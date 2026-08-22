import Foundation
import os

/// Structured logging, one `Logger` per §66 category. All logging goes through here so the
/// privacy rules live in one place: paths, window titles and search queries are `.private`;
/// bundle identifiers, counts and error codes are `.public`.
public enum Log {
    public static let subsystem = "com.congbui.nexus"

    public static let app = Logger(subsystem: subsystem, category: "Nexus.App")
    public static let sidebar = Logger(subsystem: subsystem, category: "Nexus.Sidebar")
    public static let search = Logger(subsystem: subsystem, category: "Nexus.Search")
    public static let windows = Logger(subsystem: subsystem, category: "Nexus.Windows")
    public static let applications = Logger(subsystem: subsystem, category: "Nexus.Applications")
    public static let system = Logger(subsystem: subsystem, category: "Nexus.System")
    public static let permissions = Logger(subsystem: subsystem, category: "Nexus.Permissions")

    /// Latency budgets (§68) are measured with signposts, not log lines.
    public static let signposter = OSSignposter(subsystem: subsystem, category: "Performance")

    /// Seconds since this process was exec'd, read from the kernel so the number includes dyld
    /// and runtime setup — the honest "cold start" the user experiences.
    public static func secondsSinceProcessStart() -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, ProcessInfo.processInfo.processIdentifier]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let started = Double(info.kp_proc.p_starttime.tv_sec)
            + Double(info.kp_proc.p_starttime.tv_usec) / 1_000_000
        return Date().timeIntervalSince1970 - started
    }
}
