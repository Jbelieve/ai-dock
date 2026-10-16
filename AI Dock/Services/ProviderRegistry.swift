import Foundation

/// Discovers which AI providers are present on this machine and produces their
/// latest usage snapshots.
///
/// Providers are now described as data in `ProviderCatalog` (the pattern ported
/// from Codenotch, whose `AppDelegate` holds a list of 32 `UsageProvider`
/// conformers). Adding one is a single entry there — no switch to keep in sync.
///
/// The distinction between **authoritative** and **estimated** readings is kept
/// honest all the way to the UI: authoritative numbers come from the provider
/// itself (its own server, or a credential/file the provider wrote), estimated
/// numbers are derived from local file activity.
@MainActor
enum ProviderRegistry {

    /// Run every adapter's detector and return the providers found, in catalog
    /// order so rings never jump around between refreshes.
    static func detectAll() -> [Provider] {
        ProviderCatalog.all.compactMap { adapter in
            guard let source = adapter.detect() else { return nil }
            return Provider(id: adapter.id,
                            displayName: adapter.displayName,
                            glyph: adapter.glyph,
                            accent: adapter.accent,
                            source: source)
        }
    }

    /// Build a usage snapshot for a detected provider.
    ///
    /// Real data wins; when a provider cannot be read, the snapshot carries no
    /// data and the ring shows "—" rather than a misleading 0%.
    static func snapshot(for provider: Provider, force: Bool = false) async -> UsageSnapshot {
        let adapter = ProviderCatalog.all.first { $0.id == provider.id }
        let reading = await adapter?.read(force)

        let now = Date()
        return UsageSnapshot(
            id: provider.id,
            provider: provider,
            sessionUsedFraction: reading?.session ?? 0,
            sessionResetsAt: reading?.sessionReset,
            allModelsUsedFraction: reading?.allModels ?? 0,
            allModelsResetsAt: reading?.allReset,
            capturedAt: now,
            hasData: reading != nil,
            windows: reading?.windows ?? [],
            plan: reading?.plan,
            credits: reading?.credits,
            isLive: reading?.isLive ?? false,
            isAuthoritative: reading?.isAuthoritative ?? false,
            balanceOnly: reading?.balanceOnly ?? false,
            balanceDetail: reading?.balanceDetail,
            stats: reading?.stats
        )
    }
}
