import CoreGraphics
import Foundation

/// Window counts without any permission (D5). `CGWindowListCopyWindowInfo` returns owner PID,
/// window number, layer and bounds to anyone; only `kCGWindowName` and window images are
/// withheld until Screen Recording is granted.
public enum WindowCounts {
    /// On-screen, layer-0 (ordinary document) windows grouped by owning process.
    public static func byProcess() -> [pid_t: Int] {
        guard let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]]
        else { return [:] }

        var counts: [pid_t: Int] = [:]
        for window in info {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t
            else { continue }
            counts[pid, default: 0] += 1
        }
        return counts
    }

    /// Window numbers for one process, so AX elements can be correlated at Milestone 4.
    public static func windowNumbers(for pid: pid_t) -> [CGWindowID] {
        guard let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]]
        else { return [] }

        return info.compactMap { window in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  let number = window[kCGWindowNumber as String] as? CGWindowID
            else { return nil }
            return number
        }
    }
}
