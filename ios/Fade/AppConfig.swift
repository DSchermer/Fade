import Foundation

/// Public connection details for the Supabase backend.
/// The URL and the *publishable* (anon) key are designed to be public — Row Level Security
/// protects the data. NEVER put a "secret" or "service_role" key in this file.
enum AppConfig {
    static let supabaseURL = URL(string: "https://skfbqidighnmhsvgscxf.supabase.co")!
    static let supabasePublishableKey = "sb_publishable_7qb-Y5Tp7ClDHgzgeCuGDw_chBeMDFt"

    static var isConfigured: Bool {
        !supabasePublishableKey.hasPrefix("YOUR-") && !(supabaseURL.host ?? "").hasPrefix("YOUR-")
    }
}
