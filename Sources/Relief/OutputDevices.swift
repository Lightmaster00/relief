import AudioToolbox
import CoreAudio
import Foundation

/// A sound output the user can choose.
struct OutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32

    var symbol: String {
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt: return "hifispeaker"
        default: return "speaker.wave.2"
        }
    }
}

extension AudioObjectID {
    var transportType: UInt32 { (try? read(kAudioDevicePropertyTransportType, default: UInt32(0))) ?? 0 }

    /// Current data source of an output (built-in output: internal speakers or headphones jack).
    var outputDataSource: UInt32 {
        guard has(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput) else { return 0 }
        return (try? read(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput, default: UInt32(0))) ?? 0
    }

    var isHidden: Bool { ((try? read(kAudioDevicePropertyIsHidden, default: UInt32(0))) ?? 0) != 0 }

    static func allDevices() -> [AudioDeviceID] {
        (try? AudioObjectID.system.readArray(kAudioHardwarePropertyDevices, element: AudioDeviceID.unknown)) ?? []
    }
}

/// Lists the outputs, follows the system output and controls its volume.
@MainActor
final class OutputDevices: ObservableObject {
    @Published private(set) var devices: [OutputDevice] = []
    @Published private(set) var current: OutputDevice?
    /// System volume of the current output (0…1), or nil if it has no volume control.
    @Published private(set) var volume: Float?
    @Published private(set) var isMuted = false
    /// Current data source of the output ('hdpn' when headphones are plugged into the jack).
    @Published private(set) var dataSource: UInt32 = 0

    private var systemListeners: [PropertyListener] = []
    private var deviceListeners: [PropertyListener] = []

    static let headphonesDataSource: UInt32 = 0x6864_706E // 'hdpn'

    init() {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            if let l = PropertyListener(.system, selector, { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }) { systemListeners.append(l) }
        }
        refresh()
    }

    func refresh() {
        devices = AudioObjectID.allDevices().compactMap { id -> OutputDevice? in
            guard id.outputChannelCount > 0, !id.isHidden else { return nil }
            let uid = id.deviceUID
            // Relief's own private devices are never offered.
            guard !uid.isEmpty, !uid.hasPrefix("com.lightmaster.relief.") else { return nil }
            return OutputDevice(id: id, uid: uid, name: id.name, transport: id.transportType)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let defaultID = (try? AudioObjectID.defaultOutputDevice()) ?? .unknown
        let newCurrent = devices.first { $0.id == defaultID }
        if newCurrent?.id != current?.id {
            current = newCurrent
            watchCurrent()
        }
        refreshVolume()
    }

    /// Makes a device the system output (like choosing it in Control Center).
    func select(_ device: OutputDevice) {
        var id = device.id
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(.system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        if status != noErr { NSLog("Relief: could not select output \(device.name) (\(status))") }
        refresh()
    }

    func setVolume(_ value: Float) {
        guard let device = current?.id else { return }
        let v = min(max(value.isFinite ? value : 0, 0), 1)
        if !Self.setVirtualVolume(device, v) {
            for channel: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
                _ = Self.setScalar(device, kAudioDevicePropertyVolumeScalar, channel, v)
            }
        }
        if v > 0, isMuted { setMuted(false) }
        refreshVolume()
    }

    func setMuted(_ muted: Bool) {
        guard let device = current?.id else { return }
        var value: UInt32 = muted ? 1 : 0
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return }
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        refreshVolume()
    }

    // MARK: Private

    private func watchCurrent() {
        deviceListeners = []
        guard let device = current?.id else { return }
        let update: () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.refreshVolume() }
        }
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar,
            kAudioDevicePropertyMute, kAudioDevicePropertyDataSource,
        ]
        for selector in selectors {
            if let l = PropertyListener(device, selector, scope: kAudioObjectPropertyScopeOutput, update) {
                deviceListeners.append(l)
            }
        }
    }

    private func refreshVolume() {
        guard let device = current?.id else {
            volume = nil
            isMuted = false
            dataSource = 0
            return
        }
        let newVolume = Self.virtualVolume(device) ?? Self.scalar(device, kAudioDevicePropertyVolumeScalar)
        if newVolume != volume { volume = newVolume }
        let muted = ((try? device.read(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput,
                                       default: UInt32(0))) ?? 0) != 0
        if muted != isMuted { isMuted = muted }
        let source = device.outputDataSource
        if source != dataSource { dataSource = source }
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput, mElement: element)
    }

    private static func virtualVolume(_ device: AudioDeviceID) -> Float? {
        var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectHasProperty(device, &a) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func setVirtualVolume(_ device: AudioDeviceID, _ v: Float) -> Bool {
        var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &a),
              AudioObjectIsPropertySettable(device, &a, &settable) == noErr, settable.boolValue else { return false }
        var value = Float32(v)
        return AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    private static func scalar(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Float? {
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1] {
            var a = address(selector, element)
            guard AudioObjectHasProperty(device, &a) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr { return value }
        }
        return nil
    }

    @discardableResult
    private static func setScalar(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                                  _ element: UInt32, _ v: Float) -> Bool {
        var a = address(selector, element)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &a),
              AudioObjectIsPropertySettable(device, &a, &settable) == noErr, settable.boolValue else { return false }
        var value = Float32(v)
        return AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    /// Whether an output is most likely headphones: Bluetooth audio, or the headphones jack.
    static func looksLikeHeadphones(transport: UInt32, dataSource: UInt32) -> Bool {
        if dataSource == headphonesDataSource { return true }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}
