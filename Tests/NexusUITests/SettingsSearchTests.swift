import Foundation
import Testing

@testable import NexusUI

@Suite("Searching the settings")
struct SettingsSearchTests {
    @Test("Nothing typed finds nothing — the tabs stay put until there is a word to go on")
    func emptyQuery() {
        #expect(SettingsSearch.matches("").isEmpty)
        #expect(SettingsSearch.matches("   ").isEmpty)
    }

    @Test("A word finds the settings it names, and says which tab they are on")
    func findsByTitleAndKeyword() {
        let byTitle = SettingsSearch.matches("opened group")
        #expect(byTitle.map(\.title) == ["Opened group shows"])
        #expect(byTitle.first?.tab == .behavior)

        // The keywords carry what the label does not say: "list" is nowhere in the title.
        #expect(SettingsSearch.matches("group list").map(\.title) == ["Opened group shows"])
        // …and neither is the American spelling of the row that is spelled the other way.
        #expect(SettingsSearch.matches("favorites").map(\.tab) == [.bar])
    }

    @Test("Every token has to match, so two words narrow rather than widen")
    func tokensNarrow() {
        let one = SettingsSearch.matches("hover")
        let two = SettingsSearch.matches("hover delay")
        #expect(one.count > two.count)
        #expect(two.map(\.title) == ["Hover delay"])
    }

    @Test("A word nothing is called finds nothing, rather than everything")
    func noMatch() {
        #expect(SettingsSearch.matches("teleportation").isEmpty)
    }

    @Test("Every tab is represented, so no pane is unreachable by search")
    func everyTabIndexed() {
        for tab in SettingsTab.allCases {
            #expect(SettingsSearch.entries.contains { $0.tab == tab }, "no entries for \(tab.title)")
        }
    }

    @Test("Entries are unique: the same setting is not indexed twice")
    func uniqueEntries() {
        #expect(Set(SettingsSearch.entries.map(\.id)).count == SettingsSearch.entries.count)
    }
}
