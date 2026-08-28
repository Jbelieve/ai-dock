import SwiftUI

/// The Settings window: real, live-bound controls for the floating notch.
/// Changes apply instantly (the notch observes the same `DockSettings`).
struct SettingsView: View {
    @Bindable var settings: DockSettings
    let store: UsageStore

    var body: some View {
        Form {
            Section("Notch") {
                Picker("Edge", selection: $settings.edge) {
                    ForEach(DockEdge.allCases) { edge in
                        Text(edge.label).tag(edge)
                    }
                }
                .pickerStyle(.segmented)
                .help("Which screen edge the glass tab hugs.")

                Picker("Refresh every", selection: $settings.refreshInterval) {
                    Text("15s").tag(15.0)
                    Text("30s").tag(30.0)
                    Text("1 min").tag(60.0)
                    Text("5 min").tag(300.0)
                }
                .help("How often AI Dock re-scans your local usage.")
            }

            Section("Providers") {
                if store.detectedProviders.isEmpty {
                    Text("No AI providers detected on this Mac yet. Install/sign in to a CLI (Claude Code, Codex, Gemini) or export an API key in your shell rc — it will appear here automatically.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(store.detectedProviders) { provider in
                        ProviderToggleRow(
                            provider: provider,
                            isOn: settings.isEnabled(provider.id),
                            toggle: { settings.toggle(provider.id) }
                        )
                    }
                    Text("\(store.snapshots.count) of \(store.detectedProviders.count) shown in the notch.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("System") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .help("Start AI Dock automatically when you sign in.")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420, height: 460)
        .background {
            // Deployment target is macOS 26, so Liquid Glass is always available.
            Rectangle().glassEffect(.regular, in: .rect)
        }
    }
}

private struct ProviderToggleRow: View {
    let provider: Provider
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(provider.accent.opacity(0.18))
                ProviderGlyph(kind: provider.glyph, size: 16)
                    .foregroundStyle(provider.accent)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName).font(.body.weight(.medium))
                Text(sourceLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in toggle() }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private var sourceLabel: String {
        switch provider.source {
        case .cliBinary(let p): return "CLI · \(p)"
        case .configDirectory(let p): return "Config · \(p)"
        case .credentialsFile(let p): return "Credentials · \(p)"
        case .unknown: return "Demo data"
        }
    }
}
