import Foundation

/// The processing chain applied to the whole system sound:
/// headphone correction → equalizer → loudness → bass → clarity → virtual bass → 3D surround → ambience
/// → night mode → booster → limiter.
///
/// Created on the main thread for one sample rate, then used only by the audio thread.
/// `process` never allocates or locks.
final class SoundProcessor: @unchecked Sendable {
    let sampleRate: Double
    private var parameters = DSPParameters()
    private var configured = false

    // Headphone correction
    private var headphone = [Biquad](repeating: .identity, count: 16)
    private var headphoneL = [BiquadState](repeating: BiquadState(), count: 16)
    private var headphoneR = [BiquadState](repeating: BiquadState(), count: 16)
    private var headphoneCount = 0
    private var headphoneGain = Smoothed(1)

    // Equalizer: the gains glide to their target, and the filters follow, so moving a band never clicks.
    private var eqTarget = SIMD16<Float>(repeating: 0)
    private var eqCurrent = SIMD16<Float>(repeating: 0)
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

    // Loudness compensation: shelves that follow the volume, gliding.
    private var loudnessTarget: Float = 0
    private var loudnessCurrent: Float = 0
    private var loudnessLow = Biquad.identity, loudnessHigh = Biquad.identity
    private var loudnessLowL = BiquadState(), loudnessLowR = BiquadState()
    private var loudnessHighL = BiquadState(), loudnessHighR = BiquadState()

    // Virtual bass
    private var virtualBassTarget: Float = 0
    private var virtualBassCurrent: Float = 0
    private var subCut = Biquad.identity
    private var subCutL = BiquadState(), subCutR = BiquadState()
    private let bassSplit: Biquad
    private var bassSplit1 = BiquadState(), bassSplit2 = BiquadState()
    private let harmonicsLow: Biquad, harmonicsHigh: Biquad
    private var harmonicsLowState = BiquadState(), harmonicsHighState = BiquadState()
    private var bassEnvelope: Float = 0
    private let envelopeAttack: Float, envelopeRelease: Float

    // Speakers 3D: crosstalk cancellation.
    private var crosstalk = Smoothed(0)
    private var crosstalkDelay: Float = 8
    private var crosstalkLineL: TapLine, crosstalkLineR: TapLine
    private let crosstalkLow: Biquad, crosstalkHigh: Biquad
    private var crosstalkLowL = BiquadState(), crosstalkLowR = BiquadState()
    private var crosstalkHighL = BiquadState(), crosstalkHighR = BiquadState()

    // 3D surround
    private var sideGain = Smoothed(1)
    /// Headphones: how much of the binaural rendering is heard (0 = plain stereo).
    private var spatial = Smoothed(0)
    private var binaural: Binaural
    private var binauralRunning = false
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
    private var limiterTarget: Float = 1
    private var limiterHold = 0
    private let lookahead: Int
    private var lookaheadL: DelayLine
    private var lookaheadR: DelayLine
    private let limiterAttack: Float
    private let limiterRelease: Float
    static let ceiling: Float = 0.966 // −0.3 dBFS

    /// Per-block smoothing coefficient (about 30 ms whatever the block size).
    private var smoothing: Float = 0.8

    init(sampleRate: Double) {
        let sr = sampleRate > 1000 && sampleRate.isFinite ? sampleRate : 48000
        self.sampleRate = sr
        binaural = Binaural(sampleRate: sr)
        bassSplit = .lowPass(frequency: 120, sampleRate: sr)
        harmonicsLow = .highPass(frequency: 140, sampleRate: sr)
        harmonicsHigh = .lowPass(frequency: 700, sampleRate: sr)
        envelopeAttack = Float(exp(-1 / (0.010 * sr)))
        envelopeRelease = Float(exp(-1 / (0.080 * sr)))
        crosstalkLineL = TapLine(maxDelay: Int(sr * 0.001) + 2)
        crosstalkLineR = TapLine(maxDelay: Int(sr * 0.001) + 2)
        crosstalkLow = .highPass(frequency: 250, sampleRate: sr)
        crosstalkHigh = .lowPass(frequency: 5000, sampleRate: sr)
        sideLowCut = .highPass(frequency: 150, sampleRate: sr)
        reverb = Reverb(sampleRate: sr)
        compAttack = Float(exp(-1 / (0.005 * sr)))
        compRelease = Float(exp(-1 / (0.200 * sr)))
        limiterRelease = Float(exp(-1 / (0.120 * sr)))
        limiterAttack = Float(exp(-1 / (0.0004 * sr)))
        lookahead = max(Int(sr * 0.0015), 1)
        lookaheadL = DelayLine(size: lookahead)
        lookaheadR = DelayLine(size: lookahead)
    }

    deinit {
        binaural.free()
        crosstalkLineL.free()
        crosstalkLineR.free()
        lookaheadL.free()
        lookaheadR.free()
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
            var target = SIMD16<Float>(repeating: 0)
            var maxGain: Float = 0
            for i in 0..<SoundSettings.bandCount {
                let g = p.equalizerEnabled ? p.equalizerGains[i] : 0
                target[i] = g
                maxGain = max(maxGain, g)
            }
            eqTarget = target
            // Leave some room for the boosted bands, so the limiter works less.
            preamp.target = pow(10, -maxGain * 0.5 / 20)
            if first {
                eqCurrent = target
                updateEqualizerFilters()
            }
        }
        if first || p.headphoneCount != old.headphoneCount || p.headphoneFrequency != old.headphoneFrequency
            || p.headphoneGain != old.headphoneGain || p.headphoneQ != old.headphoneQ || p.headphoneType != old.headphoneType {
            headphoneCount = min(max(p.headphoneCount, 0), 16)
            for i in 0..<16 {
                guard i < headphoneCount else { headphone[i] = .identity; continue }
                let f = Double(p.headphoneFrequency[i]), g = Double(p.headphoneGain[i]), q = Double(p.headphoneQ[i])
                switch p.headphoneType[i] {
                case 1: headphone[i] = .lowShelf(frequency: f, gainDB: g, q: q, sampleRate: sr)
                case 2: headphone[i] = .highShelf(frequency: f, gainDB: g, q: q, sampleRate: sr)
                default: headphone[i] = .peaking(frequency: f, q: q, gainDB: g, sampleRate: sr)
                }
            }
        }
        headphoneGain.target = p.headphoneCount > 0 ? pow(10, p.headphonePreampDB / 20) : 1
        if first || p.bassDB != old.bassDB {
            bassFilter = .lowShelf(frequency: 110, gainDB: Double(p.bassDB), sampleRate: sr, slope: 0.7)
        }
        if first || p.clarity != old.clarity {
            airFilter = .highShelf(frequency: 7000, gainDB: Double(p.clarity * 6), sampleRate: sr, slope: 0.8)
            presenceFilter = .peaking(frequency: 2800, q: 0.8, gainDB: Double(p.clarity * 2.5), sampleRate: sr)
        }
        if p.headphones {
            sideGain.target = 1 + p.surround * 0.2
            spatial.target = p.surround
            crosstalk.target = 0
        } else {
            sideGain.target = 1 + p.surround * 0.5
            spatial.target = 0
            crosstalk.target = p.surround * 0.65
        }
        // Path difference between the two ears for speakers this far apart, minus the sample the loop adds.
        let angle = Double(min(max(p.speakerAngle.isFinite ? p.speakerAngle : 25, 5), 45))
        crosstalkDelay = Float(max(0, 0.18 * sin(angle * .pi / 180) / 343 * sr - 1))
        loudnessTarget = min(max(p.loudnessDB.isFinite ? p.loudnessDB : 0, 0), 40)
        virtualBassTarget = min(max(p.virtualBass.isFinite ? p.virtualBass : 0, 0), 1)
        wet.target = p.ambience * 0.9
        nightMix.target = p.nightMode ? 1 : 0
        boost.target = pow(10, max(0, p.boostDB) / 20)
        if first {
            preamp.value = preamp.target
            sideGain.value = sideGain.target
            spatial.value = spatial.target
            crosstalk.value = crosstalk.target
            loudnessCurrent = loudnessTarget
            virtualBassCurrent = virtualBassTarget
            updateLoudnessFilters()
            updateVirtualBassFilter()
            headphoneGain.value = headphoneGain.target
            wet.value = wet.target
            nightMix.value = nightMix.target
            boost.value = boost.target
        }
    }

    /// Low volume: up to +10 dB of bass and +4 dB of treble, following the equal-loudness contours.
    private func updateLoudnessFilters() {
        let a = Double(loudnessCurrent)
        loudnessLow = .lowShelf(frequency: 120, gainDB: min(10, a * 0.3), sampleRate: sampleRate, slope: 0.7)
        loudnessHigh = .highShelf(frequency: 9000, gainDB: min(4, a * 0.12), sampleRate: sampleRate, slope: 0.7)
    }

    /// With virtual bass on, the deepest bass the speakers can't play is turned down: it only distorts.
    private func updateVirtualBassFilter() {
        subCut = .lowShelf(frequency: 70, gainDB: Double(-9 * virtualBassCurrent), sampleRate: sampleRate, slope: 0.8)
    }

    /// Glides a value toward its target; true when it moved.
    @inline(__always)
    private func glide(_ current: inout Float, to target: Float, _ coefficient: Float, step: Float) -> Bool {
        guard current != target else { return false }
        current = target + (current - target) * coefficient
        if abs(current - target) < step { current = target }
        return true
    }

    /// Filters for the equalizer's current (gliding) gains.
    private func updateEqualizerFilters() {
        let sr = sampleRate
        eqActive = false
        for i in 0..<SoundSettings.bandCount {
            let g = Double(eqCurrent[i])
            let f = SoundSettings.bandFrequencies[i]
            switch i {
            case 0: eq[i] = .lowShelf(frequency: f * 1.4, gainDB: g, sampleRate: sr, slope: 0.8)
            case SoundSettings.bandCount - 1: eq[i] = .highShelf(frequency: f * 0.7, gainDB: g, sampleRate: sr, slope: 0.8)
            default: eq[i] = .peaking(frequency: f, q: 1.25, gainDB: g, sampleRate: sr)
            }
            if g != 0 { eqActive = true }
        }
    }

    /// Processes a stereo block in place.
    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        if !configured { apply(parameters) }
        // About 30 ms time constant, whatever the block size.
        smoothing = Float(exp(-Double(frames) / (0.03 * sampleRate)))
        let n = Float(frames)

        // 0. Headphone correction (its preamp keeps the boosted bands from clipping).
        let hg = headphoneGain.step(smoothing)
        if headphoneCount > 0 || hg.start != 1 || hg.end != 1 {
            let dh = (hg.end - hg.start) / n
            var g = hg.start
            let count = headphoneCount
            for i in 0..<frames {
                var l = left[i] * g
                var r = right[i] * g
                for b in 0..<count {
                    l = headphoneL[b].process(l, headphone[b])
                    r = headphoneR[b].process(r, headphone[b])
                }
                left[i] = l
                right[i] = r
                g += dh
            }
        }

        // 1. Equalizer: gains glide about 30 ms toward their target, block by block.
        if eqCurrent != eqTarget {
            let next = eqTarget + (eqCurrent - eqTarget) * smoothing
            let diff = next - eqTarget
            let close = (diff .< 0.01) .& (diff .> -0.01)
            eqCurrent = next.replacing(with: eqTarget, where: close)
            updateEqualizerFilters()
        }
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

        // 1b. Loudness compensation
        if glide(&loudnessCurrent, to: loudnessTarget, smoothing, step: 0.05) { updateLoudnessFilters() }
        if loudnessLow != .identity || loudnessHigh != .identity {
            for i in 0..<frames {
                left[i] = loudnessHighL.process(loudnessLowL.process(left[i], loudnessLow), loudnessHigh)
                right[i] = loudnessHighR.process(loudnessLowR.process(right[i], loudnessLow), loudnessHigh)
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

        // 2b. Virtual bass: the bass below 120 Hz, made into its harmonics (which small speakers can play),
        //     follows its own level so quiet and loud passages get the same amount.
        if glide(&virtualBassCurrent, to: virtualBassTarget, smoothing, step: 0.002) { updateVirtualBassFilter() }
        if virtualBassCurrent > 0 {
            let amount = virtualBassCurrent * 1.8
            for i in 0..<frames {
                let l = subCutL.process(left[i], subCut)
                let r = subCutR.process(right[i], subCut)
                let low = bassSplit2.process(bassSplit1.process((left[i] + right[i]) * 0.5, bassSplit), bassSplit)
                let level = abs(low)
                bassEnvelope = level + (bassEnvelope - level) * (level > bassEnvelope ? envelopeAttack : envelopeRelease)
                // Full-wave rectifying a sine doubles its frequency; removing its mean (2/π) leaves the harmonics.
                let unit = min(max(low / (bassEnvelope + 1e-5), -4), 4)
                let harmonics = (abs(unit) - 0.637) * bassEnvelope
                let h = harmonicsHighState.process(harmonicsLowState.process(harmonics, harmonicsLow), harmonicsHigh) * amount
                left[i] = l + h
                right[i] = r + h
            }
        }

        // 3. 3D surround. Speakers: widen the side signal (above 150 Hz, so the bass stays centred).
        //    Headphones: binaural rendering of virtual speakers in a room, blended in.
        let side = sideGain.step(smoothing)
        if side.start != 1 || side.end != 1 {
            let ds = (side.end - side.start) / n
            var s = side.start
            for i in 0..<frames {
                let l = left[i], r = right[i]
                let mid = (l + r) * 0.5
                let sideSignal = (l - r) * 0.5
                let extra = sideLowCutState.process(sideSignal, sideLowCut) * (s - 1)
                left[i] = mid + sideSignal + extra
                right[i] = mid - sideSignal - extra
                s += ds
            }
        }
        // Speakers: cancel the sound of each speaker that reaches the opposite ear (recursive canceller,
        // 250 Hz – 5 kHz, where it works and stays stable), so the image spreads beyond the speakers.
        let xt = crosstalk.step(smoothing)
        if xt.start > 0 || xt.end > 0 {
            let dx = (xt.end - xt.start) / n
            var g = xt.start
            let d = crosstalkDelay
            for i in 0..<frames {
                let fromR = crosstalkHighR.process(crosstalkLowR.process(crosstalkLineR.read(d), crosstalkLow), crosstalkHigh)
                let fromL = crosstalkHighL.process(crosstalkLowL.process(crosstalkLineL.read(d), crosstalkLow), crosstalkHigh)
                let l = left[i] - g * fromR
                let r = right[i] - g * fromL
                crosstalkLineL.write(l)
                crosstalkLineR.write(r)
                left[i] = l
                right[i] = r
                g += dx
            }
        } else if crosstalk.value == 0 {
            crosstalkLineL.clear(); crosstalkLineR.clear()
        }

        let sp = spatial.step(smoothing)
        if sp.start > 0 || sp.end > 0 {
            if !binauralRunning {
                binaural.clear()
                binauralRunning = true
            }
            let dsp = (sp.end - sp.start) / n
            var m = sp.start
            for i in 0..<frames {
                let (bl, br) = binaural.process(left[i], right[i], rear: m)
                left[i] = left[i] * (1 - m) + bl * m
                right[i] = right[i] * (1 - m) + br * m
                m += dsp
            }
        } else {
            binauralRunning = false
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
        //    The gain is computed on the incoming signal and applied 1.5 ms later, so it is
        //    already down when a peak arrives (no hard clipping on transients).
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
            if needed <= limiterTarget {
                limiterTarget = needed
                limiterHold = lookahead
            } else if limiterHold > 0 {
                limiterHold -= 1
            } else {
                limiterTarget = needed
            }
            let coefficient = limiterTarget < limiterGain ? limiterAttack : limiterRelease
            limiterGain = limiterTarget + (limiterGain - limiterTarget) * coefficient
            let dl = lookaheadL.push(l)
            let dr = lookaheadR.push(r)
            // The clamp only catches what the attack could not reach in time.
            left[i] = min(max(dl * limiterGain, -ceiling), ceiling)
            right[i] = min(max(dr * limiterGain, -ceiling), ceiling)
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
        for i in 0..<16 { headphoneL[i].reset(); headphoneR[i].reset() }
        sideLowCutState.reset()
        binaural.clear()
        loudnessLowL.reset(); loudnessLowR.reset(); loudnessHighL.reset(); loudnessHighR.reset()
        subCutL.reset(); subCutR.reset(); bassSplit1.reset(); bassSplit2.reset()
        harmonicsLowState.reset(); harmonicsHighState.reset(); bassEnvelope = 0
        crosstalkLineL.clear(); crosstalkLineR.clear()
        crosstalkLowL.reset(); crosstalkLowR.reset(); crosstalkHighL.reset(); crosstalkHighR.reset()
        reverb.clear()
        compressorEnvelope = 0
        lookaheadL.clear()
        lookaheadR.clear()
        limiterGain = 1
        limiterTarget = 1
        limiterHold = 0
    }
}
