import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import os

/// Maximum number of apps with their own volume (each one gets its own tap).
let maxAppTaps = 31

/// Hands the settings from the main thread to the audio thread.
/// The audio thread only *tries* to take the lock: it never waits.
final class ParameterMailbox: @unchecked Sendable {
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var parameters = DSPParameters()
    private var appGains = SIMD32<Float>(repeating: 1)
    private var version: UInt64 = 1

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    func post(_ p: DSPParameters, appGains gains: SIMD32<Float>) {
        os_unfair_lock_lock(lock)
        parameters = p
        appGains = gains
        version &+= 1
        os_unfair_lock_unlock(lock)
    }

    /// New values since `seen`, or nil (nothing new, or the main thread is writing right now).
    @inline(__always)
    func take(since seen: UInt64) -> (DSPParameters, SIMD32<Float>, UInt64)? {
        guard os_unfair_lock_trylock(lock) else { return nil }
        defer { os_unfair_lock_unlock(lock) }
        guard version != seen else { return nil }
        return (parameters, appGains, version)
    }
}

/// Everything the audio thread touches. Allocated once per audio graph.
final class RenderContext: @unchecked Sendable {
    let processor: SoundProcessor
    private let mailbox: ParameterMailbox
    private var seen: UInt64 = 0
    /// Number of taps at the end of the input buffer list: the global tap, then one per app.
    private let tapCount: Int
    private var gains = SIMD32<Float>(repeating: 1)
    private var appliedGains = SIMD32<Float>(repeating: 1)
    private let capacity = 4096
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>

    init(sampleRate: Double, tapCount: Int, mailbox: ParameterMailbox) {
        processor = SoundProcessor(sampleRate: sampleRate)
        self.mailbox = mailbox
        self.tapCount = tapCount
        left = .allocate(capacity: capacity)
        right = .allocate(capacity: capacity)
        left.initialize(repeating: 0, count: capacity)
        right.initialize(repeating: 0, count: capacity)
        if let new = mailbox.take(since: 0) {
            processor.apply(new.0)
            gains = new.1
            appliedGains = new.1
            seen = new.2
        }
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    /// The IOProc: mixes the taps, processes, writes to the output device.
    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        if let new = mailbox.take(since: seen) {
            processor.apply(new.0)
            gains = new.1
            seen = new.2
        }
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        guard outputs.count > 0 else { return }

        // Frames requested by the output device.
        var frames = Int.max
        for buffer in outputs where buffer.mNumberChannels > 0 {
            frames = min(frames, Int(buffer.mDataByteSize) / (4 * Int(buffer.mNumberChannels)))
        }
        if frames == Int.max { frames = 0 }
        let totalOutputChannels = outputs.reduce(0) { $0 + Int($1.mNumberChannels) }

        var offset = 0
        let firstTap = max(inputs.count - tapCount, 0)
        let previousGains = appliedGains
        while offset < frames {
            let chunk = min(capacity, frames - offset)
            left.update(repeating: 0, count: chunk)
            right.update(repeating: 0, count: chunk)

            // 1. Mix: the global tap (index 0), then each app at its own volume.
            for t in 0..<min(tapCount, inputs.count - firstTap) {
                let buffer = inputs[firstTap + t]
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self), buffer.mNumberChannels > 0 else { continue }
                let channels = Int(buffer.mNumberChannels)
                let available = Int(buffer.mDataByteSize) / (4 * channels) - offset
                let n = min(chunk, max(available, 0))
                if n == 0 { continue }
                var g: Float = 1, dg: Float = 0
                if t > 0 {
                    // Ramp from the previous volume to avoid a click.
                    let start = previousGains[t - 1], end = gains[t - 1]
                    g = start
                    dg = (end - start) / Float(max(frames, 1))
                    g += dg * Float(offset)
                }
                let base = data + offset * channels
                if channels == 1 {
                    for i in 0..<n {
                        let s = base[i] * g
                        left[i] += s
                        right[i] += s
                        g += dg
                    }
                } else {
                    for i in 0..<n {
                        left[i] += base[i * channels] * g
                        right[i] += base[i * channels + 1] * g
                        g += dg
                    }
                }
            }

            // 2. Effects.
            processor.process(left: left, right: right, frames: chunk)

            // 3. Output: left and right on the first two channels, silence on the others.
            var channelBase = 0
            for buffer in outputs {
                let channels = Int(buffer.mNumberChannels)
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self), channels > 0 else {
                    channelBase += channels
                    continue
                }
                let base = data + offset * channels
                for c in 0..<channels {
                    let global = channelBase + c
                    if totalOutputChannels == 1 {
                        for i in 0..<chunk { base[i] = (left[i] + right[i]) * 0.5 }
                    } else if global == 0 {
                        for i in 0..<chunk { base[i * channels + c] = left[i] }
                    } else if global == 1 {
                        for i in 0..<chunk { base[i * channels + c] = right[i] }
                    } else {
                        for i in 0..<chunk { base[i * channels + c] = 0 }
                    }
                }
                channelBase += channels
            }
            offset += chunk
        }
        appliedGains = gains
    }
}

/// One running audio graph: taps → private aggregate device → IOProc → output device.
private final class AudioGraph {
    var taps: [AudioObjectID] = []
    var aggregate = AudioObjectID.unknown
    var proc: AudioDeviceIOProcID?
    var context: RenderContext?
    let outputDevice: AudioDeviceID
    /// Keys of the apps with their own tap, in tap order.
    let appKeys: [String]
    let appObjects: [[AudioObjectID]]

    init(outputDevice: AudioDeviceID, appKeys: [String], appObjects: [[AudioObjectID]]) {
        self.outputDevice = outputDevice
        self.appKeys = appKeys
        self.appObjects = appObjects
    }

    func teardown() {
        if aggregate.isValid {
            if let proc {
                AudioDeviceStop(aggregate, proc)
                AudioDeviceDestroyIOProcID(aggregate, proc)
            }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        for tap in taps where tap.isValid {
            AudioHardwareDestroyProcessTap(tap)
        }
        proc = nil
        aggregate = .unknown
        taps = []
        context = nil
    }
}

/// Captures the sound of every app, processes it and plays it on the current output device.
@MainActor
final class AudioEngine: ObservableObject {
    enum State: Equatable {
        case off
        case running
        case needsPermission
        case failed(String)
    }

    @Published private(set) var state: State = .off
    @Published private(set) var outputDeviceName = ""

    private let mailbox = ParameterMailbox()
    private var graph: AudioGraph?
    private var wanted = false
    private var restartWork: DispatchWorkItem?
    private var listeners: [PropertyListener] = []
    private var deviceListeners: [PropertyListener] = []
    private var wakeObserver: NSObjectProtocol?
    private var failures = 0

    private var parameters = DSPParameters()
    private var appGains: [String: Float] = [:]
    /// Returns the audio objects of each app that has its own volume.
    var appGroups: () -> [(key: String, objects: [AudioObjectID])] = { [] }

    init() {
        if let l = PropertyListener(.system, kAudioHardwarePropertyDefaultOutputDevice, { [weak self] in
            MainActor.assumeIsolated { self?.outputDeviceChanged() }
        }) { listeners.append(l) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRestart(after: 1.0) }
        }
        refreshDeviceName()
    }

    // MARK: Control

    func start() {
        wanted = true
        guard graph == nil else { return }
        AudioPermission.request { [weak self] granted in
            guard let self, self.wanted, self.graph == nil else { return }
            if granted {
                self.build()
            } else {
                self.state = .needsPermission
            }
        }
    }

    func stop() {
        wanted = false
        restartWork?.cancel()
        teardown()
        state = .off
    }

    func update(_ p: DSPParameters) {
        guard p != parameters else { return }
        parameters = p
        post()
    }

    /// Volume of an app (0…1.5). Apps without their own tap get one at the next rebuild.
    func setAppGain(_ key: String, _ gain: Float) {
        appGains[key] = gain
        post()
        reconcileApps()
    }

    func removeAppGain(_ key: String) {
        appGains[key] = nil
        reconcileApps()
    }

    /// Rebuilds the graph if the set of apps with their own volume changed
    /// (an app was added, quit, or opened a new audio process).
    func reconcileApps() {
        guard let graph, wanted else { return }
        let groups = currentGroups()
        if groups.map(\.key) != graph.appKeys || groups.map(\.objects) != graph.appObjects {
            scheduleRestart(after: 0.15)
        }
    }

    // MARK: Graph

    private func currentGroups() -> [(key: String, objects: [AudioObjectID])] {
        let groups = appGroups()
            .filter { appGains[$0.key] != nil && !$0.objects.isEmpty }
            .map { (key: $0.key, objects: $0.objects.sorted()) }
            .sorted { $0.key < $1.key }
        return Array(groups.prefix(maxAppTaps))
    }

    private func post() {
        var gains = SIMD32<Float>(repeating: 1)
        if let graph {
            for (i, key) in graph.appKeys.enumerated() where i < 32 {
                gains[i] = min(max(appGains[key] ?? 1, 0), 1.5)
            }
        }
        mailbox.post(parameters, appGains: gains)
    }

    private func build() {
        teardown()
        do {
            let graph = try makeGraph()
            self.graph = graph
            post()
            failures = 0
            state = .running
            watch(graph.outputDevice)
        } catch {
            teardown()
            NSLog("Relief: could not start the audio engine: \(error.localizedDescription)")
            failures += 1
            state = .failed(error.localizedDescription)
            // Devices are often busy for a moment after a change: try again a few times.
            if failures < 4 { scheduleRestart(after: Double(failures)) }
        }
        refreshDeviceName()
    }

    private func makeGraph() throws -> AudioGraph {
        let output = try AudioObjectID.defaultOutputDevice()
        guard output.isValid else { throw CoreAudioError(what: S.noOutputDevice, status: 0) }
        let outputUID = output.deviceUID
        guard !outputUID.isEmpty else { throw CoreAudioError(what: S.noOutputDevice, status: 0) }
        guard output.outputChannelCount > 0 else { throw CoreAudioError(what: S.noOutputDevice, status: 0) }

        let groups = currentGroups()
        let graph = AudioGraph(outputDevice: output, appKeys: groups.map(\.key), appObjects: groups.map(\.objects))

        // Our own process is excluded, otherwise Relief would hear itself (feedback).
        var excluded: [AudioObjectID] = []
        if let me = AudioObjectID.processObject(for: getpid()) { excluded.append(me) }
        excluded += groups.flatMap(\.objects)

        var tapUIDs: [String] = []
        func makeTap(_ description: CATapDescription) throws {
            description.uuid = UUID()
            description.name = "Relief"
            description.muteBehavior = .mutedWhenTapped
            var tap = AudioObjectID.unknown
            try check(AudioHardwareCreateProcessTap(description, &tap), S.cannotCaptureAudio)
            graph.taps.append(tap)
            tapUIDs.append(description.uuid.uuidString)
            if let format = tap.tapFormat {
                guard format.mFormatID == kAudioFormatLinearPCM,
                      format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                      format.mBitsPerChannel == 32 else {
                    throw CoreAudioError(what: S.unsupportedFormat, status: 0)
                }
            }
        }
        do {
            try makeTap(CATapDescription(stereoGlobalTapButExcludeProcesses: excluded))
            for group in groups {
                try makeTap(CATapDescription(stereoMixdownOfProcesses: group.objects))
            }

            let description: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Relief",
                kAudioAggregateDeviceUIDKey: "com.lightmaster.relief.aggregate.\(UUID().uuidString)",
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: tapUIDs.map {
                    [kAudioSubTapUIDKey: $0, kAudioSubTapDriftCompensationKey: true] as [String: Any]
                },
            ]
            var aggregate = AudioObjectID.unknown
            try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate), S.cannotCaptureAudio)
            graph.aggregate = aggregate

            var sampleRate = aggregate.nominalSampleRate
            if sampleRate <= 0 { sampleRate = output.nominalSampleRate }
            if sampleRate <= 0 { sampleRate = 48000 }

            let context = RenderContext(sampleRate: sampleRate, tapCount: graph.taps.count, mailbox: mailbox)
            graph.context = context
            var proc: AudioDeviceIOProcID?
            try check(AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, _, output, _ in
                context.render(input: input, output: output)
            }, S.cannotCaptureAudio)
            graph.proc = proc
            if let proc { aggregate.useOnlyLastInputStreams(graph.taps.count, for: proc) }
            try check(AudioDeviceStart(aggregate, proc), S.cannotCaptureAudio)
        } catch {
            graph.teardown()
            throw error
        }
        return graph
    }

    private func teardown() {
        deviceListeners = []
        graph?.teardown()
        graph = nil
    }

    // MARK: Changes

    private func watch(_ device: AudioDeviceID) {
        deviceListeners = []
        let restart: () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRestart(after: 0.3) }
        }
        for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive,
                         kAudioDevicePropertyStreamConfiguration] {
            if let l = PropertyListener(device, selector, restart) { deviceListeners.append(l) }
        }
    }

    private func outputDeviceChanged() {
        refreshDeviceName()
        if wanted { scheduleRestart(after: 0.3) }
    }

    private func scheduleRestart(after delay: Double) {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.wanted, self.state != .needsPermission else { return }
                self.build()
            }
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func refreshDeviceName() {
        let device = (try? AudioObjectID.defaultOutputDevice()) ?? .unknown
        outputDeviceName = device.isValid ? device.name : ""
    }
}
