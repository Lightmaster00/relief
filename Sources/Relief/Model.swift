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
    static let autoStandby = "engine.autoStandby"
    static let autoOutputMode = "sound.autoOutputMode"
    static let outputModes = "sound.outputModes"
    static let headphoneProfiles = "sound.headphoneProfiles"
}

/// The app's state: settings, presets, per-app volumes and the audio engine.
@MainActor
final class ReliefModel: ObservableObject {
    static let shared = ReliefModel()

    let engine = AudioEngine()
    let monitor = AppAudioMonitor()
    let devices = OutputDevices()

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

    @Published var autoStandby: Bool {
        didSet {
            UserDefaults.standard.set(autoStandby, forKey: PrefKey.autoStandby)
            engine.autoStandby = autoStandby
        }
    }

    /// Chooses Speakers or Headphones by itself when the output changes.
    @Published var autoOutputMode: Bool {
        didSet {
            UserDefaults.standard.set(autoOutputMode, forKey: PrefKey.autoOutputMode)
            if autoOutputMode { applyOutputModeForCurrentRoute() }
        }
    }

    /// Speakers or Headphones chosen by the user for each output (device + data source).
    private var outputModes: [String: String]
    /// Headphone model chosen for each output (AirPods, a wired pair…).
    private var headphoneProfiles: [String: String]
    private var hotKeyIDs: [UInt32] = []

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
        autoStandby = defaults.object(forKey: PrefKey.autoStandby) as? Bool ?? true
        autoOutputMode = defaults.object(forKey: PrefKey.autoOutputMode) as? Bool ?? true
        outputModes = defaults.dictionary(forKey: PrefKey.outputModes) as? [String: String] ?? [:]
        headphoneProfiles = defaults.dictionary(forKey: PrefKey.headphoneProfiles) as? [String: String] ?? [:]
        engine.autoStandby = autoStandby

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
        devices.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)

        // A new output (AirPods connected, headphones plugged in): pick the matching 3D mode.
        Publishers.CombineLatest(devices.$current.map { $0?.uid }, devices.$dataSource)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .dropFirst()
            .sink { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyOutputModeForCurrentRoute() } }
            }
            .store(in: &cancellables)
        applyOutputModeForCurrentRoute()

        NotificationCenter.default.addObserver(forName: ShortcutStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerShortcuts() }
        }
        NotificationCenter.default.addObserver(forName: ShortcutStore.recordingDidChange, object: nil, queue: .main) { [weak self] note in
            // While a shortcut is being recorded, the existing ones must not fire.
            MainActor.assumeIsolated {
                if (note.object as? Bool) == true { self?.unregisterShortcuts() } else { self?.registerShortcuts() }
            }
        }
    }

    func startIfEnabled() {
        if isOn { engine.start() }
    }

    func shutdown() {
        saveNow()
        engine.stop()
    }

    // MARK: Speakers / headphones

    private var routeKey: String? {
        guard let device = devices.current else { return nil }
        return "\(device.uid)#\(devices.dataSource)"
    }

    /// Chosen in the interface: also remembered for the current output.
    func setOutputMode(_ mode: OutputMode) {
        settings.outputMode = mode
        if let key = routeKey {
            outputModes[key] = mode.rawValue
            UserDefaults.standard.set(outputModes, forKey: PrefKey.outputModes)
        }
    }

    /// Chosen in the interface: remembered for the current output.
    func setHeadphoneProfile(_ name: String?) {
        settings.headphoneProfile = name
        if let key = routeKey {
            headphoneProfiles[key] = name
            UserDefaults.standard.set(headphoneProfiles, forKey: PrefKey.headphoneProfiles)
        }
    }

    private func applyOutputModeForCurrentRoute() {
        // The headphone model follows the output, whatever the automatic mode setting.
        if let key = routeKey {
            let profile = headphoneProfiles[key]
            if settings.headphoneProfile != profile { settings.headphoneProfile = profile }
        }
        guard autoOutputMode, let device = devices.current, let key = routeKey else { return }
        let mode: OutputMode
        if let stored = outputModes[key], let m = OutputMode(rawValue: stored) {
            mode = m
        } else {
            mode = OutputDevices.looksLikeHeadphones(transport: device.transport, dataSource: devices.dataSource)
                ? .headphones : .speakers
        }
        if settings.outputMode != mode { settings.outputMode = mode }
    }

    // MARK: Shortcuts

    func registerShortcuts() {
        unregisterShortcuts()
        for action in ShortcutAction.allCases {
            guard let combo = ShortcutStore.combo(for: action) else { continue }
            if let id = HotKeyCenter.shared.register(keyCode: combo.keyCode, modifiers: combo.modifiers, handler: { [weak self] in
                self?.perform(action)
            }) {
                hotKeyIDs.append(id)
            }
        }
    }

    private func unregisterShortcuts() {
        for id in hotKeyIDs { HotKeyCenter.shared.unregister(id) }
        hotKeyIDs = []
    }

    /// Opens the panel (set by the app delegate).
    var showPanel: () -> Void = {}

    func perform(_ action: ShortcutAction) {
        switch action {
        case .toggleRelief:
            isOn.toggle()
            HUD.shared.show(symbol: isOn ? "speaker.wave.3.fill" : "speaker.slash.fill",
                            text: isOn ? S.reliefOn : S.reliefOff)
        case .showPanel:
            showPanel()
        case .toggleEqualizer:
            settings.equalizerEnabled.toggle()
            HUD.shared.show(symbol: "slider.vertical.3",
                            text: "\(S.equalizer) — \(settings.equalizerEnabled ? S.on : S.off)")
        case .nextPreset:
            let presets = allPresets
            let index = presets.firstIndex { $0.id == settings.presetID } ?? -1
            let next = presets[(index + 1) % presets.count]
            apply(next)
            HUD.shared.show(symbol: "slider.vertical.3", text: next.localizedName)
        case .toggleOutputMode:
            setOutputMode(settings.outputMode == .speakers ? .headphones : .speakers)
            HUD.shared.show(symbol: settings.outputMode == .speakers ? "hifispeaker.2.fill" : "headphones",
                            text: settings.outputMode == .speakers ? S.speakers : S.headphones)
        case .toggleNightMode:
            settings.nightMode.toggle()
            HUD.shared.show(symbol: "moon.fill", text: "\(S.nightMode) — \(settings.nightMode ? S.on : S.off)")
        case .boostUp, .boostDown:
            let step: Float = 1.0 / 6 // 2 dB
            let value = settings.boost + (action == .boostUp ? step : -step)
            settings.boost = min(max((value * 6).rounded() / 6, 0), 1)
            HUD.shared.show(symbol: "speaker.wave.3.fill",
                            text: settings.boost == 0 ? "\(S.booster) — \(S.off)"
                                                      : String(format: "\(S.booster) +%.0f dB", settings.boost * 12))
        }
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

    func resetAllAppVolumes() {
        for key in appVolumes.keys { engine.removeAppGain(key) }
        appVolumes = [:]
        volumeBeforeMute = [:]
        storeVolumes()
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
