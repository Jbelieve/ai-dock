import Foundation

/// Turns a pile of local session files into a usage estimate that *always*
/// renders sensibly — never a dead "0% with empty ring" that looks broken.
///
/// Two signals, both derived from file modification times (local, no network):
/// - **session** (rolling window, the red bar): how much activity happened in
///   the most recent window, normalised against a soft per-provider cap.
/// - **allModels** (weekly, the green bar): broader recent activity.
///
/// A provider that was used recently but is now idle still shows a decaying,
/// non-zero value (recency weighting) so the ring never reads as "broken".
enum UsageMetrics {

    struct Sample {
        let session: Double          // 0...1
        let allModels: Double        // 0...1
        let sessionReset: Date?
        let allModelsReset: Date?
    }

    /// Score a set of file modification dates.
    /// - Parameters:
    ///   - dates: modification dates of the provider's session files.
    ///   - sessionCap: file-count at which the rolling window reads as "full".
    ///   - weeklyCap: file-count at which the weekly bar reads as "full".
    ///   - windowSeconds: length of the rolling "current session" window.
    static func score(dates: [Date],
                      sessionCap: Double = 40,
                      weeklyCap: Double = 200,
                      windowSeconds: TimeInterval = 5 * 3600) -> Sample {
        let now = Date()
        guard let latest = dates.max() else {
            return Sample(session: 0, allModels: 0, sessionReset: nil, allModelsReset: nextMidnight(after: now))
        }

        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let windowStart = now.addingTimeInterval(-windowSeconds)

        let inWindow = dates.filter { $0 >= windowStart }.count
        let inWeek = dates.filter { $0 >= weekAgo }.count

        // Base fractions from raw counts.
        var session = min(1.0, Double(inWindow) / sessionCap)
        var allModels = min(1.0, Double(inWeek) / weeklyCap)

        // Recency boost/decay: if the latest activity is recent, lift the
        // session value so an actively-used provider reads as "in use" even if
        // the raw count is modest; if it's stale, decay toward zero smoothly.
        let ageHours = now.timeIntervalSince(latest) / 3600
        let recency = max(0, min(1, 1 - (ageHours / 12)))   // full at 0h, gone by 12h
        session = max(session, recency * 0.5)               // at least reflect "used recently"
        allModels = max(allModels, min(1.0, recency * 0.35 + Double(inWeek) / weeklyCap))

        // Rolling window resets relative to the latest activity (when the
        // current window would close), falling back to next block boundary.
        let t = now.timeIntervalSinceReferenceDate
        let sessionReset: Date? = latest > windowStart
            ? latest.addingTimeInterval(windowSeconds)
            : now.addingTimeInterval(windowSeconds - t.truncatingRemainder(dividingBy: windowSeconds))
        let allReset = nextMidnight(after: now)

        return Sample(session: session, allModels: allModels,
                      sessionReset: sessionReset, allModelsReset: allReset)
    }

    /// Recursively collect modification dates of files matching `suffix` under
    /// `root`. Returns [] if root doesn't exist.
    static func modificationDates(under root: URL, suffix: String) -> [Date] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }

        var dates: [Date] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(suffix) else { continue }
            if let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let d = vals.contentModificationDate {
                dates.append(d)
            }
        }
        return dates
    }

    static func nextMidnight(after date: Date) -> Date {
        Calendar.current.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0),
                                  matchingPolicy: .nextTime) ?? date.addingTimeInterval(86_400)
    }
}
