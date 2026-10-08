import Foundation
import Supabase
import SwiftUI

/// Who is signed in, and their profile. The screens react to `state`.
@MainActor
@Observable
final class Session {
    enum State {
        case loading        // checking for a saved login at launch
        case signedOut
        case needsUsername  // signed in, but no username picked yet
        case ready
    }

    var state: State = .loading
    var profile: Profile?
    var errorMessage: String?
    var isBusy = false

    // MARK: Launch

    /// Called once at launch: restores a saved login if there is one.
    func restore() async {
        guard AppConfig.isConfigured else {
            state = .signedOut
            return
        }
        do {
            _ = try await supabase.auth.session
            await loadProfile()
        } catch {
            state = .signedOut
        }
    }

    // MARK: Signing in and out

    func signInWithApple(idToken: String, nonce: String) async {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            _ = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            await loadProfile()
        } catch {
            errorMessage = "Sign in failed: \(Self.describe(error))"
            state = .signedOut
        }
    }

    #if DEBUG
    /// Debug builds only: sign in (or create) a test account with email + password so you can
    /// test with several different users. Not compiled into release builds.
    func debugEmailSignIn(email: String, password: String) async {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            _ = try await supabase.auth.signIn(email: email, password: password)
        } catch {
            do {
                _ = try await supabase.auth.signUp(email: email, password: password)
            } catch {
                errorMessage = "Debug sign in failed: \(Self.describe(error))"
                return
            }
        }
        await loadProfile()
    }
    #endif

    func signOut() async {
        try? await supabase.auth.signOut()
        profile = nil
        errorMessage = nil
        state = .signedOut
    }

    // MARK: Profile

    /// Saves the chosen username. Returns an error message to show, or nil on success.
    func setUsername(_ raw: String) async -> String? {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await supabase.rpc("set_username", params: ["p_username": raw]).execute()
            await loadProfile()
            return nil
        } catch {
            return Self.describe(error)
        }
    }

    func setPriceFormat(_ format: PriceFormat) async {
        guard let id = profile?.id else { return }
        do {
            _ = try await supabase.from("profiles")
                .update(["price_format": format.rawValue])
                .eq("id", value: id)
                .execute()
            profile?.priceFormat = format
        } catch {
            errorMessage = "Couldn't save that setting: \(Self.describe(error))"
        }
    }

    private func loadProfile() async {
        do {
            let userID = try await supabase.auth.session.user.id
            let rows: [Profile] = try await supabase.from("profiles")
                .select()
                .eq("id", value: userID)
                .execute()
                .value
            profile = rows.first
            state = (rows.first?.username == nil) ? .needsUsername : .ready
        } catch {
            errorMessage = "Couldn't load your profile: \(Self.describe(error))"
            state = .signedOut
        }
    }

    // MARK: Error text

    private static func describe(_ error: Error) -> String {
        let raw = (error as? PostgrestError)?.message ?? error.localizedDescription
        if raw.contains("username_taken") { return "That username is already taken." }
        if raw.contains("username_invalid") { return "Use 3–20 letters, numbers, or underscores." }
        if raw.contains("username_reserved") { return "That username isn't available." }
        if raw.contains("account_disabled") { return "This account has been disabled." }
        return raw
    }
}
