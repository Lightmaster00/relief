import AppKit
import CoreAudio
import Foundation

/// An app that plays (or played) sound, with all its audio processes
/// (a browser plays through helper processes, for example).
struct AudioApp: Identifiable, Equatable {
    /// Bundle identifier of the app, or "pid.<n>" without one.
    let id: String
    let name: String
    let pid: pid_t
    var objects: [AudioObjectID]
    var isPlaying: Bool

    static func == (a: AudioApp, b: AudioApp) -> Bool {
        a.id == b.id && a.name == b.name && a.objects == b.objects && a.isPlaying == b.isPlaying
    }

    @MainActor var icon: NSImage? {
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon { return icon }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}

/// Lists the apps that use the audio system.
@MainActor
final class AppAudioMonitor: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []
    private var listener: PropertyListener?
    private var timer: Timer?
    var onChange: () -> Void = {}

    private typealias ResponsibleFunc = @convention(c) (pid_t) -> pid_t
    private static let responsiblePID: ResponsibleFunc? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibleFunc.self)
    }()

    init() {
        listener = PropertyListener(.system, kAudioHardwarePropertyProcessObjectList) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Refreshes the "playing" state regularly while the interface is visible.
    func setVisible(_ visible: Bool) {
        timer?.invalidate()
        timer = nil
        guard visible else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let me = getpid()
        let running = NSWorkspace.shared.runningApplications
        let regular = running.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
        var byKey: [String: AudioApp] = [:]
        var order: [String] = []

        for object in AudioObjectID.processObjects() {
            let pid = object.processPID
            guard pid > 0, pid != me else { continue }
            let bundleID = object.processBundleID
            let owner = Self.owner(pid: pid, bundleID: bundleID, regular: regular)
            guard let owner else { continue }
            let playing = object.processIsRunningOutput
            if var existing = byKey[owner.key] {
                existing.objects.append(object)
                existing.isPlaying = existing.isPlaying || playing
                byKey[owner.key] = existing
            } else {
                byKey[owner.key] = AudioApp(id: owner.key, name: owner.name, pid: owner.pid,
                                            objects: [object], isPlaying: playing)
                order.append(owner.key)
            }
        }
        let list = order.compactMap { byKey[$0] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if list != apps {
            apps = list
            onChange()
        }
    }

    /// The app a process belongs to: itself, the app responsible for it, or the app
    /// whose identifier its own starts with ("com.google.Chrome.helper" → Chrome).
    private static func owner(pid: pid_t, bundleID: String,
                              regular: [NSRunningApplication]) -> (key: String, name: String, pid: pid_t)? {
        func entry(_ app: NSRunningApplication) -> (key: String, name: String, pid: pid_t)? {
            guard let id = app.bundleIdentifier else { return nil }
            return (id, app.localizedName ?? id, app.processIdentifier)
        }
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
           let e = entry(app) { return e }
        if let responsible = responsiblePID?(pid), responsible > 0, responsible != pid,
           let app = NSRunningApplication(processIdentifier: responsible), app.activationPolicy == .regular,
           let e = entry(app) { return e }
        if !bundleID.isEmpty {
            let match = regular
                .filter { bundleID.hasPrefix($0.bundleIdentifier! + ".") }
                .max { $0.bundleIdentifier!.count < $1.bundleIdentifier!.count }
            if let match, let e = entry(match) { return e }
        }
        // Background processes without an app (system sounds, daemons) are not listed.
        return nil
    }
}
