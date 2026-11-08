import Foundation

// Building blocks of the sound processing. Everything here runs on the audio thread:
// no allocation, no lock, no Objective-C, after initialization.

/// Biquad filter coefficients (RBJ "Audio EQ Cookbook"), normalized so a0 = 1.
struct Biquad: Equatable {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0

    static let identity = Biquad()

    private init(_ b0: Double, _ b1: Double, _ b2: Double, _ a0: Double, _ a1: Double, _ a2: Double) {
        self.b0 = Float(b0 / a0)
        self.b1 = Float(b1 / a0)
        self.b2 = Float(b2 / a0)
        self.a1 = Float(a1 / a0)
        self.a2 = Float(a2 / a0)
    }

    init() {}

    /// Keeps the frequency safely below Nyquist.
    private static func omega(_ frequency: Double, _ sampleRate: Double) -> Double {
        let f = min(max(frequency, 10), sampleRate * 0.45)
        return 2 * Double.pi * f / sampleRate
    }

    static func peaking(frequency: Double, q: Double, gainDB: Double, sampleRate: Double) -> Biquad {
        if abs(gainDB) < 0.001 { return .identity }
        let a = pow(10, gainDB / 40)
        let w = omega(frequency, sampleRate)
        let alpha = sin(w) / (2 * q)
        let c = cos(w)
        return Biquad(1 + alpha * a, -2 * c, 1 - alpha * a, 1 + alpha / a, -2 * c, 1 - alpha / a)
    }

    static func lowShelf(frequency: Double, gainDB: Double, sampleRate: Double, slope: Double = 1) -> Biquad {
        if abs(gainDB) < 0.001 { return .identity }
        let a = pow(10, gainDB / 40)
        let w = omega(frequency, sampleRate)
        let c = cos(w)
        let alpha = sin(w) / 2 * sqrt((a + 1 / a) * (1 / slope - 1) + 2)
        let sq = 2 * sqrt(a) * alpha
        return Biquad(a * ((a + 1) - (a - 1) * c + sq),
                      2 * a * ((a - 1) - (a + 1) * c),
                      a * ((a + 1) - (a - 1) * c - sq),
                      (a + 1) + (a - 1) * c + sq,
                      -2 * ((a - 1) + (a + 1) * c),
                      (a + 1) + (a - 1) * c - sq)
    }

    static func highShelf(frequency: Double, gainDB: Double, sampleRate: Double, slope: Double = 1) -> Biquad {
        if abs(gainDB) < 0.001 { return .identity }
        let a = pow(10, gainDB / 40)
        let w = omega(frequency, sampleRate)
        let c = cos(w)
        let alpha = sin(w) / 2 * sqrt((a + 1 / a) * (1 / slope - 1) + 2)
        let sq = 2 * sqrt(a) * alpha
        return Biquad(a * ((a + 1) + (a - 1) * c + sq),
                      -2 * a * ((a - 1) + (a + 1) * c),
                      a * ((a + 1) + (a - 1) * c - sq),
                      (a + 1) - (a - 1) * c + sq,
                      2 * ((a - 1) - (a + 1) * c),
                      (a + 1) - (a - 1) * c - sq)
    }

    /// Shelves defined by Q, as headphone correction files give them.
    static func lowShelf(frequency: Double, gainDB: Double, q: Double, sampleRate: Double) -> Biquad {
        if abs(gainDB) < 0.001 { return .identity }
        let a = pow(10, gainDB / 40)
        let w = omega(frequency, sampleRate)
        let c = cos(w)
        let alpha = sin(w) / (2 * max(q, 0.05))
        let sq = 2 * sqrt(a) * alpha
        return Biquad(a * ((a + 1) - (a - 1) * c + sq), 2 * a * ((a - 1) - (a + 1) * c), a * ((a + 1) - (a - 1) * c - sq),
                      (a + 1) + (a - 1) * c + sq, -2 * ((a - 1) + (a + 1) * c), (a + 1) + (a - 1) * c - sq)
    }

    static func highShelf(frequency: Double, gainDB: Double, q: Double, sampleRate: Double) -> Biquad {
        if abs(gainDB) < 0.001 { return .identity }
        let a = pow(10, gainDB / 40)
        let w = omega(frequency, sampleRate)
        let c = cos(w)
        let alpha = sin(w) / (2 * max(q, 0.05))
        let sq = 2 * sqrt(a) * alpha
        return Biquad(a * ((a + 1) + (a - 1) * c + sq), -2 * a * ((a - 1) + (a + 1) * c), a * ((a + 1) + (a - 1) * c - sq),
                      (a + 1) - (a - 1) * c + sq, 2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - sq)
    }

    /// First-order filter from its coefficients (b2 = a2 = 0).
    static func firstOrder(b0: Double, b1: Double, a1: Double) -> Biquad {
        Biquad(b0, b1, 0, 1, a1, 0)
    }

    static func lowPass(frequency: Double, q: Double = 0.7071, sampleRate: Double) -> Biquad {
        let w = omega(frequency, sampleRate)
        let alpha = sin(w) / (2 * q)
        let c = cos(w)
        return Biquad((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha)
    }

    static func highPass(frequency: Double, q: Double = 0.7071, sampleRate: Double) -> Biquad {
        let w = omega(frequency, sampleRate)
        let alpha = sin(w) / (2 * q)
        let c = cos(w)
        return Biquad((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha)
    }

    /// Gain of the filter at a frequency, in decibels (for the equalizer curve and the tests).
    func responseDB(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let c1 = cos(w), s1 = sin(w), c2 = cos(2 * w), s2 = sin(2 * w)
        let nr = Double(b0) + Double(b1) * c1 + Double(b2) * c2
        let ni = -(Double(b1) * s1 + Double(b2) * s2)
        let dr = 1 + Double(a1) * c1 + Double(a2) * c2
        let di = -(Double(a1) * s1 + Double(a2) * s2)
        let mag = sqrt((nr * nr + ni * ni) / max(dr * dr + di * di, 1e-30))
        return 20 * log10(max(mag, 1e-12))
    }
}

/// State of one biquad on one channel (transposed direct form II).
struct BiquadState {
    var z1: Float = 0
    var z2: Float = 0

    @inline(__always)
    mutating func process(_ x: Float, _ c: Biquad) -> Float {
        let y = c.b0 * x + z1
        z1 = c.b1 * x - c.a1 * y + z2
        z2 = c.b2 * x - c.a2 * y
        return y
    }

    mutating func reset() { z1 = 0; z2 = 0 }
}

/// A value that glides to its target, to avoid clicks when a setting changes.
struct Smoothed {
    var value: Float
    var target: Float

    init(_ v: Float) { value = v; target = v }

    /// Advances one block; `coefficient` close to 1 is slow.
    @inline(__always)
    mutating func step(_ coefficient: Float) -> (start: Float, end: Float) {
        let start = value
        value = target + (value - target) * coefficient
        if abs(value - target) < 1e-5 { value = target }
        return (start, value)
    }
}

/// Fixed-size delay line.
struct DelayLine {
    private let buffer: UnsafeMutablePointer<Float>
    private let size: Int
    private var index = 0

    init(size: Int) {
        self.size = max(size, 1)
        buffer = .allocate(capacity: self.size)
        buffer.initialize(repeating: 0, count: self.size)
    }

    func free() { buffer.deallocate() }

    func clear() { buffer.update(repeating: 0, count: size) }

    /// The sample written `size` samples ago (the one the next `write` replaces).
    @inline(__always)
    func read() -> Float { buffer[index] }

    @inline(__always)
    mutating func write(_ x: Float) {
        buffer[index] = x
        index += 1
        if index == size { index = 0 }
    }

    /// Writes a sample and returns the one written `size` samples ago.
    @inline(__always)
    mutating func push(_ x: Float) -> Float {
        let out = buffer[index]
        write(x)
        return out
    }
}

/// Freeverb comb filter.
private struct Comb {
    var line: DelayLine
    var store: Float = 0

    @inline(__always)
    mutating func process(_ x: Float, feedback: Float, damp: Float) -> Float {
        let out = line.read()
        store = out * (1 - damp) + store * damp
        line.write(x + store * feedback)
        return out
    }
}

/// Freeverb all-pass filter.
private struct AllPass {
    var line: DelayLine

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        let buffered = line.read()
        line.write(x + buffered * 0.5)
        return buffered - x
    }
}

/// Stereo room reverb (Schroeder–Moorer "Freeverb" topology), used for the ambience effect.
struct Reverb {
    private var combsL: [Comb] = []
    private var combsR: [Comb] = []
    private var allPassL: [AllPass] = []
    private var allPassR: [AllPass] = []
    private var preDelayL: DelayLine
    private var preDelayR: DelayLine
    private var toneL = BiquadState()
    private var toneR = BiquadState()
    private let tone: Biquad
    var roomSize: Float = 0.78
    var damping: Float = 0.45

    init(sampleRate: Double) {
        let scale = sampleRate / 44100
        let combTunings = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
        let allPassTunings = [556, 441, 341, 225]
        let spread = 23
        func len(_ n: Int) -> Int { max(Int(Double(n) * scale), 1) }
        combsL = combTunings.map { Comb(line: DelayLine(size: len($0))) }
        combsR = combTunings.map { Comb(line: DelayLine(size: len($0 + spread))) }
        allPassL = allPassTunings.map { AllPass(line: DelayLine(size: len($0))) }
        allPassR = allPassTunings.map { AllPass(line: DelayLine(size: len($0 + spread))) }
        preDelayL = DelayLine(size: max(Int(sampleRate * 0.012), 1))
        preDelayR = DelayLine(size: max(Int(sampleRate * 0.017), 1))
        tone = .lowPass(frequency: 7000, sampleRate: sampleRate)
    }

    func free() {
        for c in combsL { c.line.free() }
        for c in combsR { c.line.free() }
        for a in allPassL { a.line.free() }
        for a in allPassR { a.line.free() }
        preDelayL.free()
        preDelayR.free()
    }

    mutating func clear() {
        for i in combsL.indices { combsL[i].line.clear(); combsL[i].store = 0 }
        for i in combsR.indices { combsR[i].line.clear(); combsR[i].store = 0 }
        for a in allPassL { a.line.clear() }
        for a in allPassR { a.line.clear() }
        preDelayL.clear()
        preDelayR.clear()
        toneL.reset()
        toneR.reset()
    }

    /// Returns the wet signal only.
    @inline(__always)
    mutating func process(_ l: Float, _ r: Float) -> (Float, Float) {
        let input = (l + r) * 0.015
        let inL = preDelayL.push(input)
        let inR = preDelayR.push(input)
        var outL: Float = 0, outR: Float = 0
        for i in combsL.indices { outL += combsL[i].process(inL, feedback: roomSize, damp: damping) }
        for i in combsR.indices { outR += combsR[i].process(inR, feedback: roomSize, damp: damping) }
        for i in allPassL.indices { outL = allPassL[i].process(outL) }
        for i in allPassR.indices { outR = allPassR[i].process(outR) }
        return (toneL.process(outL, tone), toneR.process(outR, tone))
    }
}

/// Delay line read at any fractional delay (linear interpolation). Power-of-two size.
struct TapLine {
    private let buffer: UnsafeMutablePointer<Float>
    private let mask: Int
    private var index = 0

    init(maxDelay: Int) {
        var size = 1
        while size < maxDelay + 2 { size <<= 1 }
        mask = size - 1
        buffer = .allocate(capacity: size)
        buffer.initialize(repeating: 0, count: size)
    }

    func free() { buffer.deallocate() }
    func clear() { buffer.update(repeating: 0, count: mask + 1) }

    @inline(__always)
    mutating func write(_ x: Float) {
        index = (index + 1) & mask
        buffer[index] = x
    }

    /// The sample written `delay` samples before the last one.
    @inline(__always)
    func read(_ delay: Float) -> Float {
        let d = Int(delay)
        let frac = delay - Float(d)
        let a = buffer[(index - d) & mask]
        let b = buffer[(index - d - 1) & mask]
        return a + (b - a) * frac
    }
}

/// Binaural rendering for headphones: the two channels are played by virtual speakers in front
/// of the listener (±30°), the difference signal by two virtual surrounds behind (±110°), and a
/// few early reflections place the whole scene in a room, outside the head.
///
/// Each speaker reaches each ear through a spherical-head model (Brown & Duda, 1998): an
/// interaural time difference (Woodworth) and a head-shadow filter that depends on the angle.
struct Binaural {
    private struct Path {
        var filter: Biquad
        var delay: Float
        var state = BiquadState()
    }

    /// paths[speaker * 2 + ear]: speakers front L, front R, rear L, rear R; ears left, right.
    private var paths: [Path] = []
    private var lines: [TapLine] = []
    private var reflections: TapLine
    private var reflectionTaps: [(delay: Float, gainL: Float, gainR: Float)] = []
    private var reflectionToneL = BiquadState(), reflectionToneR = BiquadState()
    private let reflectionTone: Biquad
    private var rearLowCut = BiquadState()
    private let rearLowCutFilter: Biquad
    private var decorrelateL: DelayLine, decorrelateR: DelayLine

    static let speakerAngles: [Double] = [-30, 30, -110, 110]

    init(sampleRate: Double) {
        let headRadius = 0.0875, speed = 343.0
        let k = 2 * sampleRate, beta = 2 * speed / headRadius
        let earAngles: [Double] = [-90, 90]
        var maxDelay: Float = 0
        for az in Self.speakerAngles {
            for ear in earAngles {
                // Angle between the source and the ear's axis, 0…π.
                let theta = acos(cos((az - ear) * .pi / 180))
                // Head shadow: bright on the near side, dull on the far side.
                let alpha = (1 + 0.1 / 2) + (1 - 0.1 / 2) * cos(theta / (150 * .pi / 180) * .pi)
                let filter = Biquad.firstOrder(b0: (alpha * k + beta) / (k + beta), b1: (beta - alpha * k) / (k + beta),
                                               a1: (beta - k) / (k + beta))
                let seconds = theta < .pi / 2 ? headRadius / speed * (1 - cos(theta))
                                               : headRadius / speed * (1 + theta - .pi / 2)
                paths.append(Path(filter: filter, delay: Float(seconds * sampleRate)))
            }
        }
        // Time relative to the near ear of the front speakers: blended with the dry signal,
        // that path must not be delayed, or the mix would comb.
        let reference = paths[0].delay
        for i in paths.indices {
            paths[i].delay = max(0, paths[i].delay - reference)
            maxDelay = max(maxDelay, paths[i].delay)
        }
        lines = (0..<4).map { _ in TapLine(maxDelay: Int(maxDelay) + 2) }
        // Early reflections: walls a few metres away, the left wall nearer the left ear.
        let ms: [(Double, Float, Float)] = [(7.3, 0.30, 0.12), (8.9, 0.11, 0.28), (13.1, 0.20, 0.10),
                                            (15.7, 0.09, 0.19), (21.4, 0.12, 0.09), (26.9, 0.07, 0.10)]
        reflectionTaps = ms.map { (Float($0.0 / 1000 * sampleRate), $0.1, $0.2) }
        reflections = TapLine(maxDelay: Int(0.03 * sampleRate))
        reflectionTone = .lowPass(frequency: 4500, sampleRate: sampleRate)
        rearLowCutFilter = .highPass(frequency: 180, sampleRate: sampleRate)
        decorrelateL = DelayLine(size: max(Int(sampleRate * 0.0071), 1))
        decorrelateR = DelayLine(size: max(Int(sampleRate * 0.0113), 1))
    }

    func free() {
        for l in lines { l.free() }
        reflections.free()
        decorrelateL.free()
        decorrelateR.free()
    }

    mutating func clear() {
        for l in lines { l.clear() }
        reflections.clear()
        for i in paths.indices { paths[i].state.reset() }
        reflectionToneL.reset(); reflectionToneR.reset(); rearLowCut.reset()
        decorrelateL.clear(); decorrelateR.clear()
    }

    /// One stereo sample in, the two ears out. `rear` sets the level of the surrounds (0…1).
    @inline(__always)
    mutating func process(_ l: Float, _ r: Float, rear: Float) -> (Float, Float) {
        // Surrounds: the difference signal without its bass, made different on each side.
        let side = rearLowCut.process((l - r) * 0.5, rearLowCutFilter) * rear
        let rl = decorrelateL.push(side)
        let rr = -decorrelateR.push(side)
        lines[0].write(l)
        lines[1].write(r)
        lines[2].write(rl)
        lines[3].write(rr)
        reflections.write((l + r) * 0.5)

        var left: Float = 0, right: Float = 0
        for s in 0..<4 {
            let a = s * 2, b = s * 2 + 1
            left += paths[a].state.process(lines[s].read(paths[a].delay), paths[a].filter)
            right += paths[b].state.process(lines[s].read(paths[b].delay), paths[b].filter)
        }
        var reflL: Float = 0, reflR: Float = 0
        for t in reflectionTaps {
            let x = reflections.read(t.delay)
            reflL += x * t.gainL
            reflR += x * t.gainR
        }
        left = left * 0.62 + reflectionToneL.process(reflL, reflectionTone)
        right = right * 0.62 + reflectionToneR.process(reflR, reflectionTone)
        return (left, right)
    }
}
