import Foundation

/// How the 3D effect is rendered.
enum OutputMode: String, Codable, CaseIterable, Sendable {
    /// Wider stereo image for built-in or external speakers.
    case speakers
    /// Crossfeed and a sense of space for headphones and earbuds.
    case headphones
}

/// Everything the user can set about the sound. Stored as JSON in the preferences.
struct SoundSettings: Codable, Equatable, Sendable {
    static let bandCount = 10
    /// Centre frequencies of the equalizer bands, in hertz.
    static let bandFrequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    /// Range of each equalizer band, in decibels.
    static let bandRange: ClosedRange<Float> = -12...12

    var equalizerEnabled = true
    var equalizerGains: [Float] = Array(repeating: 0, count: bandCount)
    /// Identifier of the selected preset, or nil when the gains were edited by hand.
    var presetID: String? = EQPreset.flat.id

    /// Volume booster, 0…1 (0 to +12 dB).
    var boost: Float = 0
    /// 3D surround intensity, 0…1.
    var surround: Float = 0.5
    var outputMode: OutputMode = .speakers
    /// Room ambience (reverb), 0…1.
    var ambience: Float = 0
    /// Clarity (presence and air), 0…1.
    var clarity: Float = 0
    /// Bass boost, 0…1 (0 to +10 dB).
    var bass: Float = 0
    /// Night mode: evens out loud and quiet passages.
    var nightMode = false

    init() {}

    /// Values that are out of range (an edited or older preferences file) are clamped,
    /// so the audio thread never receives a dangerous value.
    func sanitized() -> SoundSettings {
        var s = self
        var gains = s.equalizerGains.prefix(Self.bandCount).map { g -> Float in
            g.isFinite ? min(max(g, Self.bandRange.lowerBound), Self.bandRange.upperBound) : 0
        }
        while gains.count < Self.bandCount { gains.append(0) }
        s.equalizerGains = gains
        func unit(_ v: Float) -> Float { v.isFinite ? min(max(v, 0), 1) : 0 }
        s.boost = unit(s.boost)
        s.surround = unit(s.surround)
        s.ambience = unit(s.ambience)
        s.clarity = unit(s.clarity)
        s.bass = unit(s.bass)
        return s
    }

    // Tolerant decoding: a missing key keeps its default value.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SoundSettings()
        equalizerEnabled = (try? c.decode(Bool.self, forKey: .equalizerEnabled)) ?? d.equalizerEnabled
        equalizerGains = (try? c.decode([Float].self, forKey: .equalizerGains)) ?? d.equalizerGains
        presetID = (try? c.decodeIfPresent(String.self, forKey: .presetID)) ?? nil
        boost = (try? c.decode(Float.self, forKey: .boost)) ?? d.boost
        surround = (try? c.decode(Float.self, forKey: .surround)) ?? d.surround
        outputMode = (try? c.decode(OutputMode.self, forKey: .outputMode)) ?? d.outputMode
        ambience = (try? c.decode(Float.self, forKey: .ambience)) ?? d.ambience
        clarity = (try? c.decode(Float.self, forKey: .clarity)) ?? d.clarity
        bass = (try? c.decode(Float.self, forKey: .bass)) ?? d.bass
        nightMode = (try? c.decode(Bool.self, forKey: .nightMode)) ?? d.nightMode
        self = sanitized()
    }

    /// The values handed to the audio thread (plain values only, no heap storage).
    var dspParameters: DSPParameters {
        let s = sanitized()
        var p = DSPParameters()
        p.equalizerEnabled = s.equalizerEnabled
        for i in 0..<Self.bandCount { p.equalizerGains[i] = s.equalizerGains[i] }
        p.boostDB = s.boost * 12
        p.surround = s.surround
        p.headphones = s.outputMode == .headphones
        p.ambience = s.ambience
        p.clarity = s.clarity
        p.bassDB = s.bass * 10
        p.nightMode = s.nightMode
        return p
    }
}

/// Parameters read by the audio thread. Only trivial values, so copying never allocates.
struct DSPParameters: Equatable, Sendable {
    var equalizerEnabled = false
    var equalizerGains = SIMD16<Float>(repeating: 0)
    var boostDB: Float = 0
    var surround: Float = 0
    var headphones = false
    var ambience: Float = 0
    var clarity: Float = 0
    var bassDB: Float = 0
    var nightMode = false
}

/// An equalizer preset.
struct EQPreset: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var gains: [Float]
    /// Presets created by the user can be renamed and deleted.
    var isCustom: Bool = false

    static let flat = EQPreset(id: "flat", name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

    static let builtIn: [EQPreset] = [
        flat,
        EQPreset(id: "bass", name: "Bass Booster", gains: [6, 5, 4, 2.5, 1, 0, 0, 0, 0, 0]),
        EQPreset(id: "treble", name: "Treble Booster", gains: [0, 0, 0, 0, 0, 1, 2.5, 4, 5, 6]),
        EQPreset(id: "vocal", name: "Vocal", gains: [-2, -2, -1, 1, 3, 4, 4, 3, 1, 0]),
        EQPreset(id: "rock", name: "Rock", gains: [5, 4, 3, 1, -1, -1, 1, 3, 4, 5]),
        EQPreset(id: "pop", name: "Pop", gains: [-1, 0, 2, 3, 4, 3, 1, 0, 0, -1]),
        EQPreset(id: "jazz", name: "Jazz", gains: [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]),
        EQPreset(id: "classical", name: "Classical", gains: [4, 3, 2, 1, 0, 0, 0, 1, 2, 3]),
        EQPreset(id: "electronic", name: "Electronic", gains: [5, 4, 1, 0, -2, 1, 0, 1, 4, 5]),
        EQPreset(id: "hiphop", name: "Hip-Hop", gains: [5, 4, 2, 3, -1, -1, 1, 0, 1, 2]),
        EQPreset(id: "acoustic", name: "Acoustic", gains: [3, 3, 2, 1, 1, 1, 2, 2, 2, 1]),
        EQPreset(id: "podcast", name: "Podcast", gains: [-4, -3, -1, 1, 2, 3, 3, 2, 0, -2]),
        EQPreset(id: "movie", name: "Movie", gains: [4, 3, 1, 0, 0, 1, 2, 2, 2, 1]),
        EQPreset(id: "gaming", name: "Gaming", gains: [3, 2, 0, -1, -1, 1, 3, 4, 3, 1]),
        EQPreset(id: "loudness", name: "Loudness", gains: [6, 4, 1, 0, -1, 0, 0, 1, 4, 6]),
        EQPreset(id: "laptop", name: "Small Speakers", gains: [0, 0, 4, 3, 1, 0, 0, 1, 2, 2]),
    ]

    var localizedName: String { isCustom ? name : S.presetName(id, fallback: name) }
}
