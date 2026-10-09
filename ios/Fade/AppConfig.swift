import Foundation

/// Public connection details for the Supabase backend.
/// The URL and the *publishable* (anon) key are designed to be public — Row Level Security
/// protects the data. NEVER put a "secret" or "service_role" key in this file.
enum AppConfig {
    static let supabaseURL = URL(string: "https://skfbqidighnmhsvgscxf.supabase.co")!
    static let supabasePublishableKey = "sb_publishable_7qb-Y5Tp7ClDHgzgeCuGDw_chBeMDFt"

    /// Public web pages (hosted free from the repository's docs/ folder with GitHub Pages — see docs/APPLE_ACCOUNT_STEPS.md).
    static let supportURL = "https://dschermer.github.io/Fade/"
    static let privacyURL = "https://dschermer.github.io/Fade/privacy.html"
    static let termsURL = "https://dschermer.github.io/Fade/terms.html"

    static var isConfigured: Bool {
        !supabasePublishableKey.hasPrefix("YOUR-") && !(supabaseURL.host ?? "").hasPrefix("YOUR-")
    }
}
