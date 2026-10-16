import Foundation

/// Keeps Claude's saved login usable without the user having to run Claude Code
/// by hand.
///
/// Ported from Codenotch, whose release notes describe the same failure this
/// fixes: *"Claude's saved login is about to expire and the `claude` command
/// isn't installed to renew it. Run Claude Code once to sign in again."* —
/// i.e. renewal is **delegated to the CLI**, which owns the refresh token.
///
/// That delegation is deliberate and we keep it. Reimplementing the OAuth
/// refresh means two processes rotating the same single-use refresh token
/// against each other, and the loser silently invalidates the user's login.
/// The CLI also rotates `~/.claude/.credentials.json` in place, and Codenotch
/// notes the CLI *"files a new keychain entry on every token rotation"* — so
/// reading a rotated file is normal, picking an entry at random is not.
///
/// Two further lessons from Codenotch's changelog are encoded here:
/// - *"It now runs from a single place, in print mode, writing no session at
///   all."* → the working directory is stable and print mode is used, so we do
///   not litter `~/.claude/projects/` with a transcript folder per poll.
/// - *"Renewing Claude's login no longer starts your MCP servers and hooks"*
///   → `--strict-mcp-config` with an empty config set.
enum ClaudeTokenRefresher {

    /// The CLI's credential file. `CLAUDE_CONFIG_DIR` selects a work login, so
    /// a second account is a different file rather than a different app.
    static var credentialsFile: URL {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir).appendingPathComponent(".credentials.json")
        }
        return ClaudeCodeDetector.credentials
    }

    struct Credential {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
    }

    static func credential() -> Credential? {
        guard let data = try? Data(contentsOf: credentialsFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        // `expiresAt` is milliseconds since the epoch.
        let expires = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Credential(accessToken: token,
                          refreshToken: oauth["refreshToken"] as? String,
                          expiresAt: expires)
    }

    /// A token we are confident the usage endpoint will accept, renewing first
    /// if it is about to lapse.
    ///
    /// Returns the current token even when it looks expired: the endpoint is the
    /// authority on whether a token is dead, and a stale token that still works
    /// beats refusing to ask.
    static func validAccessToken() async -> String? {
        guard let cred = credential() else { return nil }

        // Renew a little before expiry rather than after: the ring should never
        // blank out for the minute a renewal takes.
        let margin: TimeInterval = 5 * 60
        guard let expires = cred.expiresAt, expires.timeIntervalSinceNow < margin else {
            return cred.accessToken
        }
        guard await renew() else { return cred.accessToken }

        // Re-read: the CLI rewrote the file it owns.
        return credential()?.accessToken ?? cred.accessToken
    }

    // MARK: - Renewal via the CLI

    @MainActor private static var lastAttempt = Date.distantPast
    /// The CLI is an outbound process with the user's whole config behind it;
    /// never run it more than once every few minutes.
    private static let cooldown: TimeInterval = 300

    /// Claim the right to run the CLI, or report that we ran it too recently.
    /// Kept on the main actor so two overlapping refreshes cannot both spawn.
    @MainActor
    private static func claimRenewalSlot() -> Bool {
        guard Date().timeIntervalSince(lastAttempt) > cooldown else { return false }
        lastAttempt = Date()
        return true
    }

    /// Ask the CLI to renew its own session.
    ///
    /// Flags, all verified against the installed `claude` binary:
    /// - `-p` / `--print` — non-interactive, no TUI.
    /// - `--no-session-persistence` — writes no transcript, so polling does not
    ///   fill `~/.claude/projects/` with empty sessions.
    /// - `--strict-mcp-config` with no `--mcp-config` — starts no MCP servers.
    @discardableResult
    static func renew() async -> Bool {
        guard await claimRenewalSlot() else { return false }
        guard let binary = claudeBinary() else { return false }

        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "-p", "ok",
            "--no-session-persistence",
            "--strict-mcp-config",
            "--model", "haiku"
        ]
        // A fixed, private working directory: Codenotch learned that reading
        // usage from a fresh directory every poll made Claude Code file a
        // transcript folder for each one.
        let cwd = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-dock-renewal", isDirectory: true)
        try? FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        process.currentDirectoryURL = cwd
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // Inherit the user's environment so the CLI finds its own config.
        process.environment = ProcessInfo.processInfo.environment

        do {
            try process.run()
        } catch {
            return false
        }

        // Bounded wait off the main actor: a hung CLI must never wedge the UI.
        let exited = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let deadline = Date().addingTimeInterval(25)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.25)
                }
                if process.isRunning {
                    process.terminate()
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: process.terminationStatus == 0)
                }
            }
        }
        return exited
    }

    /// The `claude` binary, searched where a global install actually lands —
    /// including the nvm / Volta / pnpm layouts Codenotch had to add.
    static func claudeBinary() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.volta/bin/claude",
            "\(home)/Library/pnpm/claude"
        ]
        // nvm keeps one directory per installed version.
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            candidates += versions.map { "\(nvm)/\($0)/bin/claude" }
        }
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
}
