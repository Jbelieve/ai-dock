import Foundation

/// DeepSeek — prepaid balance and spend, from DeepSeek's own public API.
///
/// Unlike Codenotch, which signs into `platform.deepseek.com` in a web view and
/// scrapes the console, DeepSeek publishes this over an ordinary authenticated
/// API, so no browser session is involved:
///
///   GET https://api.deepseek.com/user/balance
///   200 {"is_available":true,"balance_infos":[
///          {"currency":"USD","total_balance":"178.44",
///           "granted_balance":"99.67","topped_up_balance":"78.77"}]}
///
/// The key is borrowed from wherever it already lives on this machine — the
/// DSH harness credential store, an OpenCode entry, or the shell environment.
enum DeepSeekDetector {

    private static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    /// Where a DeepSeek key is looked for, in priority order. Every source is a
    /// file some other tool already owns; nothing here writes to them.
    static func apiKey() -> String? {
        // The DSH harness stores it under `refs:` in its own credential file.
        if let key = ProviderCredentials.yamlScalar(
            named: "DEEPSEEK_API_KEY",
            in: ProviderCredentials.dshCredentialsFile) { return key }
        if let key = ProviderCredentials.openCodeKey(for: "deepseek") { return key }
        return ProviderCredentials.exportedValue(named: "DEEPSEEK_API_KEY")
    }

    static func detect() -> DetectionSource? {
        guard let key = apiKey(), !key.isEmpty else { return nil }
        if ProviderCredentials.yamlScalar(named: "DEEPSEEK_API_KEY",
                                         in: ProviderCredentials.dshCredentialsFile) != nil {
            return .credentialsFile(path: ProviderCredentials.dshCredentialsFile.path
                + " (DEEPSEEK_API_KEY)")
        }
        if ProviderCredentials.openCodeKey(for: "deepseek") != nil {
            return .credentialsFile(path: ProviderCredentials.openCodeAuthFile.path + " (deepseek)")
        }
        return .credentialsFile(path: "DEEPSEEK_API_KEY")
    }

    // MARK: - Reading

    /// A balance is not a quota: there is no window to fill. The reading carries
    /// the money and is flagged balance-only so the notch prints the amount
    /// instead of inventing a percentage.
    static func fetchUsage(force: Bool = false) async -> UsageReading? {
        guard let key = apiKey(), !key.isEmpty else { return nil }

        var req = URLRequest(url: balanceURL)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        guard let (body, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let infos = json["balance_infos"] as? [[String: Any]]
        else { return nil }

        // Amounts are strings in this API. With several currencies listed,
        // prefer the wallet that actually holds money rather than the first.
        let wallets = infos.compactMap { info -> (currency: String, total: Double, granted: Double, topped: Double)? in
            guard let currency = info["currency"] as? String,
                  let total = Double(info["total_balance"] as? String ?? "") else { return nil }
            return (currency,
                    total,
                    Double(info["granted_balance"] as? String ?? "") ?? 0,
                    Double(info["topped_up_balance"] as? String ?? "") ?? 0)
        }
        guard let wallet = wallets.first(where: { $0.total > 0 }) ?? wallets.first else { return nil }

        return UsageReading(
            session: 0,
            allModels: 0,
            sessionReset: nil,
            allReset: nil,
            windows: [],
            plan: PlanInfo(tier: "deepseek-prepaid", displayName: "Prepaid balance",
                           monthlyUSD: nil, creditUSD: nil),
            credits: CreditInfo(resetCredits: nil, nextExpiry: nil,
                                balance: wallet.total,
                                currency: wallet.currency,
                                monthlyLimit: nil,
                                usedCredits: nil),
            isLive: true,
            balanceOnly: true,
            balanceDetail: BalanceDetail(currency: wallet.currency,
                                         granted: wallet.granted,
                                         toppedUp: wallet.topped,
                                         available: (json["is_available"] as? Bool) ?? true))
    }
}

/// A prepaid wallet's breakdown, for the popover.
struct BalanceDetail: Hashable {
    let currency: String
    /// Promotional credit that expires.
    let granted: Double
    /// Money actually paid in.
    let toppedUp: Double
    let available: Bool
}
