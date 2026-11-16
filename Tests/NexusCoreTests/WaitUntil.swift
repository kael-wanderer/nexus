import Foundation

/// Polls until `condition` holds or `timeout` passes, for a state an event *will* produce — a
/// fixed sleep guesses how long that takes, and on a busy machine the guess is wrong. It does not
/// fail by itself: the caller's `#expect` says what was wanted. Never use it to show that
/// something does *not* happen; that still needs a sleep.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while await !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}
