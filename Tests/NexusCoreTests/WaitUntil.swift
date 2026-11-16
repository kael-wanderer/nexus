import Foundation

/// Polls until `condition` holds or `timeout` worth of turns have been taken, for a state an event
/// *will* produce — a fixed sleep guesses how long that takes, and on a busy machine the guess is
/// wrong. It does not fail by itself: the caller's `#expect` says what was wanted. Never use it to
/// show that something does *not* happen; that still needs a sleep.
///
/// The timeout is counted in turns, not read off a clock. Every test here shares one main actor,
/// and another suite holding it for two seconds used to run a clock deadline out before this
/// loop — or the task that would have satisfied it — got a single turn. A turn is one 10 ms
/// sleep, which is also what lets the awaited work in; on an idle machine the two measures agree.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () async -> Bool) async throws {
    let interval = Duration.milliseconds(10)
    var turns = max(1, Int(timeout / interval))
    while await !condition(), turns > 0 {
        try await Task.sleep(for: interval)
        turns -= 1
    }
}
