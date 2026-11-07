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
