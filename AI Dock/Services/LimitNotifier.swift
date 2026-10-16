import Foundation
import UserNotifications

/// Tells the user when a limit crosses the watch line, when it is reached, and
/// when it resets — and nothing else.
///
/// Ported from Codenotch, whose release notes describe the exact behaviour:
/// *"A system notification the moment a provider's headline limit crosses 80%,
/// and again at 100%"*, *"Displays a notification card … when a provider's usage
/// limit resets"*, and *"Opening Codenotch no longer announces a limit that was
/// reached long before: a reading kept from last time is no longer mistaken for
/// something that just happened."*
///
/// That last point is the whole design: this only fires on a **transition**
/// observed between two readings in this session, so a launch after a week away
/// cannot replay a week of alerts.
@MainActor
final class LimitNotifier {

    static let shared = LimitNotifier()

    /// Last severity seen per provider+window, and whether it was already
    /// announced. In-memory on purpose: a fresh launch has nothing to compare
    /// against yet, and inventing a transition is exactly the bug being avoided.
    private var lastSeverity: [String: WindowSeverity] = [:]
    private var lastFraction: [String: Double] = [:]
    private var authorised = false

    private init() {}

    /// Compare against the previous observation and announce only real changes.
    func evaluate(_ snapshots: [UsageSnapshot], settings: DockSettings) {
        requestAuthorisationIfNeeded()

        for snap in snapshots where snap.hasData {
            // Evaluate the window the ring leads with, plus any scoped window
            // that is itself critical — a spent model limit deserves its own alert.
            var windows = snap.windows
            if windows.isEmpty {
                windows = [
                    UsageWindow(id: "session", kind: "session", label: "session",
                                usedFraction: snap.sessionUsedFraction,
                                resetsAt: snap.sessionResetsAt,
                                severity: .classify(snap.sessionUsedFraction,
                                                    watch: settings.watchThreshold, critical: 1.0),
                                scope: nil),
                    UsageWindow(id: "weekly", kind: "weekly", label: "weekly",
                                usedFraction: snap.allModelsUsedFraction,
                                resetsAt: snap.allModelsResetsAt,
                                severity: .classify(snap.allModelsUsedFraction,
                                                    watch: settings.watchThreshold, critical: 1.0),
                                scope: nil)
                ]
            }

            for window in windows {
                let key = "\(snap.id):\(window.id)"
                let severity = WindowSeverity.classify(window.usedFraction,
                                                       watch: settings.watchThreshold,
                                                       critical: 1.0)
                let previous = lastSeverity[key]
                let previousFraction = lastFraction[key]

                // A reset: the window rolled over since we last looked.
                if let pf = previousFraction, window.usedFraction + 0.001 < pf,
                   let resets = window.resetsAt {
                    announce(title: "\(snap.provider.displayName) limit reset",
                             body: "\(window.label.capitalized) is back to 0%. Resets again \(Self.format(resets)).")
                } else if severity != previous, let previous {
                    // Only announce an *escalation*, and only from a state we
                    // actually observed earlier in this session.
                    if severity.rank < previous.rank {
                        switch severity {
                        case .critical:
                            announce(title: "\(snap.provider.displayName) limit reached",
                                     body: "\(window.label.capitalized) is spent\(window.resetsAt.map { ". Resets \(Self.format($0))" } ?? "").")
                        case .warning:
                            announce(title: "\(snap.provider.displayName) limit close",
                                     body: "\(window.label.capitalized) is at \(Int((window.usedFraction * 100).rounded()))%.")
                        case .normal:
                            break
                        }
                    }
                }

                lastSeverity[key] = severity
                lastFraction[key] = window.usedFraction
            }
        }
    }

    private func requestAuthorisationIfNeeded() {
        guard !authorised else { return }
        authorised = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func announce(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // Codenotch keeps alert chimes on the ordinary output rather than the
        // interface sound-effects channel; the default sound does that.
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f.string(from: date)
    }
}
