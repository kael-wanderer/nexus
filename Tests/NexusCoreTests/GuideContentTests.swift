import Foundation
import Testing

@testable import NexusCore

/// The user guide published at kael.io.vn/projects/nexus/docs is content in this
/// repository, so a broken guide fails the test run like any other defect.
@Suite struct GuideContentTests {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NexusCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root

    private static func fixture(_ name: String) -> URL {
        repositoryRoot.appending(path: "Tests/NexusCoreTests/Fixtures/guide-bad/\(name)")
    }

    private static func problems(_ name: String, appSlugs: [String] = []) throws
        -> [GuideProblem]
    {
        try GuideValidator.validate(root: fixture(name), appSlugs: appSlugs)
    }

    @Test func realGuideHasNoProblems() throws {
        let problems = try GuideValidator.validate(
            root: Self.repositoryRoot.appending(path: "docs/guide"), appSlugs: Self.appSlugs)
        #expect(problems == [])
    }

    /// Every page the app links to, so a removed or renamed page fails here before a shipped
    /// build's link 404s.
    private static var appSlugs: [String] {
        GuideLink.Page.allCases.map(\.rawValue).filter { !$0.isEmpty }
    }

    @Test func guideLinkURLs() {
        #expect(
            GuideLink.url(.replaceTheDock).absoluteString
                == "https://kael.io.vn/projects/nexus/docs/recipes/replace-the-dock")
        #expect(GuideLink.url(.home).absoluteString == "https://kael.io.vn/projects/nexus/docs")
        for page in GuideLink.Page.allCases {
            #expect(GuideLink.url(page).scheme == "https")
            #expect(GuideLink.url(page).host == "kael.io.vn")
        }
    }

    @Test func missingFileFails() throws {
        #expect(try Self.problems("missing-file") == [.missingFile("a/one")])
    }

    @Test func orphanFails() throws {
        #expect(try Self.problems("orphan") == [.orphan("a/stray")])
    }

    @Test func brokenLinkFails() throws {
        #expect(
            try Self.problems("broken-link")
                == [.brokenLink(page: "a/one", target: "missing.md")])
    }

    @Test func missingImageFails() throws {
        #expect(
            try Self.problems("missing-image")
                == [.missingImage(page: "a/one", path: "../images/a/one/shot.png")])
    }

    @Test func scriptTagFails() throws {
        #expect(
            try Self.problems("script-tag")
                == [.forbiddenHTML(page: "a/one", snippet: "<script")])
    }

    @Test func javascriptLinkFails() throws {
        #expect(
            try Self.problems("javascript-link")
                == [.forbiddenHTML(page: "a/one", snippet: "javascript:")])
    }

    @Test func frontmatterMismatchFails() throws {
        #expect(try Self.problems("frontmatter-mismatch") == [.frontmatterMismatch("a/one")])
    }

    @Test func badSlugFails() throws {
        #expect(try Self.problems("bad-slug") == [.badSlug("Cleanup/Page")])
    }

    @Test func deadAppLinkFails() throws {
        #expect(
            try Self.problems("dead-app-link", appSlugs: ["a/one", "a/removed"])
                == [.deadAppLink("a/removed")])
    }

    @Test func deadPublishedSlugFails() throws {
        #expect(try Self.problems("dead-published-slug") == [.deadPublishedSlug("a/gone")])
    }

    @Test func redirectKeepsPublishedSlugAlive() throws {
        #expect(try Self.problems("redirect-keeps-slug") == [])
    }

    @Test func unknownVersionFails() throws {
        #expect(try Self.problems("unknown-version") == [.unsupportedVersion(2)])
    }

    @Test func duplicateSlugFails() throws {
        #expect(try Self.problems("duplicate-slug") == [.duplicateSlug("a/one")])
    }

    @Test func kbdIsAllowed() throws {
        #expect(try Self.problems("kbd-allowed") == [])
    }

    @Test func lessThanInProseIsNotATag() throws {
        #expect(try Self.problems("prose-less-than") == [])
    }
}
