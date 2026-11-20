import Foundation

struct SupabaseConfiguration: Sendable {
    let projectURL: URL
    let publishableKey: String

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SupabaseConfiguration? {
        guard
            let rawURL = environment["SUPABASE_URL"]
                ?? (bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String),
            let rawKey = environment["SUPABASE_PUBLISHABLE_KEY"]
                ?? (bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String),
            let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme == "https",
            url.host?.hasSuffix(".supabase.co") == true
        else { return nil }

        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("YOUR_") else { return nil }
        return SupabaseConfiguration(projectURL: url, publishableKey: key)
    }
}
