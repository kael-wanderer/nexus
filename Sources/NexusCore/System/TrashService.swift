import AppKit
import Foundation

/// The Trash, as much of it as a sidebar needs: show it, empty it.
///
/// Deliberately no full/empty state. Reading `~/.Trash` needs Full Disk Access, and an icon that
/// silently draws "empty" over a full Trash whenever the grant is missing is worse than one icon
/// that never claims to know (D55).
public enum TrashService {
    public static var url: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
    }


    /// TEMPORARY probe (removed once the detection method is chosen).
    public static func probe() {
        let path = url.path
        let listed = (try? FileManager.default.contentsOfDirectory(atPath: path))?.count
        var status = stat()
        let statOK = stat(path, &status) == 0
        var child = stat()
        let dsStore = stat(path + "/.DS_Store", &child) == 0
        var missing = stat()
        let bogus = stat(path + "/definitely-not-there", &missing) == 0
        Log.system.notice("Trash probe: listed=\(String(describing: listed), privacy: .public) statOK=\(statOK, privacy: .public) nlink=\(status.st_nlink, privacy: .public) dsStore=\(dsStore, privacy: .public) bogus=\(bogus, privacy: .public)")
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
