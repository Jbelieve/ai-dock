import SwiftUI

/// The Costs card: what each project spent, in money, read from the transcripts
/// Claude Code and Codex already keep.
struct CostsCard: View {
    @Bindable var center: CostCenter
    @Namespace private var rangeSpace
    @Namespace private var groupSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !center.isAvailable {
                Text("Cost tracking is unavailable — the local database could not be opened.")
                    .font(.system(size: 12))
                    .foregroundStyle(Dock.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                headline
                rangePicker
                groupPicker
                spendList
                attributionList
                provenance
            }
        }
        .animation(Dock.Motion.snappy, value: center.range)
        .animation(Dock.Motion.snappy, value: center.group)
    }

    // MARK: - Headline

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(money(center.totalUSD))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Dock.Ink.primary)
                .shadow(color: Dock.Accent.claude.opacity(0.28), radius: 8)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("across \(center.range.label.lowercased())")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Dock.Ink.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                        }
                )

            Spacer()
            if center.isIndexing {
                Circle()
                    .fill(Dock.Accent.codex)
                    .frame(width: 7, height: 7)
                    .shadow(color: Dock.Accent.codex, radius: 4)
            }
        }
    }

    // MARK: - Pickers

    private var rangePicker: some View {
        segmented(CostRange.allCases, selection: center.range, namespace: rangeSpace) { val in
            withAnimation(Dock.Motion.snappy) { center.range = val }
        }
        .help("Which slice of time to total up.")
    }

    private var groupPicker: some View {
        segmented(CostGroup.allCases, selection: center.group, namespace: groupSpace) { val in
            withAnimation(Dock.Motion.snappy) { center.group = val }
        }
        .help("How to break the total down.")
    }

    private func segmented<T: Hashable & Identifiable>(
        _ items: [T],
        selection: T,
        namespace: Namespace.ID,
        set: @escaping (T) -> Void
    ) -> some View {
        HStack(spacing: 3) {
            ForEach(items) { item in
                let isOn = item == selection
                Button {
                    set(item)
                } label: {
                    Text(label(of: item))
                        .font(.system(size: 11.5, weight: isOn ? .semibold : .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6.5)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.20),
                                                Color.white.opacity(0.09)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(
                                                LinearGradient(
                                                    colors: [
                                                        Color.white.opacity(0.32),
                                                        Color.white.opacity(0.06)
                                                    ],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                                lineWidth: 0.85
                                            )
                                    }
                                    .shadow(color: .black.opacity(0.28), radius: 4, x: 0, y: 2)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .foregroundStyle(isOn ? Dock.Ink.primary : Dock.Ink.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3.5)
        .dockGlassWell(cornerRadius: 11)
    }

    private func label(of item: Any) -> String {
        if let r = item as? CostRange { return r.label }
        if let g = item as? CostGroup { return g.label }
        return ""
    }

    // MARK: - Lists

    @ViewBuilder
    private var spendList: some View {
        if center.rows.isEmpty {
            Text("Nothing indexed yet. Spend appears a few minutes after an agent session starts — the numbers are read from the transcripts each tool writes, never uploaded.")
                .font(.system(size: 12))
                .foregroundStyle(Dock.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let top = Array(center.rows.prefix(6))
            let maxUSD = max(top.first?.usd ?? 1, 0.0001)
            VStack(spacing: 9) {
                ForEach(Array(top.enumerated()), id: \.element.id) { index, row in
                    let barAccent = index == 0 ? Dock.Accent.claude : Dock.Accent.claude.opacity(0.82)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.label)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Dock.Ink.primary)
                                .lineLimit(1).truncationMode(.head)
                            Spacer()
                            Text("\(compact(row.tokens)) tok")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Dock.Ink.tertiary)
                                .monospacedDigit()
                                .padding(.trailing, 4)
                            Text(money(row.usd))
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(Dock.Ink.primary)
                                .monospacedDigit()
                        }
                        UsageBar(
                            fraction: row.usd / maxUSD,
                            accent: barAccent,
                            height: 5
                        )
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
                    }
            )

            if center.rows.count > top.count {
                Text("and \(center.rows.count - top.count) more")
                    .font(.system(size: 11))
                    .foregroundStyle(Dock.Ink.tertiary)
            }
        }
    }

    /// Quota points attributed to a project — the figure that answers "what did
    /// this cost me of my allowance", which money alone cannot.
    @ViewBuilder
    private var attributionList: some View {
        let rows = center.attributed
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("SHARE OF ALLOWANCE")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(Dock.Ink.tertiary)
                ForEach(groupedAttribution(rows), id: \.key) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text(shortLabel(entry.key))
                            .font(.system(size: 12))
                            .foregroundStyle(entry.key == AttributionRow.unexplained
                                             ? Dock.Ink.tertiary : Dock.Ink.primary)
                            .lineLimit(1).truncationMode(.head)
                        Spacer()
                        Text(String(format: "%.1f pp", entry.value))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Dock.Ink.secondary)
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                }
            }
        }
    }

    private func groupedAttribution(_ rows: [AttributionRow]) -> [(key: String, value: Double)] {
        var sums: [String: Double] = [:]
        for r in rows { sums[r.project, default: 0] += r.deltaPct }
        return sums
            .map { (key: $0.key, value: $0.value) }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0 }
    }

    private func shortLabel(_ path: String) -> String {
        if path == AttributionRow.unexplained { return "Not from this Mac" }
        return path.split(separator: "/").suffix(2).joined(separator: "/")
    }

    // MARK: - Provenance

    @ViewBuilder
    private var provenance: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let report = center.lastReport {
                Text("\(center.eventCount) calls indexed · last pass read \(report.filesRead) file\(report.filesRead == 1 ? "" : "s")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Dock.Ink.tertiary)
            }
            if !center.unpricedModels.isEmpty {
                Text("No price for: \(center.unpricedModels.prefix(3).joined(separator: ", ")) — excluded from the total")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Read locally from ~/.claude and ~/.codex transcripts. Nothing leaves this Mac.")
                .font(.system(size: 10.5))
                .foregroundStyle(Dock.Ink.tertiary)
        }
        .padding(.top, 2)
    }

    // MARK: - Formatting

    private func money(_ usd: Double) -> String {
        if usd >= 1000 { return String(format: "$%.0f", usd) }
        if usd >= 10 { return String(format: "$%.2f", usd) }
        return String(format: "$%.2f", usd)
    }

    private func compact(_ tokens: Int) -> String {
        let n = Double(tokens)
        if n >= 1_000_000_000 { return String(format: "%.1fB", n / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", n / 1_000) }
        return "\(tokens)"
    }
}
