import Foundation

public struct MetadataItem: Sendable, Hashable {
    public let url: URL
    public let displayName: String

    public init(url: URL, displayName: String) {
        self.url = url
        self.displayName = displayName
    }
}

/// Excludes implementation files while keeping cloud documents searchable.
public struct PathExclusion: Sendable {
    public let root: URL
    public let exceptions: [URL]

    public init(root: URL, exceptions: [URL]) {
        self.root = root
        self.exceptions = exceptions
    }

    public static func userLibrary(home: URL) -> PathExclusion {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        return PathExclusion(root: library, exceptions: [
            library.appendingPathComponent("Mobile Documents", isDirectory: true),
            library.appendingPathComponent("CloudStorage", isDirectory: true)
        ])
    }

    public func excludes(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        guard path.starts(with: rootComponents) else { return false }
        return !exceptions.contains { path.starts(with: $0.standardizedFileURL.pathComponents) }
    }
}

public enum MetadataScope: Sendable {
    case localComputer
    case userHome

    var rawScopes: [Any] {
        switch self {
        case .localComputer: [NSMetadataQueryLocalComputerScope]
        case .userHome: [NSMetadataQueryUserHomeScope]
        }
    }
}

/// Whether a file query wants files, folders, or both (M19).
public enum FileKind: String, Sendable, Hashable {
    case any
    case filesOnly
    case foldersOnly

    /// `kMDItemContentTypeTree` rather than `kMDItemContentType`: a folder's own content type is
    /// whatever kind of folder it is — a bundle, a package, a plain directory — and the tree is
    /// where `public.folder` is common to all of them.
    var predicate: NSPredicate? {
        switch self {
        case .any:
            nil
        case .foldersOnly:
            NSPredicate(format: "kMDItemContentTypeTree == %@", "public.folder")
        case .filesOnly:
            NSCompoundPredicate(
                notPredicateWithSubpredicate:
                    NSPredicate(format: "kMDItemContentTypeTree == %@", "public.folder")
            )
        }
    }
}

public enum MetadataSearch: Sendable {
    case applicationBundles
    /// Display-name prefix match. The text is bound as a predicate argument, never interpolated
    /// into the format string.
    case displayNamePrefix(String, kind: FileKind = .any)

    var predicate: NSPredicate {
        switch self {
        case .applicationBundles:
            return NSPredicate(format: "kMDItemContentType == %@", "com.apple.application-bundle")
        case .displayNamePrefix(let text, let kind):
            let name = NSPredicate(format: "kMDItemDisplayName LIKE[cd] %@", "\(text)*")
            guard let kindPredicate = kind.predicate else { return name }
            return NSCompoundPredicate(andPredicateWithSubpredicates: [name, kindPredicate])
        }
    }
}

/// One-shot Spotlight query. `NSMetadataQuery` needs a run loop, so it lives on the main actor;
/// callers get back `Sendable` value types. The query is stopped on the first gather — no live
/// monitoring, no background churn (design/mvp.md §4.2).
@MainActor
public final class MetadataQueryRunner {
    public static let shared = MetadataQueryRunner()

    public init() {}

    public func run(
        _ search: MetadataSearch,
        scope: MetadataScope,
        limit: Int,
        exclusion: PathExclusion? = nil,
        timeout: Duration = .seconds(3)
    ) async -> [MetadataItem] {
        let session = QuerySession(limit: limit, exclusion: exclusion)
        return await withCheckedContinuation { continuation in
            session.begin(
                predicate: search.predicate,
                scopes: scope.rawScopes,
                timeout: timeout,
                continuation: continuation
            )
        }
    }

    /// Filter before applying the limit so implementation files cannot crowd out documents. Takes
    /// any sequence so the query can hand over a lazy one: a two-letter prefix can match thousands
    /// of items, and reading each one's attributes on the main actor stops at the limit, as before.
    nonisolated static func collect(
        _ entries: some Sequence<(path: String, name: String?)>,
        limit: Int,
        exclusion: PathExclusion?
    ) -> [MetadataItem] {
        guard limit > 0 else { return [] }
        var results: [MetadataItem] = []
        results.reserveCapacity(Swift.min(limit, entries.underestimatedCount))
        for entry in entries {
            let url = URL(fileURLWithPath: entry.path)
            guard exclusion?.excludes(url) != true else { continue }
            let name = entry.name ?? (entry.path as NSString).lastPathComponent
            results.append(MetadataItem(url: url, displayName: name))
            if results.count >= limit { break }
        }
        return results
    }
}

/// Owns the `NSMetadataQuery` and its observer so the `@Sendable` notification block captures
/// nothing but this box. Created and used only on the main actor.
private final class QuerySession: @unchecked Sendable {
    private let query = NSMetadataQuery()
    private let limit: Int
    private let exclusion: PathExclusion?
    private var observer: (any NSObjectProtocol)?
    private var continuation: CheckedContinuation<[MetadataItem], Never>?
    private var timeoutTask: Task<Void, Never>?

    init(limit: Int, exclusion: PathExclusion?) {
        self.limit = limit
        self.exclusion = exclusion
    }

    @MainActor
    func begin(
        predicate: NSPredicate,
        scopes: [Any],
        timeout: Duration,
        continuation: CheckedContinuation<[MetadataItem], Never>
    ) {
        self.continuation = continuation
        query.predicate = predicate
        query.searchScopes = scopes
        query.valueListAttributes = [NSMetadataItemDisplayNameKey, NSMetadataItemPathKey]
        query.notificationBatchingInterval = 0.1

        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [self] _ in
            MainActor.assumeIsolated { self.finish(collectResults()) }
        }
        timeoutTask = Task { @MainActor [self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            Log.search.debug("Spotlight query timed out")
            finish([])
        }
        query.start()
    }

    @MainActor
    private func finish(_ items: [MetadataItem]) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        query.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        continuation.resume(returning: items)
    }

    @MainActor
    private func collectResults() -> [MetadataItem] {
        // Lazy, so attributes are read only until `collect` reaches the limit.
        let entries = (0..<query.resultCount).lazy.compactMap { index -> (path: String, name: String?)? in
            guard let item = self.query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { return nil }
            return (path: path, name: item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
        }
        return MetadataQueryRunner.collect(entries, limit: limit, exclusion: exclusion)
    }
}
