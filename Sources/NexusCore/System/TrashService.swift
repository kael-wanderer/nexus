import AppKit
import Foundation

/// The Trash, as much of it as a sidebar needs: is it empty, what does it look like, show it,
/// empty it.
public enum TrashService {
    public static var url: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
    }

    /// Files Finder puts there on its own. Counting them would leave the full icon showing over an
    /// empty Trash, because Finder recreates `.DS_Store` as soon as the Trash window is opened.
    private static let housekeeping = [".DS_Store", ".localized"]

    /// Reading `~/.Trash` needs Full Disk Access; `stat` does not, and on APFS a directory's
    /// `st_nlink` is `2 + entry count`, files included. So the count comes from link counts, and
    /// the housekeeping files are subtracted by name (D58).
    ///
    /// An unreadable or missing Trash counts as empty: the only consequence is which icon is drawn.
    public static var isEmpty: Bool { entryCount(in: url.path) <= 0 }

    static func entryCount(in path: String) -> Int {
        var status = stat()
        guard stat(path, &status) == 0 else { return 0 }
        let entries = Int(status.st_nlink) - 2
        guard entries > 0 else { return 0 }
        let noise = housekeeping.count { exists(path + "/" + $0) }
        return max(0, entries - noise)
    }

    private static func exists(_ path: String) -> Bool {
        var status = stat()
        return stat(path, &status) == 0
    }

    /// The Trash icons macOS itself uses. Not protected, so no permission is involved; the SF
    /// Symbol is the fallback if a future macOS moves them.
    public static func icon(empty: Bool) -> NSImage? {
        let name = empty ? "TrashIcon" : "FullTrashIcon"
        let path = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/\(name).icns"
        if let image = NSImage(contentsOfFile: path) { return image }
        return NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
    }

    public static func open() {
        NSWorkspace.shared.open(url)
    }

    /// Finder owns the Trash — emptying it by hand would skip the "put back" bookkeeping and the
    /// locked-item rules. The first call prompts for Automation access; a refusal leaves the
    /// Trash untouched and is logged, never retried silently.
    @discardableResult
    public static func empty() -> Bool {
        guard let script = NSAppleScript(source: "tell application \"Finder\" to empty trash") else {
            return false
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            Log.system.error("Empty Trash failed: \(String(describing: error), privacy: .public)")
            return false
        }
        Log.system.notice("Trash emptied")
        return true
    }
}
