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

    /// Turn this ON (true) once the paid Apple account is set up and the `apple-link` / `apple-delete-account` Edge Functions are deployed
    /// (docs/APPLE_ACCOUNT_STEPS.md). Apple requires that deleting an account also disconnects Sign in with Apple. While it is off, deleting
    /// an account works but does not tell Apple — fine for testing, NOT acceptable for the App Store.
    static let appleRevocationEnabled = false

    static var isConfigured: Bool {
        !supabasePublishableKey.hasPrefix("YOUR-") && !(supabaseURL.host ?? "").hasPrefix("YOUR-")
    }
}
