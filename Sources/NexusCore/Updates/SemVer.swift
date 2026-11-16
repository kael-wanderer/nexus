import Foundation

// Ported from Bugler (`Sources/Bugler/Core/SemVer.swift`), same author, unchanged logic.

/// A SemVer-2.0-style comparator, used by the update check.
///
/// A naive comparator splits on `-` and treats `0.3.1-beta.2` as a five-segment
/// numeric list, which fails on `beta`. This type orders numeric
/// prerelease identifiers numerically (`beta.10 > beta.2`) and ranks a final
/// release above any prerelease of the same core version.
public enum SemVer {
    private enum Identifier: Equatable {
        case numeric(Int)
        case alphanumeric(String)
    }

    private struct Parsed {
        let core: [Int]
        let prerelease: [Identifier]
    }

    /// True when `candidate` is a strictly newer version than `current`. Returns
    /// false for equal versions and for anything that does not parse, so garbage
    /// input can never trigger a spurious update notification.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parse(candidate), let b = parse(current) else { return false }
        return compare(a, b) == .orderedDescending
    }

    /// True when `raw` parses as a supported version, so a feed
    /// entry with a garbage version string can be rejected before it is offered.
    public static func isValid(_ raw: String) -> Bool {
        parse(raw) != nil
    }

    private static func parse(_ raw: String) -> Parsed? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("v"), value.dropFirst().first?.isNumber == true {
            value.removeFirst()
        }
        // Build metadata (+...) does not affect precedence.
        if let plus = value.firstIndex(of: "+") {
            value = String(value[..<plus])
        }
        // Split core from prerelease on the first hyphen.
        let coreString: Substring
        let preString: Substring
        if let hyphen = value.firstIndex(of: "-") {
            coreString = value[..<hyphen]
            preString = value[value.index(after: hyphen)...]
        } else {
            coreString = Substring(value)
            preString = ""
        }

        let coreParts = coreString.split(separator: ".", omittingEmptySubsequences: false)
        guard !coreParts.isEmpty, coreParts.count <= 3 else { return nil }
        var core: [Int] = []
        for part in coreParts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let number = Int(part) else {
                return nil
            }
            core.append(number)
        }
        while core.count < 3 { core.append(0) }  // missing minor/patch = 0

        var prerelease: [Identifier] = []
        if !preString.isEmpty {
            for part in preString.split(separator: ".", omittingEmptySubsequences: false) {
                guard !part.isEmpty else { return nil }
                if part.allSatisfy(\.isNumber), let number = Int(part) {
                    prerelease.append(.numeric(number))
                } else {
                    prerelease.append(.alphanumeric(String(part)))
                }
            }
        }
        return Parsed(core: core, prerelease: prerelease)
    }

    private static func compare(_ a: Parsed, _ b: Parsed) -> ComparisonResult {
        for index in 0..<3 where a.core[index] != b.core[index] {
            return a.core[index] < b.core[index] ? .orderedAscending : .orderedDescending
        }
        // Equal core: a version with no prerelease outranks one with a prerelease.
        switch (a.prerelease.isEmpty, b.prerelease.isEmpty) {
        case (true, true): return .orderedSame
        case (true, false): return .orderedDescending
        case (false, true): return .orderedAscending
        case (false, false): return comparePrerelease(a.prerelease, b.prerelease)
        }
    }

    private static func comparePrerelease(_ a: [Identifier], _ b: [Identifier]) -> ComparisonResult
    {
        for (lhs, rhs) in zip(a, b) {
            switch (lhs, rhs) {
            case let (.numeric(x), .numeric(y)):
                if x != y { return x < y ? .orderedAscending : .orderedDescending }
            case (.numeric, .alphanumeric):
                return .orderedAscending  // numeric identifiers rank lower
            case (.alphanumeric, .numeric):
                return .orderedDescending
            case let (.alphanumeric(x), .alphanumeric(y)):
                if x != y { return x < y ? .orderedAscending : .orderedDescending }
            }
        }
        // All shared identifiers equal: the longer list is greater.
        if a.count != b.count { return a.count < b.count ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }
}
