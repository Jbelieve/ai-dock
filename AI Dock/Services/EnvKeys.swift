import Foundation

/// Tiny helper that scans a user's shell rc files for the presence of API-key
/// exports — a signal that a provider subscription is "live" on this machine
/// even when no CLI binary is installed. Read-only, local, no network.
enum EnvKeys {

    /// True if any of `keys` appears as an export/assignment in any of `files`.
    static func contains(anyOf keys: [String], in files: [String]) -> Bool {
        for path in files {
            guard let text = try? String(contentsOfFile: path) else { continue }
            for key in keys where text.contains(key) { return true }
        }
        return false
    }
}
