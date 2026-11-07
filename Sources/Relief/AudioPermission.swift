import AppKit
import Foundation

/// "System Audio Recording" permission (Settings › Privacy & Security › Screen & System Audio Recording).
///
/// macOS has no public API to read this permission. Without it, a tap delivers silence while
/// still muting the original sound, so Relief must never start the engine before access is granted.
/// The TCC framework is queried when it's available; otherwise Relief assumes access and
/// relies on the system prompt.
enum AudioPermission {
    enum Status { case authorized, denied, unknown }

    private typealias PreflightFunc = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFunc = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static let service = "kTCCServiceAudioCapture" as CFString

    private static let tcc: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    static var status: Status {
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessPreflight") else { return .unknown }
        let preflight = unsafeBitCast(symbol, to: PreflightFunc.self)
        switch preflight(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    /// Shows the system prompt if needed. The completion runs on the main thread.
    static func request(_ completion: @escaping @MainActor (Bool) -> Void) {
        switch status {
        case .authorized:
            Task { @MainActor in completion(true) }
            return
        case .denied:
            Task { @MainActor in completion(false) }
            return
        case .unknown:
            break
        }
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessRequest") else {
            // No way to ask in advance: the prompt appears when the first tap is created.
            Task { @MainActor in completion(true) }
            return
        }
        let request = unsafeBitCast(symbol, to: RequestFunc.self)
        request(service, nil) { granted in
            Task { @MainActor in completion(granted) }
        }
    }

    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
