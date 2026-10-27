import Foundation
import Testing

@testable import NexusCore

@Suite("Metadata query collection")
struct MetadataQueryRunnerTests {
    @Test("Excluded candidates do not consume the limit")
    func exclusionBeforeLimit() throws {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let exclusion = PathExclusion.userLibrary(home: home)
        let caches = (0..<100).map { index in
            (path: home.appendingPathComponent("Library/Caches/\(index)").path, name: Optional("cache"))
        }
        let document = home.appendingPathComponent("Documents/Report.txt")
        let entries = caches + [(path: document.path, name: Optional("Report.txt"))]
        let results = MetadataQueryRunner.collect(entries, limit: 48, exclusion: exclusion)
        try #require(results.count > 0)
        #expect(results.count == 1)
        #expect(results[0] == MetadataItem(url: document, displayName: "Report.txt"))
    }

    @Test("Library exceptions, boundaries, limit and missing names")
    func exceptionsAndLimit() throws {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let exclusion = PathExclusion.userLibrary(home: home)
        let paths = [
            "Library",
            "Library/Caches/x",
            "Library/Application Support/x",
            "Library/Mobile Documents/com~apple~CloudDocs/Documents/iCloud.txt",
            "Library/CloudStorage/Dropbox/Cloud.txt",
            "Library Notes/x"
        ].map { home.appendingPathComponent($0) }
        let entries = paths.map { (path: $0.path, name: Optional<String>.none) }
        let kept = MetadataQueryRunner.collect(entries, limit: 48, exclusion: exclusion)
        let expectedCloud = [
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Documents/iCloud.txt"),
            home.appendingPathComponent("Library/CloudStorage/Dropbox/Cloud.txt")
        ]
        #expect(kept.map(\.url) == expectedCloud + [home.appendingPathComponent("Library Notes/x")])
        #expect(kept.map(\.displayName) == ["iCloud.txt", "Cloud.txt", "x"])
        let all = MetadataQueryRunner.collect(entries, limit: 48, exclusion: nil)
        #expect(all.map(\.url) == paths)
        let capped = MetadataQueryRunner.collect(entries, limit: 2, exclusion: exclusion)
        #expect(capped.map(\.url) == expectedCloud)
        #expect(MetadataQueryRunner.collect(entries, limit: 0, exclusion: exclusion).isEmpty)
    }
}
