import SwiftUI

/// Who is signed in. Milestone 1 only has a debug-only fake login.
/// Milestone 2 replaces this with Sign in with Apple + Supabase.
@Observable
final class Session {
    var displayName: String?

    var isSignedIn: Bool { displayName != nil }

    func signOut() { displayName = nil }

    #if DEBUG
    func debugSignIn() { displayName = "Debug User" }
    #endif
}
