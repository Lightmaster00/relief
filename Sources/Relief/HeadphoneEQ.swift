import Foundation

/// A headphone correction: the filters that bring a model's frequency response to a neutral
/// target (Harman). From the AutoEq project (MIT licence), one profile per model.
struct HeadphoneProfile: Identifiable, Equatable, Sendable {
    enum Kind: Character, Sendable {
        case overEar = "o", inEar = "i", earbud = "e"
        var symbol: String {
            switch self {
            case .overEar: return "headphones"
            case .inEar, .earbud: return "earbuds"
            }
        }
    }

    enum FilterType: Float, Sendable { case peak = 0, lowShelf = 1, highShelf = 2 }

    struct Filter: Equatable, Sendable {
        var type: FilterType
        var frequency: Float
        var gainDB: Float
        var q: Float
    }

    var name: String
    var kind: Kind
    var preampDB: Float
    var filters: [Filter]
    var id: String { name }

    static let maxFilters = 10
}

/// All the headphone profiles shipped with the app, loaded on first use.
enum HeadphoneLibrary {
    /// Sorted by name.
    static let all: [HeadphoneProfile] = {
        guard let url = Bundle.main.url(forResource: "headphones", withExtension: "eq"),
              let data = try? Data(contentsOf: url) else { return [] }
        return parse(compressed: data)
    }()

    private static let byName: [String: HeadphoneProfile] = {
        var d: [String: HeadphoneProfile] = [:]
        for p in all { d[p.name] = p }
        return d
    }()

    static func profile(named name: String) -> HeadphoneProfile? { byName[name] }

    /// Models whose name contains every word of the query, best matches first.
    static func search(_ query: String, limit: Int = 200) -> [HeadphoneProfile] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return Array(all.prefix(limit)) }
        var hits: [HeadphoneProfile] = []
        for p in all {
            let name = p.name.lowercased()
            if words.allSatisfy({ name.contains($0) }) {
                hits.append(p)
                if hits.count >= limit * 3 { break }
            }
        }
        // Names that start with the query come first.
        let first = words[0]
        hits.sort { a, b in
            let pa = a.name.lowercased().hasPrefix(first), pb = b.name.lowercased().hasPrefix(first)
            return pa != pb ? pa : a.name.count < b.name.count
        }
        return Array(hits.prefix(limit))
    }

    /// The file is raw DEFLATE of lines: `name \t kind \t preamp \t T,fc,gain,q;…`.
    static func parse(compressed: Data) -> [HeadphoneProfile] {
        guard let raw = try? (compressed as NSData).decompressed(using: .zlib) as Data,
              let text = String(data: raw, encoding: .utf8) else { return [] }
        return parse(text: text)
    }

    static func parse(text: String) -> [HeadphoneProfile] {
        var out: [HeadphoneProfile] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 4, let preamp = Float(parts[2]), preamp.isFinite, abs(preamp) < 30 else { continue }
            let kind = parts[1].first.flatMap(HeadphoneProfile.Kind.init(rawValue:)) ?? .overEar
            var filters: [HeadphoneProfile.Filter] = []
            for f in parts[3].split(separator: ";") {
                let v = f.split(separator: ",")
                guard v.count == 4, let fc = Float(v[1]), let g = Float(v[2]), let q = Float(v[3]),
                      fc > 10, fc < 24000, abs(g) <= 24, q > 0.05, q < 30 else { continue }
                let type: HeadphoneProfile.FilterType = v[0] == "L" ? .lowShelf : (v[0] == "H" ? .highShelf : .peak)
                filters.append(.init(type: type, frequency: fc, gainDB: g, q: q))
            }
            guard !filters.isEmpty else { continue }
            out.append(HeadphoneProfile(name: String(parts[0]), kind: kind, preampDB: preamp,
                                        filters: Array(filters.prefix(HeadphoneProfile.maxFilters))))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
