import SwiftUI

/// The Settings window: a premium dark-glass panel consistent with the notch's
/// design language. Live-bound controls — changes apply instantly (the notch
/// observes the same `DockSettings`).
struct SettingsView: View {
    @Bindable var settings: DockSettings
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            card("Position") {
                edgePicker
                sizeRow
                refreshRow
            }

            card("Providers") {
                providerList
            }

            card("System") {
                Toggle(isOn: $settings.launchAtLogin) {
                    Text("Launch at login")
                        .font(.system(size: 13))
                        .foregroundStyle(Dock.Ink.primary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Dock.Accent.codex)
                .help("Start AI Dock automatically when you sign in.")
            }

            Text("Usage is estimated from local CLI activity. Nothing leaves this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(Dock.Ink.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 34)      // room for the transparent title bar's controls
        .frame(width: 460)
        .background {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07)
                RadialGradient(colors: [Dock.Accent.claude.opacity(0.10), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 400)
                RadialGradient(colors: [Dock.Accent.gemini.opacity(0.08), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: 400)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                ProgressRing(fraction: 0.73, accent: Dock.Accent.claude,
                             size: 36, stroke: 3.5)
                ProviderGlyph(kind: .genericBurst, size: 14)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Dock")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Dock.Ink.primary)
                Text("Live usage for the AI subscriptions on this Mac")
                    .font(.system(size: 12))
                    .foregroundStyle(Dock.Ink.secondary)
            }
            Spacer()
        }
        .padding(.bottom, 2)
    }

    // MARK: - Position card

    private var edgePicker: some View {
        HStack(spacing: 4) {
            ForEach(DockEdge.allCases) { e in
                Button {
                    withAnimation(Dock.Motion.gentle) { settings.edge = e }
                } label: {
                    Label(e.label, systemImage: e == .left
                        ? "arrow.left.to.line" : "arrow.right.to.line")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            settings.edge == e ? Color.white.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .foregroundStyle(settings.edge == e
                            ? Dock.Ink.primary : Dock.Ink.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Which screen edge the tab hugs.")
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 10) {
            Text("Size")
                .font(.system(size: 13))
                .foregroundStyle(Dock.Ink.primary)
            Image(systemName: "circle")
                .font(.system(size: 8))
                .foregroundStyle(Dock.Ink.tertiary)
            Slider(value: $settings.scale, in: 0.75...1.4)
                .controlSize(.small)
                .help("Proportional size of the notch — applies live.")
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundStyle(Dock.Ink.tertiary)
            Text("\(Int((settings.scale * 100).rounded()))%")
                .font(.system(size: 12))
                .foregroundStyle(Dock.Ink.secondary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.top, 4)
    }

    private var refreshRow: some View {
        HStack {
            Text("Refresh every")
                .font(.system(size: 13))
                .foregroundStyle(Dock.Ink.primary)
            Spacer()
            Picker("", selection: $settings.refreshInterval) {
                Text("15s").tag(15.0)
                Text("30s").tag(30.0)
                Text("1 min").tag(60.0)
                Text("5 min").tag(300.0)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 92)
            .help("How often AI Dock re-scans your local usage.")
        }
        .padding(.top, 4)
    }

    // MARK: - Providers card

    @ViewBuilder
    private var providerList: some View {
        if store.detectedProviders.isEmpty {
            Text("No AI providers detected on this Mac yet. Install/sign in to a CLI (Claude Code, Codex, Gemini) or export an API key in your shell rc — it will appear here automatically.")
                .font(.system(size: 12))
                .foregroundStyle(Dock.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 2) {
                ForEach(store.detectedProviders) { provider in
                    ProviderToggleRow(
                        provider: provider,
                        snapshot: store.snapshot(for: provider.id),
                        isOn: settings.isEnabled(provider.id),
                        toggle: { settings.toggle(provider.id) }
                    )
                }
            }
            Text("\(store.snapshots.count) of \(store.detectedProviders.count) shown in the dock")
                .font(.system(size: 11))
                .foregroundStyle(Dock.Ink.tertiary)
        }
    }

    // MARK: - Card chrome

    @ViewBuilder
    private func card<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(Dock.Ink.tertiary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}

// MARK: - Provider row

private struct ProviderToggleRow: View {
    let provider: Provider
    let snapshot: UsageSnapshot?
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let snapshot {
                    ProgressRing(fraction: snapshot.sessionUsedFraction,
                                 accent: provider.accent, size: 32, stroke: 3)
                } else {
                    Circle()
                        .stroke(Dock.Surface.ringTrack, lineWidth: 3)
                        .frame(width: 32, height: 32)
                }
                ProviderGlyph(kind: provider.glyph, size: 13)
            }
            .opacity(isOn ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Dock.Ink.primary)
                Text(sourceLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Dock.Ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .opacity(isOn ? 1 : 0.5)

            Spacer()

            Toggle("", isOn: Binding(get: { isOn }, set: { _ in toggle() }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(provider.accent)
                .labelsHidden()
        }
        .padding(.vertical, 6)
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
