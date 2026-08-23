import AppKit
import NexusCore
import SwiftUI

/// The start menu answers "show me what I have"; the palette answers "I know what I want" (M11).
/// Same index, opposite affordance — so this model browses and filters, and does not rank across
/// providers the way `SearchViewModel` does.
@MainActor
@Observable
public final class StartMenuViewModel {
    public var query = "" {
        didSet {
            guard query != oldValue else { return }
            selectedIndex = 0
            rebuild()
        }
    }

    public private(set) var applications: [NexusApplication] = []
    public var selectedIndex = 0

    /// How many pinned applications lead the list. The view draws those as their own section;
    /// everything after them is the alphabetical remainder (M11).
    public private(set) var pinnedCount = 0

    /// While a query is on screen the list is one flat set of matches, so the pinned section — and
    /// its header — steps aside rather than splitting the results in two.
    public var isFiltering: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    @ObservationIgnored private let index: ApplicationIndexSnapshot
    @ObservationIgnored private let configuration: ConfigurationController
    @ObservationIgnored private let launcher: any ApplicationServing

    @ObservationIgnored public var onClose: (() -> Void)?
    @ObservationIgnored public var onContentChange: (() -> Void)?

    /// Pinning is the sidebar's job — it knows about groups, and unpinning has to reach into them.
    /// The start menu only says which way to flip it.
    @ObservationIgnored public var setPinned: ((String, Bool) -> Void)?

    public init(
        index: ApplicationIndexSnapshot,
        configuration: ConfigurationController,
        launcher: any ApplicationServing
    ) {
        self.index = index
        self.configuration = configuration
        self.launcher = launcher
    }

    public func prepareForDisplay() {
        isShowing = true
        query = ""
        selectedIndex = 0
        rebuild()
    }

    /// The index finished building while the menu was open — or before it opened for the first
    /// time, which is the common case.
    public func indexChanged() {
        guard isShowing else { return }
        rebuild()
    }

    public private(set) var isShowing = false

    public func reset() {
        isShowing = false
        query = ""
        applications = []
        pinnedCount = 0
        selectedIndex = 0
    }

    // MARK: - Contents

    private func rebuild() {
        let all = index.read()
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            let byIdentifier = Dictionary(
                all.map { ($0.identity.bundleIdentifier, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            // Dock order, not alphabetical: the pinned section is the bar, laid out flat, so the
            // two read the same way round. Group members are in `pinnedApplications` too.
            let pinned = configuration.configuration.pinnedApplications.compactMap { byIdentifier[$0] }
            let pinnedIdentifiers = Set(pinned.map(\.identity.bundleIdentifier))
            let rest = all
                .filter { !pinnedIdentifiers.contains($0.identity.bundleIdentifier) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            pinnedCount = pinned.count
            applications = pinned + rest
            onContentChange?()
            return
        }

        // Filtering, not ranking: best match first, then alphabetical, so the grid stays stable
        // enough to aim at while you are still typing.
        pinnedCount = 0
        var scored: [(application: NexusApplication, score: Double)] = []
        for application in all {
            guard let score = StringMatch.score(query: trimmed, candidate: application.name) else {
                continue
            }
            scored.append((application, score))
        }
        scored.sort { left, right in
            if left.score == right.score {
                return left.application.name.localizedStandardCompare(right.application.name) == .orderedAscending
            }
            return left.score > right.score
        }
        applications = scored.map(\.application)
        onContentChange?()
    }

    // MARK: - Pinning

    public func isPinned(_ application: NexusApplication) -> Bool {
        configuration.configuration.pinnedApplications.contains(application.identity.bundleIdentifier)
    }

    public func togglePin(_ application: NexusApplication) {
        let identifier = application.identity.bundleIdentifier
        setPinned?(identifier, !isPinned(application))
        rebuild()
        // The row that was under the pointer is now somewhere else in the list; keep the selection
        // inside it rather than pointing past the end.
        selectedIndex = min(selectedIndex, max(0, applications.count - 1))
    }

    // MARK: - Selection

    public var selectedApplication: NexusApplication? {
        applications.indices.contains(selectedIndex) ? applications[selectedIndex] : nil
    }

    /// `delta` is in rows; the view passes its column count so the arrow keys walk the grid
    /// rather than the flat array.
    public func moveSelection(by delta: Int, columns: Int) {
        guard !applications.isEmpty else { return }
        let step = abs(delta) == 1 ? delta : delta / abs(delta) * columns
        selectedIndex = min(max(selectedIndex + step, 0), applications.count - 1)
    }

    public func launchSelected() {
        guard let application = selectedApplication else { return }
        launch(application)
    }

    public func launch(_ application: NexusApplication) {
        let identity = application.identity
        configuration.update { $0.frecency["app:\(identity.bundleIdentifier)", default: FrecencyEntry()].bump() }
        Task { [launcher] in
            if application.isRunning {
                try? await launcher.activate(identity)
            } else {
                try? await launcher.launch(identity)
            }
        }
        close()
    }

    public func run(_ action: SystemAction) {
        close()
        SystemActions.run(action)
    }

    public func close() {
        onClose?()
    }
}
