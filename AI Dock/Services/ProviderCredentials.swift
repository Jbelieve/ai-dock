import Foundation

/// Borrows API keys that other tools already store on this machine.
///
/// This is Codenotch's central tactic, stated plainly in its own copy: *"Most
/// readings are borrowed from a tool that already holds the account"* and
/// *"Z.ai's Coding Plan reads live now too, with a key borrowed from whichever
/// tool already holds one."* The user never signs in to AI Dock for these.
///
/// Everything here is read-only. No key is logged, written back, or sent
/// anywhere except the provider's own endpoint.
enum ProviderCredentials {

    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Shell rc files where users commonly export keys.
    static let envFiles = [
        "\(home.path)/.zshrc", "\(home.path)/.zprofile",
        "\(home.path)/.bash_profile", "\(home.path)/.bashrc",
        "\(home.path)/.profile", "\(home.path)/.config/fish/config.fish"
    ]

    // MARK: - OpenCode

    /// OpenCode keeps provider keys in `~/.local/share/opencode/auth.json` as
    /// `{ "<provider-id>": { "type": "api", "key": "…" } }`. Two of its entries
    /// are themselves meters we can read: the Z.ai GLM Coding Plan, and
    /// OpenRouter.
    static var openCodeAuthFile: URL {
        // OpenCode honours XDG_DATA_HOME.
        if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg)
                .appendingPathComponent("opencode/auth.json")
        }
        return home.appendingPathComponent(".local/share/opencode/auth.json")
    }

    /// The stored key for one OpenCode provider id, e.g. `zai-coding-plan`.
    static func openCodeKey(for providerID: String) -> String? {
        guard let data = try? Data(contentsOf: openCodeAuthFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root[providerID] as? [String: Any]
        else { return nil }
        // `key` for api-type entries; tolerate an OAuth-shaped entry too.
        if let key = entry["key"] as? String, !key.isEmpty { return key }
        if let token = entry["access_token"] as? String, !token.isEmpty { return token }
        return nil
    }

    /// True when any OpenCode provider entry exists at all.
    static func hasOpenCodeAuth() -> Bool {
        guard let data = try? Data(contentsOf: openCodeAuthFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return !root.isEmpty
    }

    // MARK: - Qwen

    /// Qwen Code stores its environment (including the Bailian coding-plan key)
    /// in `~/.qwen/settings.json` under `env`.
    static var qwenSettingsFile: URL { home.appendingPathComponent(".qwen/settings.json") }

    static func qwenEnvValue(_ name: String) -> String? {
        guard let data = try? Data(contentsOf: qwenSettingsFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = root["env"] as? [String: Any],
              let value = env[name] as? String, !value.isEmpty
        else { return nil }
        return value
    }

    // MARK: - YAML credential stores

    /// The DSH harness keeps provider keys in a small YAML file under `refs:`.
    /// Read-only, and only the one scalar we ask for.
    static var dshCredentialsFile: URL {
        home.appendingPathComponent(
            "Library/Application Support/dsh-desktop/harness/.credentials.yaml")
    }

    /// Pull a single `NAME: value` scalar out of a YAML file.
    ///
    /// Deliberately a line scan rather than a YAML parser: the file may hold
    /// structures we do not model, and we only ever want one flat scalar. The
    /// value is never logged.
    static func yamlScalar(named name: String, in url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("\(name):") else { continue }
            var value = String(line.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
            // Tolerate an inline comment after the value.
            if let hash = value.firstIndex(of: "#"), value[value.startIndex] != "#" {
                value = String(value[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return value }
        }
        return nil
    }

    // MARK: - Shell rc

    /// Read a single `export NAME=value` out of the user's shell rc files.
    /// Only used for keys that have no dedicated config file.
    static func exportedValue(named name: String) -> String? {
        for path in envFiles {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for rawLine in text.split(separator: "\n") {
                var line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("export ") { line.removeFirst("export ".count) }
                guard line.hasPrefix("\(name)=") || line.hasPrefix("\(name) =") else { continue }
                guard let eq = line.firstIndex(of: "=") else { continue }
                var value = String(line[line.index(after: eq)...])
                    .trimmingCharacters(in: .whitespaces)
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// True when the name appears at all (used for detection, where the value
    /// itself does not matter).
    static func isExported(named name: String) -> Bool {
        EnvKeys.contains(anyOf: [name], in: envFiles)
    }
}
