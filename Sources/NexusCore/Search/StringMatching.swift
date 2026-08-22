import Foundation

public enum MatchKind: Sendable, Equatable {
    case exact
    case prefix
    case wordPrefix
    case acronym
    case subsequence(density: Double)

    public var score: Double {
        switch self {
        case .exact: 1.00
        case .prefix: 0.90
        case .wordPrefix: 0.80
        case .acronym: 0.70
        case .subsequence(let density):
            // 0.20 at a fully scattered match, 0.55 at a contiguous one.
            (0.20 + 0.35 * density).clamped(to: 0.20...0.55)
        }
    }
}

/// Pure string matching — no I/O, no state. The largest unit-test surface in the project
/// together with `Ranking`.
public enum StringMatch {
    /// Case- and diacritic-insensitive, locale-independent.
    public static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
    }

    /// Best match of `query` against `candidate`, or `nil` when there is none.
    public static func match(query: String, candidate: String) -> MatchKind? {
        let needle = normalize(query.trimmingCharacters(in: .whitespaces))
        let haystack = normalize(candidate)
        guard !needle.isEmpty, !haystack.isEmpty else { return nil }

        if needle == haystack { return .exact }
        if haystack.hasPrefix(needle) { return .prefix }

        let words = self.words(in: haystack)
        if words.dropFirst().contains(where: { $0.hasPrefix(needle) }) { return .wordPrefix }

        let initials = String(words.compactMap(\.first))
        if initials.count > 1, initials.hasPrefix(needle) { return .acronym }

        if let density = subsequenceDensity(needle: needle, haystack: haystack) {
            return .subsequence(density: density)
        }
        return nil
    }

    public static func score(query: String, candidate: String) -> Double? {
        match(query: query, candidate: candidate)?.score
    }

    /// Splits on separators and camelCase boundaries: "VisualStudio-Code_v2" →
    /// ["visual", "studio", "code", "v2"] (after normalisation).
    public static func words(in value: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousWasLower = false

        for character in value {
            if character.isWhitespace || Self.separators.contains(character) {
                if !current.isEmpty { words.append(current) }
                current = ""
                previousWasLower = false
                continue
            }
            if character.isUppercase, previousWasLower, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
            previousWasLower = character.isLowercase || character.isNumber
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.lowercased() }
    }

    private static let separators: Set<Character> = ["-", "_", ".", "/", "\\", ":", "(", ")", "[", "]", ","]

    /// `nil` when `needle` is not a subsequence of `haystack`. Otherwise the ratio of matched
    /// characters to the span they were found in: 1.0 for a contiguous run.
    private static func subsequenceDensity(needle: String, haystack: String) -> Double? {
        let target = Array(haystack)
        var first: Int?
        var last = 0
        var index = 0

        for character in needle {
            var found = false
            while index < target.count {
                if target[index] == character {
                    if first == nil { first = index }
                    last = index
                    index += 1
                    found = true
                    break
                }
                index += 1
            }
            guard found else { return nil }
        }
        guard let first else { return nil }
        let span = last - first + 1
        guard span > 0 else { return nil }
        return Double(needle.count) / Double(span)
    }
}

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
