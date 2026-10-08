import Foundation

/// Public connection details for the Supabase backend.
/// The URL and the *publishable* (anon) key are designed to be public — Row Level Security
/// protects the data. NEVER put a "secret" or "service_role" key in this file.
enum AppConfig {
    static let supabaseURL = URL(string: "https://YOUR-PROJECT-REF.supabase.co")!
    static let supabasePublishableKey = "YOUR-PUBLISHABLE-KEY"

    static var isConfigured: Bool {
        !supabasePublishableKey.hasPrefix("YOUR-") && !(supabaseURL.host ?? "").hasPrefix("YOUR-")
    }
}
