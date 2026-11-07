import AudioToolbox
import CoreAudio
import Foundation

struct CoreAudioError: LocalizedError {
    let what: String
    let status: OSStatus

    var errorDescription: String? {
        let code = UInt32(bitPattern: status)
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        let fourCC = bytes.allSatisfy { $0 >= 32 && $0 < 127 } ? " '\(String(decoding: bytes, as: UTF8.self))'" : ""
        return "\(what) (\(status)\(fourCC))"
    }
}

@inline(__always)
func check(_ status: OSStatus, _ what: @autoclosure () -> String) throws {
    if status != noErr { throw CoreAudioError(what: what(), status: status) }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    var isValid: Bool { self != .unknown }

    func address(_ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                 element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    func has(_ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var a = address(selector, scope: scope)
        return AudioObjectHasProperty(self, &a)
    }

    /// Reads a fixed-size property.
    func read<T>(_ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                 default value: T) throws -> T {
        var a = address(selector, scope: scope)
        var result = value
        var size = UInt32(MemoryLayout<T>.size)
        try check(AudioObjectGetPropertyData(self, &a, 0, nil, &size, &result), "read property \(selector)")
        return result
    }

    /// Reads a fixed-size property with a qualifier.
    func read<T, Q>(_ selector: AudioObjectPropertySelector, qualifier: Q, default value: T) throws -> T {
        var a = address(selector)
        var result = value
        var size = UInt32(MemoryLayout<T>.size)
        var q = qualifier
        let status = withUnsafeMutablePointer(to: &q) { qp in
            AudioObjectGetPropertyData(self, &a, UInt32(MemoryLayout<Q>.size), qp, &size, &result)
        }
        try check(status, "read property \(selector)")
        return result
    }

    /// Reads an array property.
    func readArray<T>(_ selector: AudioObjectPropertySelector,
                      scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                      element: T) throws -> [T] {
        var a = address(selector, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &a, 0, nil, &size), "size of property \(selector)")
        let count = Int(size) / MemoryLayout<T>.stride
        if count == 0 { return [] }
        var items = [T](repeating: element, count: count)
        try check(AudioObjectGetPropertyData(self, &a, 0, nil, &size, &items), "read property \(selector)")
        return Array(items.prefix(Int(size) / MemoryLayout<T>.stride))
    }

    /// Reads a CFString property.
    func readString(_ selector: AudioObjectPropertySelector) throws -> String {
        var a = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        try check(AudioObjectGetPropertyData(self, &a, 0, nil, &size, &value), "read string \(selector)")
        guard let value else { return "" }
        return value.takeRetainedValue() as String
    }

    // MARK: Devices

    static func defaultOutputDevice() throws -> AudioDeviceID {
        try AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID.unknown)
    }

    var deviceUID: String { (try? readString(kAudioDevicePropertyDeviceUID)) ?? "" }
    var name: String { (try? readString(kAudioObjectPropertyName)) ?? "" }

    var nominalSampleRate: Double {
        (try? read(kAudioDevicePropertyNominalSampleRate, default: Float64(0))) ?? 0
    }

    var bufferFrameSize: UInt32 {
        (try? read(kAudioDevicePropertyBufferFrameSize, default: UInt32(0))) ?? 0
    }

    var outputChannelCount: Int {
        var a = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(self, &a, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    // MARK: Processes

    static func processObjects() -> [AudioObjectID] {
        (try? AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList, element: AudioObjectID.unknown)) ?? []
    }

    static func processObject(for pid: pid_t) -> AudioObjectID? {
        let id = try? AudioObjectID.system.read(kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                qualifier: pid, default: AudioObjectID.unknown)
        guard let id, id.isValid else { return nil }
        return id
    }

    var processPID: pid_t { (try? read(kAudioProcessPropertyPID, default: pid_t(-1))) ?? -1 }
    var processBundleID: String { (try? readString(kAudioProcessPropertyBundleID)) ?? "" }
    var processIsRunningOutput: Bool {
        ((try? read(kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0) != 0
    }

    // MARK: Taps

    var tapFormat: AudioStreamBasicDescription? {
        try? read(kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
    }
}

/// Listens to a Core Audio property; the block runs on the main queue.
final class PropertyListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init?(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
          _ handler: @escaping () -> Void) {
        self.object = object
        address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        block = { _, _ in handler() }
        guard AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr else { return nil }
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
    }
}
