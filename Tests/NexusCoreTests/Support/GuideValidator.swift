import Foundation

/// One way the guide under `docs/guide/` can be wrong.
enum GuideProblem: Equatable {
    case badSlug(String)
    case duplicateSlug(String)
    case missingFile(String)
    case orphan(String)
    case frontmatterMismatch(String)
    case brokenLink(page: String, target: String)
    case missingImage(page: String, path: String)
    case forbiddenHTML(page: String, snippet: String)
    case deadAppLink(String)
    case deadPublishedSlug(String)
    case unsupportedVersion(Int)
}

/// Checks a guide folder: `guide.json`, its pages, their links and images, and
/// every slug that a shipped build or the app itself depends on.
struct GuideValidator {
    private struct Manifest: Decodable {
        struct Page: Decodable {
            let slug: String
            let title: String
            let summary: String
        }
        struct Group: Decodable {
            let title: String
            let pages: [Page]
        }
        let version: Int
        let groups: [Group]
        let redirects: [String: String]?
    }

    static func validate(root: URL, appSlugs: [String]) throws -> [GuideProblem] {
        let data = try Data(contentsOf: root.appending(path: "guide.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.version == 1 else { return [.unsupportedVersion(manifest.version)] }

        var problems: [GuideProblem] = []
        let pages = manifest.groups.flatMap(\.pages)
        let slugPattern = try NSRegularExpression(pattern: #"^[a-z0-9-]+/[a-z0-9-]+$"#)
        var seen = Set<String>()
        var listed = Set<String>()
        var reportedDuplicates = Set<String>()

        for page in pages {
            let range = NSRange(page.slug.startIndex..., in: page.slug)
            guard slugPattern.firstMatch(in: page.slug, range: range) != nil else {
                problems.append(.badSlug(page.slug))
                continue
            }
            if !seen.insert(page.slug).inserted {
                if reportedDuplicates.insert(page.slug).inserted {
                    problems.append(.duplicateSlug(page.slug))
                }
                continue
            }
            listed.insert(page.slug)
            let file = root.appending(path: page.slug + ".md")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                problems.append(.missingFile(page.slug))
                continue
            }
            problems += check(page: page, text: text, root: root, listed: Set(pages.map(\.slug)))
        }

        problems += orphans(root: root, listed: listed)

        let alive = listed.union(manifest.redirects?.keys.map { $0 } ?? [])
        for slug in appSlugs where !alive.contains(slug) {
            problems.append(.deadAppLink(slug))
        }
        let published = root.appending(path: "published-slugs.txt")
        if let text = try? String(contentsOf: published, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let slug = line.trimmingCharacters(in: .whitespaces)
                if !slug.isEmpty, !alive.contains(slug) {
                    problems.append(.deadPublishedSlug(slug))
                }
            }
        }
        return problems
    }

    // MARK: - Pages

    private static func check(
        page: Manifest.Page, text: String, root: URL, listed: Set<String>
    ) -> [GuideProblem] {
        var problems: [GuideProblem] = []
        let (front, body) = split(text)
        if front["title"] != page.title || front["summary"] != page.summary {
            problems.append(.frontmatterMismatch(page.slug))
        }

        let folder = page.slug.split(separator: "/").dropLast().map(String.init)
        for target in matches(#"(?<!!)\[[^\]]*\]\(([^)\s]+)\)"#, in: body) {
            guard isRelative(target) else { continue }
            let path =
                target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? target
            guard path.hasSuffix(".md") else { continue }
            guard let resolved = resolve(path, from: folder),
                listed.contains(String(resolved.dropLast(3)))
            else {
                problems.append(.brokenLink(page: page.slug, target: target))
                continue
            }
        }
        for path in matches(#"!\[[^\]]*\]\(([^)\s]+)\)"#, in: body) {
            guard isRelative(path) else { continue }
            let clean = path.split(separator: "#", maxSplits: 1).first.map(String.init) ?? path
            guard let resolved = resolve(clean, from: folder),
                FileManager.default.fileExists(
                    atPath: root.appending(path: resolved).path)
            else {
                problems.append(.missingImage(page: page.slug, path: path))
                continue
            }
        }
        var tags: [String] = []
        let tagNames = matches(#"<(?:/)?([A-Za-z][A-Za-z0-9]*)"#, in: text)
        for tag in tagNames.map({ $0.lowercased() })
        where tag != "kbd" && !tags.contains(tag) {
            tags.append(tag)
            problems.append(.forbiddenHTML(page: page.slug, snippet: "<" + tag))
        }
        if text.range(of: "javascript:", options: .caseInsensitive) != nil {
            problems.append(.forbiddenHTML(page: page.slug, snippet: "javascript:"))
        }
        return problems
    }

    /// Frontmatter is the lines between the first two `---` lines, each
    /// `key: value`.
    private static func split(_ text: String) -> ([String: String], String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else {
            return ([:], text)
        }
        var front: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.range(of: ": ") else { continue }
            front[String(line[..<colon.lowerBound])] = String(line[colon.upperBound...])
        }
        return (front, lines[(end + 1)...].joined(separator: "\n"))
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static func isRelative(_ target: String) -> Bool {
        !target.hasPrefix("/") && !target.hasPrefix("#") && !target.contains(":")
    }

    /// Resolves `path` against a page's folder; `nil` when it climbs out of the
    /// guide root.
    private static func resolve(_ path: String, from folder: [String]) -> String? {
        var parts = folder
        for part in path.split(separator: "/") {
            switch part {
            case ".": continue
            case "..":
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            default: parts.append(String(part))
            }
        }
        return parts.joined(separator: "/")
    }

    private static func orphans(root: URL, listed: Set<String>) -> [GuideProblem] {
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)
        else { return [] }
        let prefix = root.standardizedFileURL.path + "/"
        var found: [String] = []
        for case let url as URL in walker where url.pathExtension == "md" {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            let slug = String(path.dropFirst(prefix.count).dropLast(3))
            if !listed.contains(slug) { found.append(slug) }
        }
        return found.sorted().map(GuideProblem.orphan)
    }
}
