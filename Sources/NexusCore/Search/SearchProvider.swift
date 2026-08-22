import Foundation

public protocol SearchProvider: Sendable {
    var identifier: SearchProviderID { get }
    var category: SearchCategory { get }
    /// `nil` means the provider works with every permission denied.
    var requiredPermission: Permission? { get }
    /// Per-provider, not global (D7): a global debounce would spend the whole 50 ms budget
    /// waiting for data that is already in memory.
    var debounce: Duration { get }
    var minimumCharacters: Int { get }
    func results(for query: SearchQuery, context: SearchContext) async -> [SearchResult]
}

extension SearchProvider {
    public var requiredPermission: Permission? { nil }
    public var debounce: Duration { .zero }
    public var minimumCharacters: Int { 1 }
}

/// Everything a provider needs that is not the query itself, passed as a value so providers stay
/// `Sendable` and testable.
public struct SearchContext: Sendable {
    public let frecency: Frecency
    public let frontmostApplication: String?
    public let now: Date

    public init(frecency: Frecency = Frecency(), frontmostApplication: String? = nil, now: Date = Date()) {
        self.frecency = frecency
        self.frontmostApplication = frontmostApplication
        self.now = now
    }
}
