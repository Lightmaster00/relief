import AppKit
import Combine
import Foundation
import ServiceManagement

enum PrefKey {
    static let settings = "sound.settings"
    static let enabled = "sound.enabled"
    static let customPresets = "eq.customPresets"
    static let appVolumes = "apps.volumes"
    static let autoCheckUpdates = "updates.autoCheck"
    static let skippedVersion = "updates.skippedVersion"
    static let launchedBefore = "app.launchedBefore"
}

/// The app's state: settings, presets, per-app volumes and the audio engine.
@MainActor
final class ReliefModel: ObservableObject {
    static let shared = ReliefModel()

    let engine = AudioEngine()
    let monitor = AppAudioMonitor()

    @Published var settings: SoundSettings {
        didSet {
            guard settings != oldValue else { return }
            engine.update(settings.dspParameters)
            scheduleSave()
        }
    }

    @Published var isOn: Bool {
        didSet {
            guard isOn != oldValue else { return }
            UserDefaults.standard.set(isOn, forKey: PrefKey.enabled)
            isOn ? engine.start() : engine.stop()
        }
    }

    @Published private(set) var customPresets: [EQPreset]
    /// Volume of each app (bundle identifier → 0…1.5). Absent: 100 %, no own tap.
    @Published private(set) var appVolumes: [String: Float]

    @Published var autoCheckUpdates: Bool {
        didSet { UserDefaults.standard.set(autoCheckUpdates, forKey: PrefKey.autoCheckUpdates) }
    }

    private var saveWork: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: PrefKey.settings),
           let decoded = try? JSONDecoder().decode(SoundSettings.self, from: data) {
            settings = decoded
        } else {
            settings = SoundSettings()
        }
        isOn = defaults.object(forKey: PrefKey.enabled) as? Bool ?? true
        if let data = defaults.data(forKey: PrefKey.customPresets),
           let decoded = try? JSONDecoder().decode([EQPreset].self, from: data) {
            customPresets = decoded.map { var p = $0; p.isCustom = true; return p }
        } else {
            customPresets = []
        }
        var volumes: [String: Float] = [:]
        if let stored = defaults.dictionary(forKey: PrefKey.appVolumes) {
            for (key, value) in stored {
                if let n = value as? NSNumber, n.floatValue.isFinite {
                    volumes[key] = min(max(n.floatValue, 0), 1.5)
                }
            }
        }
        appVolumes = volumes
        autoCheckUpdates = defaults.object(forKey: PrefKey.autoCheckUpdates) as? Bool ?? true

        engine.appGroups = { [weak self] in
            guard let self else { return [] }
            return self.monitor.apps.map { (key: $0.id, objects: $0.objects) }
        }
        for (key, gain) in appVolumes { engine.setAppGain(key, gain) }
        engine.update(settings.dspParameters)
        monitor.onChange = { [weak self] in self?.engine.reconcileApps() }

        // Forward the engine's changes so views observing the model refresh.
        engine.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        monitor.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    func startIfEnabled() {
        if isOn { engine.start() }
    }

    func shutdown() {
        saveNow()
        engine.stop()
    }

    // MARK: Presets

    var allPresets: [EQPreset] { EQPreset.builtIn + customPresets }

    var currentPreset: EQPreset? {
        guard let id = settings.presetID else { return nil }
        return allPresets.first { $0.id == id }
    }

    func apply(_ preset: EQPreset) {
        var s = settings
        s.equalizerGains = preset.gains
        s.presetID = preset.id
        s.equalizerEnabled = true
        settings = s.sanitized()
    }

    func setBand(_ index: Int, _ gain: Float) {
        guard settings.equalizerGains.indices.contains(index) else { return }
        var s = settings
        s.equalizerGains[index] = min(max((gain * 2).rounded() / 2, SoundSettings.bandRange.lowerBound),
                                      SoundSettings.bandRange.upperBound)
        s.presetID = allPresets.first { $0.gains == s.equalizerGains }?.id
        settings = s
    }

    func saveCurrentAsPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = EQPreset(id: "custom.\(UUID().uuidString)", name: String(trimmed.prefix(40)),
                              gains: settings.equalizerGains, isCustom: true)
        customPresets.append(preset)
        storePresets()
        settings.presetID = preset.id
    }

    func deletePreset(_ preset: EQPreset) {
        guard preset.isCustom else { return }
        customPresets.removeAll { $0.id == preset.id }
        storePresets()
        if settings.presetID == preset.id { settings.presetID = nil }
    }

    private func storePresets() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: PrefKey.customPresets)
        }
    }

    // MARK: Apps

    func volume(of app: AudioApp) -> Float { appVolumes[app.id] ?? 1 }

    func setVolume(_ volume: Float, for app: AudioApp) {
        let v = min(max(volume.isFinite ? volume : 1, 0), 1.5)
        appVolumes[app.id] = v
        engine.setAppGain(app.id, v)
        storeVolumes()
    }

    /// Volume each app had before being muted, to restore it.
    private var volumeBeforeMute: [String: Float] = [:]

    func toggleMute(_ app: AudioApp) {
        let current = volume(of: app)
        if current == 0 {
            setVolume(volumeBeforeMute.removeValue(forKey: app.id) ?? 1, for: app)
        } else {
            volumeBeforeMute[app.id] = current
            setVolume(0, for: app)
        }
    }

    func resetVolume(for app: AudioApp) {
        volumeBeforeMute[app.id] = nil
        appVolumes[app.id] = nil
        engine.removeAppGain(app.id)
        storeVolumes()
    }

    /// Apps shown in the list: those playing, and those with their own volume.
    var visibleApps: [AudioApp] {
        monitor.apps.filter { $0.isPlaying || appVolumes[$0.id] != nil }
    }

    private func storeVolumes() {
        UserDefaults.standard.set(appVolumes.mapValues { NSNumber(value: $0) }, forKey: PrefKey.appVolumes)
    }

    // MARK: Saving

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func saveNow() {
        saveWork?.cancel()
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: PrefKey.settings)
        }
    }

    func resetAll() {
        settings = SoundSettings()
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Relief: launch at login: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}
