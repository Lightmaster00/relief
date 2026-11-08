import CoreAudio
import XCTest
@testable import Relief

final class BiquadTests: XCTestCase {
    func testPeakingGainAtCentre() {
        let f = Biquad.peaking(frequency: 1000, q: 1.25, gainDB: 6, sampleRate: 48000)
        XCTAssertEqual(f.responseDB(at: 1000, sampleRate: 48000), 6, accuracy: 0.05)
        XCTAssertEqual(f.responseDB(at: 50, sampleRate: 48000), 0, accuracy: 0.2)
    }

    func testZeroGainIsIdentity() {
        XCTAssertEqual(Biquad.peaking(frequency: 1000, q: 1, gainDB: 0, sampleRate: 48000), .identity)
        XCTAssertEqual(Biquad.lowShelf(frequency: 100, gainDB: 0, sampleRate: 48000), .identity)
    }

    func testShelves() {
        let low = Biquad.lowShelf(frequency: 110, gainDB: 8, sampleRate: 44100)
        XCTAssertEqual(low.responseDB(at: 20, sampleRate: 44100), 8, accuracy: 0.5)
        XCTAssertEqual(low.responseDB(at: 10000, sampleRate: 44100), 0, accuracy: 0.2)
        let high = Biquad.highShelf(frequency: 7000, gainDB: -6, sampleRate: 96000)
        XCTAssertEqual(high.responseDB(at: 30000, sampleRate: 96000), -6, accuracy: 0.5)
        XCTAssertEqual(high.responseDB(at: 100, sampleRate: 96000), 0, accuracy: 0.2)
    }

    func testFrequencyAboveNyquistIsClamped() {
        let f = Biquad.peaking(frequency: 40000, q: 1, gainDB: 6, sampleRate: 44100)
        for v in [f.b0, f.b1, f.b2, f.a1, f.a2] { XCTAssertTrue(v.isFinite) }
    }
}

final class ProcessorTests: XCTestCase {
    private func run(_ p: DSPParameters, sampleRate: Double = 48000, frames: Int = 512, blocks: Int = 200,
                     signal: (Int) -> (Float, Float)) -> (peak: Float, left: [Float], right: [Float]) {
        let processor = SoundProcessor(sampleRate: sampleRate)
        processor.apply(p)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { l.deallocate(); r.deallocate() }
        var peak: Float = 0
        var lastL: [Float] = [], lastR: [Float] = []
        var t = 0
        for _ in 0..<blocks {
            for i in 0..<frames {
                let (a, b) = signal(t)
                l[i] = a
                r[i] = b
                t += 1
            }
            processor.process(left: l, right: r, frames: frames)
            for i in 0..<frames {
                XCTAssertTrue(l[i].isFinite && r[i].isFinite)
                peak = max(peak, abs(l[i]), abs(r[i]))
            }
            lastL = Array(UnsafeBufferPointer(start: l, count: frames))
            lastR = Array(UnsafeBufferPointer(start: r, count: frames))
        }
        return (peak, lastL, lastR)
    }

    func testNeutralSettingsPassThrough() {
        let out = run(DSPParameters()) { t in
            let s = Float(sin(Double(t) * 2 * .pi * 440 / 48000)) * 0.5
            return (s, -s)
        }
        XCTAssertEqual(out.peak, 0.5, accuracy: 0.01)
    }

    func testLimiterNeverExceedsCeiling() {
        var p = DSPParameters()
        p.boostDB = 12
        p.bassDB = 10
        p.equalizerEnabled = true
        for i in 0..<10 { p.equalizerGains[i] = 12 }
        p.nightMode = true
        p.surround = 1
        p.ambience = 1
        let out = run(p) { t in
            let s = Float(sin(Double(t) * 2 * .pi * 60 / 48000)) * 0.99
            return (s, s * 0.8)
        }
        XCTAssertLessThanOrEqual(out.peak, SoundProcessor.ceiling + 1e-6)
    }

    func testEverySampleRateAndBlockSize() {
        var p = DSPParameters()
        p.surround = 0.7
        p.headphones = true
        p.ambience = 0.5
        p.clarity = 0.5
        for sr in [22050.0, 44100, 48000, 88200, 96000, 192000] {
            for frames in [1, 15, 64, 512, 4096] {
                let out = run(p, sampleRate: sr, frames: frames, blocks: 20) { t in
                    (Float(sin(Double(t) * 0.05)) * 0.5, Float(cos(Double(t) * 0.031)) * 0.5)
                }
                XCTAssertLessThanOrEqual(out.peak, SoundProcessor.ceiling + 1e-6)
            }
        }
    }

    func testMonoStaysCentredOnSpeakers() {
        var p = DSPParameters()
        p.surround = 1
        p.ambience = 0
        let out = run(p) { t in
            let s = Float(sin(Double(t) * 2 * .pi * 1000 / 48000)) * 0.3
            return (s, s)
        }
        for i in out.left.indices { XCTAssertEqual(out.left[i], out.right[i], accuracy: 1e-5) }
    }

    func testSilenceStaysSilent() {
        var p = DSPParameters()
        p.boostDB = 12
        p.nightMode = true
        p.ambience = 1
        p.surround = 1
        p.headphones = true
        let out = run(p) { _ in (0, 0) }
        XCTAssertEqual(out.peak, 0)
    }

    func testNaNInputIsContained() {
        let out = run(DSPParameters(), blocks: 4) { t in
            t == 100 ? (.nan, .infinity) : (0.1, 0.1)
        }
        XCTAssertTrue(out.peak.isFinite)
        XCTAssertEqual(out.left.last ?? 0, 0.1, accuracy: 0.01)
    }

    func testBoosterGain() {
        var p = DSPParameters()
        p.boostDB = 6
        let out = run(p) { t in
            let s = Float(sin(Double(t) * 2 * .pi * 440 / 48000)) * 0.2
            return (s, s)
        }
        XCTAssertEqual(out.peak, 0.2 * pow(10, 6 / 20), accuracy: 0.01)
    }
}

final class SettingsTests: XCTestCase {
    func testPresetsHaveTenBandsInRange() {
        var ids = Set<String>()
        for preset in EQPreset.builtIn {
            XCTAssertEqual(preset.gains.count, SoundSettings.bandCount, preset.id)
            XCTAssertTrue(ids.insert(preset.id).inserted, "duplicate \(preset.id)")
            for g in preset.gains { XCTAssertTrue(SoundSettings.bandRange.contains(g)) }
        }
    }

    func testDecodingIsTolerant() throws {
        let json = #"{"boost": 7, "equalizerGains": [40, -40, 1], "surround": 0.25}"#
        let s = try JSONDecoder().decode(SoundSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.boost, 1)
        XCTAssertEqual(s.surround, 0.25)
        XCTAssertEqual(s.equalizerGains, [12, -12, 1, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(s.outputMode, .speakers)
    }

    func testRoundTrip() throws {
        var s = SoundSettings()
        s.boost = 0.5
        s.outputMode = .headphones
        s.nightMode = true
        s.equalizerGains[3] = -4.5
        let decoded = try JSONDecoder().decode(SoundSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    @MainActor func testVersionComparison() {
        XCTAssertTrue(Updater.isNewer("1.0.10", than: "1.0.9"))
        XCTAssertTrue(Updater.isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(Updater.isNewer("1.0.0", than: "1.0"))
        XCTAssertFalse(Updater.isNewer("1.0.0", than: "1.0.1"))
    }

    func testMailboxHandsOverOnlyNewValues() {
        let mailbox = ParameterMailbox()
        var p = DSPParameters()
        p.boostDB = 3
        mailbox.post(p, appGains: SIMD32(repeating: 0.5))
        let first = mailbox.take(since: 0)
        XCTAssertEqual(first?.0.boostDB, 3)
        XCTAssertEqual(first?.1[0], 0.5)
        XCTAssertNil(mailbox.take(since: first?.2 ?? 0))
    }
}

final class StandbyTests: XCTestCase {
    func testPolicy() {
        typealias P = StandbyPolicy
        // Silence: schedule standby once, then wait.
        XCTAssertEqual(P.action(enabled: true, othersPlaying: false, sleeping: false, sleepScheduled: false), .scheduleSleep)
        XCTAssertEqual(P.action(enabled: true, othersPlaying: false, sleeping: false, sleepScheduled: true), .none)
        XCTAssertEqual(P.action(enabled: true, othersPlaying: false, sleeping: true, sleepScheduled: false), .none)
        // Sound starts: cancel the countdown, or wake up.
        XCTAssertEqual(P.action(enabled: true, othersPlaying: true, sleeping: false, sleepScheduled: true), .cancelSleep)
        XCTAssertEqual(P.action(enabled: true, othersPlaying: true, sleeping: true, sleepScheduled: false), .wake)
        XCTAssertEqual(P.action(enabled: true, othersPlaying: true, sleeping: false, sleepScheduled: false), .none)
        // Turned off: never sleeps, wakes if asleep.
        XCTAssertEqual(P.action(enabled: false, othersPlaying: false, sleeping: false, sleepScheduled: false), .none)
        XCTAssertEqual(P.action(enabled: false, othersPlaying: false, sleeping: true, sleepScheduled: false), .wake)
        XCTAssertEqual(P.action(enabled: false, othersPlaying: false, sleeping: false, sleepScheduled: true), .cancelSleep)
    }
}

final class OutputAndShortcutTests: XCTestCase {
    @MainActor func testHeadphonesDetection() {
        XCTAssertTrue(OutputDevices.looksLikeHeadphones(transport: kAudioDeviceTransportTypeBluetooth, dataSource: 0))
        XCTAssertTrue(OutputDevices.looksLikeHeadphones(transport: kAudioDeviceTransportTypeBuiltIn,
                                                        dataSource: OutputDevices.headphonesDataSource))
        XCTAssertFalse(OutputDevices.looksLikeHeadphones(transport: kAudioDeviceTransportTypeBuiltIn,
                                                         dataSource: 0x6973_706B)) // 'ispk'
        XCTAssertFalse(OutputDevices.looksLikeHeadphones(transport: kAudioDeviceTransportTypeUSB, dataSource: 0))
    }

    func testKeyComboStorage() {
        let combo = KeyCombo(keyCode: 15, modifiers: 4096 | 2048 | 256)
        XCTAssertEqual(KeyCombo(stored: combo.stored), combo)
        XCTAssertNil(KeyCombo(stored: "garbage"))
        XCTAssertEqual(combo.display, "⌃⌥⌘R")
    }

    func testOnlyTheMainSwitchHasADefaultShortcut() {
        XCTAssertNotNil(ShortcutAction.toggleRelief.defaultCombo)
        for action in ShortcutAction.allCases where action != .toggleRelief {
            XCTAssertNil(action.defaultCombo, action.rawValue)
        }
    }
}

final class SpatialAndCorrectionTests: XCTestCase {
    private func sine(_ t: Int, _ f: Double, _ sr: Double = 48000) -> Float { Float(sin(Double(t) * 2 * .pi * f / sr)) }

    /// The headphone file shipped in Resources parses into thousands of sane profiles.
    func testHeadphoneLibraryParses() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/headphones.eq")
        let profiles = HeadphoneLibrary.parse(compressed: try Data(contentsOf: url))
        XCTAssertGreaterThan(profiles.count, 5000)
        XCTAssertTrue(profiles.contains { $0.name.hasPrefix("Apple AirPods Pro") })
        for p in profiles {
            XCTAssertLessThanOrEqual(p.filters.count, HeadphoneProfile.maxFilters)
            XCTAssertTrue(p.preampDB.isFinite)
        }
    }

    func testParseRejectsGarbage() {
        let text = "Good\to\t-5\tP,1000,3,1;L,105,2,0.7\nBad\to\tnan\tP,1000,3,1\nEmpty\to\t-1\tX\n"
        let profiles = HeadphoneLibrary.parse(text: text)
        XCTAssertEqual(profiles.map(\.name), ["Good"])
        XCTAssertEqual(profiles[0].filters[1].type, .lowShelf)
    }

    /// A correction with a preamp never pushes a full-scale tone past the ceiling, and changes the sound.
    func testHeadphoneCorrectionIsApplied() {
        var p = DSPParameters()
        p.headphones = true
        p.setHeadphone(HeadphoneProfile(name: "Test", kind: .overEar, preampDB: -6,
                                        filters: [.init(type: .peak, frequency: 1000, gainDB: 6, q: 1)]))
        let processor = SoundProcessor(sampleRate: 48000)
        processor.apply(p)
        let n = 512
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        var peak: Float = 0
        for block in 0..<100 {
            for i in 0..<n { let s = sine(block * n + i, 1000) * 0.5; l[i] = s; r[i] = s }
            processor.process(left: l, right: r, frames: n)
            if block > 50 { for i in 0..<n { peak = max(peak, abs(l[i])) } }
        }
        // −6 dB preamp, +6 dB at 1 kHz: back to about 0.5.
        XCTAssertEqual(peak, 0.5, accuracy: 0.05)
    }

    /// Binaural rendering stays finite, keeps a centred sound balanced, and sends a left sound mostly left.
    /// Measured on broadband noise: a room's reflections make single tones a little uneven, as in a real room.
    func testBinauralImage() {
        var b = Binaural(sampleRate: 48000)
        defer { b.free() }
        var seed: UInt32 = 12345
        func noise() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) - 0.5 }
        var cl: Float = 0, cr: Float = 0, ll: Float = 0, lr: Float = 0
        for t in 0..<96000 {
            let x = noise()
            let (l, r) = b.process(x, x, rear: 1)
            XCTAssertTrue(l.isFinite && r.isFinite)
            if t > 4800 { cl += l * l; cr += r * r }
        }
        b.clear()
        for t in 0..<96000 {
            let (l, r) = b.process(noise(), 0, rear: 1)
            if t > 4800 { ll += l * l; lr += r * r }
        }
        XCTAssertEqual(sqrt(cl / cr), 1, accuracy: 0.05)
        XCTAssertGreaterThan(sqrt(ll / lr), 1.4)
    }

    /// Moving an equalizer band glides: no sample jumps far from its neighbours.
    func testEqualizerChangeDoesNotClick() {
        let processor = SoundProcessor(sampleRate: 48000)
        var p = DSPParameters()
        p.equalizerEnabled = true
        processor.apply(p)
        let n = 256
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        var previous: Float = 0, maxStep: Float = 0
        for block in 0..<200 {
            if block == 50 { p.equalizerGains[3] = 12; processor.apply(p) }
            if block == 120 { p.equalizerGains[3] = -12; processor.apply(p) }
            for i in 0..<n { let s = sine(block * n + i, 250) * 0.3; l[i] = s; r[i] = s }
            processor.process(left: l, right: r, frames: n)
            for i in 0..<n {
                if block > 2 { maxStep = max(maxStep, abs(l[i] - previous)) }
                previous = l[i]
            }
        }
        // A 250 Hz tone at full boost moves at most ~0.04 per sample; a click would jump much more.
        XCTAssertLessThan(maxStep, 0.12)
    }

    func testMacBookPresetExists() {
        XCTAssertNotNil(EQPreset.builtIn.first { $0.id == "macbook" })
    }
}

final class SpeakerEnhancementTests: XCTestCase {
    private func process(_ p: DSPParameters, seconds: Double = 2, signal: (Int) -> (Float, Float)) -> (l: [Float], r: [Float]) {
        let processor = SoundProcessor(sampleRate: 48000)
        processor.apply(p)
        let n = 512, blocks = Int(seconds * 48000) / n
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        var outL: [Float] = [], outR: [Float] = []
        for b in 0..<blocks {
            for i in 0..<n { (l[i], r[i]) = signal(b * n + i) }
            processor.process(left: l, right: r, frames: n)
            for i in 0..<n { XCTAssertTrue(l[i].isFinite && r[i].isFinite) }
            outL += Array(UnsafeBufferPointer(start: l, count: n))
            outR += Array(UnsafeBufferPointer(start: r, count: n))
        }
        return (outL, outR)
    }

    /// Energy at one frequency (Goertzel), over the last second.
    private func energy(_ x: [Float], _ f: Double) -> Double {
        let part = x.suffix(48000)
        let k = 2 * cos(2 * .pi * f / 48000)
        var s1 = 0.0, s2 = 0.0
        for v in part { let s0 = Double(v) + k * s1 - s2; s2 = s1; s1 = s0 }
        return (s1 * s1 + s2 * s2 - k * s1 * s2) / Double(part.count * part.count)
    }

    func testVirtualBassAddsHarmonics() {
        let tone: (Int) -> (Float, Float) = { t in let s = Float(sin(Double(t) * 2 * .pi * 60 / 48000)) * 0.4; return (s, s) }
        let dry = process(DSPParameters(), signal: tone)
        var p = DSPParameters()
        p.virtualBass = 1
        let wet = process(p, signal: tone)
        XCTAssertGreaterThan(energy(wet.l, 120), energy(dry.l, 120) * 100)
        // And the 60 Hz fundamental the speaker can't play is turned down.
        XCTAssertLessThan(energy(wet.l, 60), energy(dry.l, 60))
    }

    func testLoudnessLiftsBassAtLowVolume() {
        let tone: (Int) -> (Float, Float) = { t in let s = Float(sin(Double(t) * 2 * .pi * 60 / 48000)) * 0.1; return (s, s) }
        var p = DSPParameters()
        p.loudnessDB = 30
        let quiet = process(p, signal: tone)
        let flat = process(DSPParameters(), signal: tone)
        XCTAssertGreaterThan(energy(quiet.l, 60), energy(flat.l, 60) * 3)
        XCTAssertEqual(ReliefModel.attenuation(forVolume: 1), 0, accuracy: 0.01)
        XCTAssertEqual(ReliefModel.attenuation(forVolume: 0), 40, accuracy: 0.01)
    }

    /// The crosstalk canceller is a feedback loop: on loud noise, for a long time, it stays bounded and widens the image.
    func testCrosstalkCancellerIsStableAndWidens() {
        var seed: UInt32 = 99
        func noise() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 8) / Float(1 << 24) - 0.5 }
        var p = DSPParameters()
        p.surround = 1
        p.speakerAngle = 12
        let out = process(p, seconds: 10) { _ in let a = noise(), b = noise(); return (a * 0.9, b * 0.9) }
        XCTAssertLessThanOrEqual(out.l.map(abs).max() ?? 0, SoundProcessor.ceiling + 1e-4)
        // A sound on the left only: the right speaker now plays an inverted copy to cancel it at the right ear.
        let hard = process(p) { _ in (noise() * 0.5, 0) }
        let rightEnergy = hard.r.suffix(48000).reduce(0) { $0 + $1 * $1 }
        XCTAssertGreaterThan(rightEnergy, 1)
    }
}
