import Foundation
import Supabase

/// The single connection to Supabase used by the whole app.
let supabase = SupabaseClient(
    supabaseURL: AppConfig.supabaseURL,
    supabaseKey: AppConfig.supabasePublishableKey
)
