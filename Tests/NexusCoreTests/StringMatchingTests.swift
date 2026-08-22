import Foundation
import Testing

@testable import NexusCore

@Suite("StringMatch")
struct StringMatchTests {
    @Test("Exact matches score 1.0, case- and diacritic-insensitively")
    func exact() {
        #expect(StringMatch.match(query: "Safari", candidate: "Safari") == .exact)
        #expect(StringMatch.match(query: "safari", candidate: "Safari") == .exact)
        #expect(StringMatch.match(query: "SAFARI", candidate: "Safari") == .exact)
        #expect(StringMatch.match(query: "resume", candidate: "résumé") == .exact)
        #expect(StringMatch.score(query: "Safari", candidate: "Safari") == 1.0)
    }

    @Test("A whole-name prefix scores above a word prefix")
    func prefixes() {
        #expect(StringMatch.match(query: "vis", candidate: "Visual Studio Code") == .prefix)
        #expect(StringMatch.match(query: "code", candidate: "Visual Studio Code") == .wordPrefix)
        let prefixScore = StringMatch.score(query: "vis", candidate: "Visual Studio Code") ?? 0
        let wordScore = StringMatch.score(query: "code", candidate: "Visual Studio Code") ?? 0
        #expect(prefixScore == 0.90)
        #expect(wordScore == 0.80)
        #expect(prefixScore > wordScore)
    }

    @Test("Initials match as an acronym")
    func acronym() {
        #expect(StringMatch.match(query: "vsc", candidate: "Visual Studio Code") == .acronym)
        #expect(StringMatch.score(query: "vsc", candidate: "Visual Studio Code") == 0.70)
        #expect(StringMatch.match(query: "vs", candidate: "Visual Studio Code") == .acronym)
    }

    @Test("A scattered subsequence still matches, at a much lower score")
    func subsequence() {
        guard let kind = StringMatch.match(query: "vlc", candidate: "Visual Studio Code") else {
            Issue.record("expected a subsequence match")
            return
        }
        guard case .subsequence = kind else {
            Issue.record("expected .subsequence, got \(kind)")
            return
        }
        let score = kind.score
        #expect(score >= 0.20)
        #expect(score <= 0.55)
    }

    @Test("A denser subsequence scores higher than a sparser one")
    func subsequenceDensityOrdering() {
        let dense = StringMatch.score(query: "stud", candidate: "Visual Studio Code") ?? 0
        let sparse = StringMatch.score(query: "vsdc", candidate: "Visual Studio Code") ?? 0
        #expect(dense > sparse)
    }

    @Test("Characters that are not present at all do not match")
    func noMatch() {
        #expect(StringMatch.match(query: "zzz", candidate: "Visual Studio Code") == nil)
        #expect(StringMatch.match(query: "codez", candidate: "Visual Studio Code") == nil)
    }

    @Test("Empty inputs never match")
    func empty() {
        #expect(StringMatch.match(query: "", candidate: "Safari") == nil)
        #expect(StringMatch.match(query: "   ", candidate: "Safari") == nil)
        #expect(StringMatch.match(query: "Safari", candidate: "") == nil)
    }

    @Test("Unicode outside ASCII behaves")
    func unicode() {
        #expect(StringMatch.match(query: "日本", candidate: "日本語入力") == .prefix)
        #expect(StringMatch.match(query: "café", candidate: "Cafe Racer") == .prefix)
        #expect(StringMatch.match(query: "🎧", candidate: "🎧 Music") == .prefix)
    }

    @Test("Words split on separators and camelCase")
    func wordSplitting() {
        #expect(StringMatch.words(in: "Visual Studio Code") == ["visual", "studio", "code"])
        #expect(StringMatch.words(in: "my-file_name.txt") == ["my", "file", "name", "txt"])
        #expect(StringMatch.words(in: "VisualStudioCode") == ["visual", "studio", "code"])
        #expect(StringMatch.words(in: "") == [])
    }

    @Test("The ordering of match kinds is exactly the documented one")
    func ordering() {
        #expect(MatchKind.exact.score > MatchKind.prefix.score)
        #expect(MatchKind.prefix.score > MatchKind.wordPrefix.score)
        #expect(MatchKind.wordPrefix.score > MatchKind.acronym.score)
        #expect(MatchKind.acronym.score > MatchKind.subsequence(density: 1).score)
        #expect(MatchKind.subsequence(density: 1).score == 0.55)
        #expect(MatchKind.subsequence(density: 0).score == 0.20)
    }
}
