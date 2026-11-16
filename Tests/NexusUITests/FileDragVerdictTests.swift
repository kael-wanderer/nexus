import AppKit
import Foundation
import Testing

@testable import NexusUI

@Suite("File drag verdict")
@MainActor
struct FileDragVerdictTests {
    private func urls(_ count: Int, ext: String = "pdf") -> [URL] {
        (0..<count).map { URL(fileURLWithPath: "/tmp/file\($0).\(ext)") }
    }

    @Test("A few ordinary files copy and outline the row")
    func ordinary() {
        let verdict = FileDragVerdict(urls: urls(3))
        #expect(verdict.operation == .copy)
        #expect(verdict.outlinesRow)
    }

    @Test("More than the drop limit is refused with no outline")
    func tooMany() {
        let verdict = FileDragVerdict(urls: urls(SidebarViewModel.maximumDroppedFiles + 1))
        #expect(verdict.operation.isEmpty)
        #expect(verdict.outlinesRow == false)
        #expect(FileDragVerdict(urls: urls(SidebarViewModel.maximumDroppedFiles)).operation == .copy)
    }

    @Test("An application bundle is taken but does not outline the row, whatever its case")
    func applicationBundle() {
        for ext in ["app", "APP"] {
            let verdict = FileDragVerdict(urls: urls(1, ext: ext))
            #expect(verdict.operation == .copy)
            #expect(verdict.outlinesRow == false)
        }
    }

    @Test("Folders alone are taken as a pin: no outline, unless Option asks to open them")
    func foldersAlone() {
        let verdict = FileDragVerdict(urls: urls(2, ext: ""), isPlainFolder: { _ in true })
        #expect(verdict.operation == .copy)
        #expect(verdict.outlines(optionHeld: false) == false)
        #expect(verdict.outlines(optionHeld: true))
    }

    @Test("A folder among files outlines the row: the whole drop opens in the application")
    func folderAmongFiles() {
        let all = urls(2)
        let verdict = FileDragVerdict(urls: all, isPlainFolder: { $0 == all[0] })
        #expect(verdict.outlines(optionHeld: false))
    }

    @Test("Option does not turn an application bundle into something to open")
    func bundleWithOption() {
        let verdict = FileDragVerdict(urls: urls(1, ext: "app"), isPlainFolder: { _ in true })
        #expect(verdict.outlines(optionHeld: true) == false)
    }

    @Test("Nothing to drag is refused")
    func empty() {
        let verdict = FileDragVerdict(urls: [])
        #expect(verdict.operation.isEmpty)
        #expect(verdict.outlinesRow == false)
    }
}
