import CoreAudio
import XCTest
@testable import Relief

/// Feeds fake Core Audio buffer lists to the render callback, the way the HAL does.
final class RenderTests: XCTestCase {
    /// A buffer list whose buffers hold `frames` frames of interleaved floats.
    private final class Buffers {
        let list: UnsafeMutableAudioBufferListPointer
        private var storage: [UnsafeMutablePointer<Float>] = []

        init(channels: [Int], frames: Int, fill: [(Int, Int) -> Float]? = nil) {
            list = AudioBufferList.allocate(maximumBuffers: max(channels.count, 1))
            list.count = channels.count
            for (b, ch) in channels.enumerated() {
                let data = UnsafeMutablePointer<Float>.allocate(capacity: ch * frames)
                for f in 0..<frames {
                    for c in 0..<ch { data[f * ch + c] = fill?[b](f, c) ?? 0 }
                }
                storage.append(data)
                list[b] = AudioBuffer(mNumberChannels: UInt32(ch), mDataByteSize: UInt32(4 * ch * frames), mData: data)
            }
        }

        func sample(buffer: Int, frame: Int, channel: Int) -> Float {
            let ch = Int(list[buffer].mNumberChannels)
            return storage[buffer][frame * ch + channel]
        }

        deinit {
            storage.forEach { $0.deallocate() }
            free(list.unsafeMutablePointer)
        }
    }

    private func context(tapCount: Int, appGains: [Float] = []) -> RenderContext {
        let mailbox = ParameterMailbox()
        var gains = SIMD32<Float>(repeating: 1)
        for (i, g) in appGains.enumerated() { gains[i] = g }
        mailbox.post(DSPParameters(), appGains: gains) // neutral sound
        return RenderContext(sampleRate: 48000, tapCount: tapCount, mailbox: mailbox)
    }

    func testMixesTapsSkipsMicrophoneAndHonoursAppVolume() {
        let frames = 512
        // A headset microphone stream first, then the global tap, then one app tap.
        let input = Buffers(channels: [1, 2, 2], frames: frames, fill: [
            { _, _ in 0.9 },                    // microphone: must be ignored
            { _, c in c == 0 ? 0.1 : 0.2 },     // global tap
            { _, c in c == 0 ? 0.3 : 0.4 },     // app at 50 %
        ])
        let output = Buffers(channels: [2], frames: frames)
        context(tapCount: 2, appGains: [0.5]).render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: frames - 1, channel: 0), 0.25, accuracy: 1e-4)
        XCTAssertEqual(output.sample(buffer: 0, frame: frames - 1, channel: 1), 0.4, accuracy: 1e-4)
    }

    func testSeparateChannelBuffersAndExtraChannels() {
        let frames = 256
        let input = Buffers(channels: [2], frames: frames, fill: [{ _, c in c == 0 ? 0.2 : -0.3 }])
        // Left and right in separate buffers, then a 2-channel buffer for channels 3–4.
        let output = Buffers(channels: [1, 1, 2], frames: frames, fill: [{ _, _ in 7 }, { _, _ in 7 }, { _, _ in 7 }])
        context(tapCount: 1).render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        let last = frames - 1
        XCTAssertEqual(output.sample(buffer: 0, frame: last, channel: 0), 0.2, accuracy: 1e-4)
        XCTAssertEqual(output.sample(buffer: 1, frame: last, channel: 0), -0.3, accuracy: 1e-4)
        XCTAssertEqual(output.sample(buffer: 2, frame: last, channel: 0), 0)
        XCTAssertEqual(output.sample(buffer: 2, frame: last, channel: 1), 0)
    }

    func testMonoOutputGetsBothSides() {
        let frames = 256
        let input = Buffers(channels: [2], frames: frames, fill: [{ _, c in c == 0 ? 0.4 : 0.2 }])
        let output = Buffers(channels: [1], frames: frames)
        context(tapCount: 1).render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: frames - 1, channel: 0), 0.3, accuracy: 1e-4)
    }

    func testBlocksLargerThanTheInternalBuffer() {
        let frames = 9000
        let input = Buffers(channels: [2], frames: frames, fill: [{ _, _ in 0.25 }])
        let output = Buffers(channels: [2], frames: frames)
        context(tapCount: 1).render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        for frame in stride(from: 200, to: frames, by: 97) {
            XCTAssertEqual(output.sample(buffer: 0, frame: frame, channel: 0), 0.25, accuracy: 1e-4)
        }
    }

    func testShortTapBufferDoesNotOverrun() {
        // A tap that delivers fewer frames than the output asks for.
        let input = Buffers(channels: [2], frames: 100, fill: [{ _, _ in 0.5 }])
        let output = Buffers(channels: [2], frames: 400, fill: [{ _, _ in 7 }])
        context(tapCount: 1).render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: 399, channel: 0), 0, accuracy: 1e-4)
    }

    func testNoInputGivesSilence() {
        let input = Buffers(channels: [], frames: 0)
        let output = Buffers(channels: [2], frames: 128, fill: [{ _, _ in 7 }])
        context(tapCount: 1).render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: 127, channel: 1), 0)
    }

    func testLimiterSmoothsAHardPeak() {
        // A sudden full-scale step boosted by 12 dB: the output stays under the ceiling.
        let processor = SoundProcessor(sampleRate: 44100)
        var p = DSPParameters()
        p.boostDB = 12
        processor.apply(p)
        let n = 4096
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        for i in 0..<n { l[i] = i < 2000 ? 0.01 : 1; r[i] = l[i] }
        processor.process(left: l, right: r, frames: n)
        for i in 0..<n { XCTAssertLessThanOrEqual(abs(l[i]), SoundProcessor.ceiling + 1e-6) }
    }
}
