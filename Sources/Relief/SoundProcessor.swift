import Foundation

/// The processing chain applied to the whole system sound:
/// equalizer → bass → clarity → 3D surround → ambience → night mode → booster → limiter.
///
/// Created on the main thread for one sample rate, then used only by the audio thread.
/// `process` never allocates or locks.
final class SoundProcessor: @unchecked Sendable {
    let sampleRate: Double
    private var parameters = DSPParameters()
    private var configured = false

    // Equalizer
    private var eq = [Biquad](repeating: .identity, count: SoundSettings.bandCount)
    private var eqL = [BiquadState](repeating: BiquadState(), count: SoundSettings.bandCount)
    private var eqR = [BiquadState](repeating: BiquadState(), count: SoundSettings.bandCount)
    private var eqActive = false
    private var preamp = Smoothed(1)

    // Bass and clarity
    private var bassFilter = Biquad.identity
    private var bassL = BiquadState(), bassR = BiquadState()
    private var airFilter = Biquad.identity
    private var presenceFilter = Biquad.identity
    private var airL = BiquadState(), airR = BiquadState()
    private var presenceL = BiquadState(), presenceR = BiquadState()

    // 3D surround
    private var sideGain = Smoothed(1)
    private var crossfeed = Smoothed(0)
    private var crossDelayL: DelayLine
    private var crossDelayR: DelayLine
    private let shadow: Biquad
    private var shadowL = BiquadState(), shadowR = BiquadState()
    private let sideLowCut: Biquad
    private var sideLowCutState = BiquadState()

    // Ambience
    private var reverb: Reverb
    private var wet = Smoothed(0)
    private var reverbRunning = false

    // Night mode (compressor)
    private var nightMix = Smoothed(0)
    private var compressorEnvelope: Float = 0
    private let compAttack: Float
    private let compRelease: Float

    // Booster and limiter
    private var boost = Smoothed(1)
    private var limiterGain: Float = 1
    private let limiterRelease: Float
    static let ceiling: Float = 0.966 // −0.3 dBFS

    /// Per-block smoothing coefficient (about 30 ms whatever the block size).
    private var smoothing: Float = 0.8

    init(sampleRate: Double) {
        let sr = sampleRate > 1000 && sampleRate.isFinite ? sampleRate : 48000
        self.sampleRate = sr
        crossDelayL = DelayLine(size: max(Int(sr * 0.00028), 1))
        crossDelayR = DelayLine(size: max(Int(sr * 0.00028), 1))
        shadow = .lowPass(frequency: 750, q: 0.6, sampleRate: sr)
        sideLowCut = .highPass(frequency: 150, sampleRate: sr)
        reverb = Reverb(sampleRate: sr)
        compAttack = Float(exp(-1 / (0.005 * sr)))
        compRelease = Float(exp(-1 / (0.200 * sr)))
        limiterRelease = Float(exp(-1 / (0.120 * sr)))
    }

    deinit {
        crossDelayL.free()
        crossDelayR.free()
        reverb.free()
    }

    /// Applies new settings. Called by the audio thread, between two blocks.
    func apply(_ p: DSPParameters) {
        let first = !configured
        configured = true
        let old = parameters
        parameters = p
        let sr = sampleRate

        if first || p.equalizerGains != old.equalizerGains || p.equalizerEnabled != old.equalizerEnabled {
            var maxGain: Float = 0
            eqActive = false
            for i in 0..<SoundSettings.bandCount {
                let g = p.equalizerEnabled ? Double(p.equalizerGains[i]) : 0
                let f = SoundSettings.bandFrequencies[i]
                switch i {
                case 0: eq[i] = .lowShelf(frequency: f * 1.4, gainDB: g, sampleRate: sr, slope: 0.8)
                case SoundSettings.bandCount - 1: eq[i] = .highShelf(frequency: f * 0.7, gainDB: g, sampleRate: sr, slope: 0.8)
                default: eq[i] = .peaking(frequency: f, q: 1.25, gainDB: g, sampleRate: sr)
                }
                if g != 0 { eqActive = true }
                maxGain = max(maxGain, Float(g))
            }
            // Leave some room for the boosted bands, so the limiter works less.
            preamp.target = pow(10, -maxGain * 0.5 / 20)
        }
        if first || p.bassDB != old.bassDB {
            bassFilter = .lowShelf(frequency: 110, gainDB: Double(p.bassDB), sampleRate: sr, slope: 0.7)
        }
        if first || p.clarity != old.clarity {
            airFilter = .highShelf(frequency: 7000, gainDB: Double(p.clarity * 6), sampleRate: sr, slope: 0.8)
            presenceFilter = .peaking(frequency: 2800, q: 0.8, gainDB: Double(p.clarity * 2.5), sampleRate: sr)
        }
        if p.headphones {
            sideGain.target = 1 + p.surround * 0.45
            crossfeed.target = p.surround * 0.42
        } else {
            sideGain.target = 1 + p.surround * 1.1
            crossfeed.target = 0
        }
        wet.target = p.ambience * 0.9
        nightMix.target = p.nightMode ? 1 : 0
        boost.target = pow(10, max(0, p.boostDB) / 20)
        if first {
            preamp.value = preamp.target
            sideGain.value = sideGain.target
            crossfeed.value = crossfeed.target
            wet.value = wet.target
            nightMix.value = nightMix.target
            boost.value = boost.target
        }
    }

    /// Processes a stereo block in place.
    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        if !configured { apply(parameters) }
        // About 30 ms time constant, whatever the block size.
        smoothing = Float(exp(-Double(frames) / (0.03 * sampleRate)))
        let n = Float(frames)

        // 1. Equalizer
        let pre = preamp.step(smoothing)
        if eqActive || pre.start != 1 || pre.end != 1 {
            let dp = (pre.end - pre.start) / n
            var g = pre.start
            for i in 0..<frames {
                var l = left[i] * g
                var r = right[i] * g
                if eqActive {
                    for b in 0..<SoundSettings.bandCount {
                        l = eqL[b].process(l, eq[b])
                        r = eqR[b].process(r, eq[b])
                    }
                }
                left[i] = l
                right[i] = r
                g += dp
            }
        }

        // 2. Bass and clarity
        if bassFilter != .identity {
            for i in 0..<frames {
                left[i] = bassL.process(left[i], bassFilter)
                right[i] = bassR.process(right[i], bassFilter)
            }
        }
        if airFilter != .identity {
            for i in 0..<frames {
                left[i] = presenceL.process(airL.process(left[i], airFilter), presenceFilter)
                right[i] = presenceR.process(airR.process(right[i], airFilter), presenceFilter)
            }
        }

        // 3. 3D surround: widen the side signal (above 150 Hz, so the bass stays centred),
        //    and for headphones blend a delayed, head-shadowed copy of each side into the other.
        let side = sideGain.step(smoothing)
        let cross = crossfeed.step(smoothing)
        if side.start != 1 || side.end != 1 || cross.start > 0 || cross.end > 0 {
            let ds = (side.end - side.start) / n
            let dc = (cross.end - cross.start) / n
            var s = side.start, c = cross.start
            for i in 0..<frames {
                let l = left[i], r = right[i]
                let mid = (l + r) * 0.5
                let sideSignal = (l - r) * 0.5
                let extra = sideLowCutState.process(sideSignal, sideLowCut) * (s - 1)
                var nl = mid + sideSignal + extra
                var nr = mid - sideSignal - extra
                if c > 0 {
                    let fromR = shadowL.process(crossDelayL.push(nr), shadow)
                    let fromL = shadowR.process(crossDelayR.push(nl), shadow)
                    let norm = 1 / (1 + c * 0.5)
                    nl = (nl + c * fromR) * norm
                    nr = (nr + c * fromL) * norm
                }
                left[i] = nl
                right[i] = nr
                s += ds
                c += dc
            }
        }

        // 4. Ambience
        let w = wet.step(smoothing)
        if w.start > 0 || w.end > 0 {
            if !reverbRunning {
                reverb.clear()
                reverbRunning = true
            }
            let dw = (w.end - w.start) / n
            var g = w.start
            for i in 0..<frames {
                let (rl, rr) = reverb.process(left[i], right[i])
                let dry = 1 - g * 0.25
                left[i] = left[i] * dry + rl * g
                right[i] = right[i] * dry + rr * g
                g += dw
            }
        } else {
            reverbRunning = false
        }

        // 5. Night mode: a gentle compressor (−30 dB threshold, 3:1) with make-up gain.
        let nm = nightMix.step(smoothing)
        if nm.start > 0 || nm.end > 0 {
            let dm = (nm.end - nm.start) / n
            var m = nm.start
            let threshold: Float = 0.0316 // −30 dB
            let makeUp: Float = 2.5       // +8 dB
            for i in 0..<frames {
                let peak = max(abs(left[i]), abs(right[i]))
                let coeff = peak > compressorEnvelope ? compAttack : compRelease
                compressorEnvelope = peak + (compressorEnvelope - peak) * coeff
                var gain: Float = 1
                if compressorEnvelope > threshold {
                    // Output level = threshold × (input / threshold)^(1/3)
                    gain = pow(compressorEnvelope / threshold, -2.0 / 3.0)
                }
                let g = 1 + m * (gain * makeUp - 1)
                left[i] *= g
                right[i] *= g
                m += dm
            }
        }

        // 6. Booster
        let b = boost.step(smoothing)
        if b.start != 1 || b.end != 1 {
            let db = (b.end - b.start) / n
            var g = b.start
            for i in 0..<frames {
                left[i] *= g
                right[i] *= g
                g += db
            }
        }

        // 7. Limiter: never above −0.3 dBFS, stereo-linked so the image doesn't shift.
        let ceiling = Self.ceiling
        var faulty = false
        for i in 0..<frames {
            var l = left[i], r = right[i]
            if !l.isFinite || !r.isFinite {
                faulty = true
                l = 0
                r = 0
            }
            let peak = max(abs(l), abs(r))
            let needed: Float = peak > ceiling ? ceiling / peak : 1
            if needed < limiterGain {
                limiterGain = needed
            } else {
                limiterGain = needed + (limiterGain - needed) * limiterRelease
            }
            left[i] = min(max(l * limiterGain, -ceiling), ceiling)
            right[i] = min(max(r * limiterGain, -ceiling), ceiling)
        }
        if faulty { resetState() }
    }

    /// Clears every filter memory (after a NaN, or when the audio restarts).
    func resetState() {
        for b in 0..<SoundSettings.bandCount {
            eqL[b].reset()
            eqR[b].reset()
        }
        bassL.reset(); bassR.reset()
        airL.reset(); airR.reset()
        presenceL.reset(); presenceR.reset()
        shadowL.reset(); shadowR.reset()
        sideLowCutState.reset()
        crossDelayL.clear()
        crossDelayR.clear()
        reverb.clear()
        compressorEnvelope = 0
        limiterGain = 1
    }
}
