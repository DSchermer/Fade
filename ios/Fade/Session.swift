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
    /// An invite code from a link like fade://join/ABCD1234, waiting to be used once you're signed in.
    var pendingJoinCode: String?

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

    // MARK: Invite links

    /// Understands fade://join/CODE (works once the URL scheme is switched on — see SETUP/TESTING notes).
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "fade", url.host?.lowercased() == "join" else { return }
        let code = url.lastPathComponent.trimmingCharacters(in: .whitespaces).uppercased()
        if code.count >= 4, code.count <= 16, code.allSatisfy({ $0.isLetter || $0.isNumber }) {
            pendingJoinCode = code
        }
    }

    // MARK: Signing in and out

    func signInWithApple(idToken: String, nonce: String, authorizationCode: String? = nil) async {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            _ = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            if AppConfig.appleRevocationEnabled, let authorizationCode {
                await linkAppleAccount(code: authorizationCode)
            }
            await loadProfile()
        } catch {
            errorMessage = "Sign in failed: \(Self.describe(error))"
            state = .signedOut
        }
    }

    /// Gives Apple's one-time code to the server so it can disconnect this app from the person's Apple ID if they ever delete their account.
    private func linkAppleAccount(code: String) async {
        do {
            try await supabase.functions.invoke("apple-link", options: FunctionInvokeOptions(body: ["authorizationCode": code]))
        } catch {
            // Not fatal for signing in; deleting the account will tell you if this matters.
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

    /// Deletes the account on the server, then signs out here. Returns an error message to show, or nil on success.
    func deleteAccount() async -> String? {
        do {
            if AppConfig.appleRevocationEnabled {
                // Tells Apple to disconnect Fade from this Apple ID, then runs the normal deletion on the server.
                try await supabase.functions.invoke("apple-delete-account")
            } else {
                _ = try await supabase.rpc("delete_my_account").execute()
            }
        } catch {
            return Self.describe(error)
        }
        // The sign-in account no longer exists on the server, so signing out may complain; the local login is cleared either way.
        try? await supabase.auth.signOut(scope: .local)
        profile = nil
        errorMessage = nil
        state = .signedOut
        return nil
    }

    func signOut() async {
        await PushManager.shared.unregisterCurrentToken()    // while still signed in, so the phone stops getting this account's pushes
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

    /// Re-reads your profile without touching the sign-in state (e.g. to update the win-loss record).
    func refreshProfile() async {
        guard let id = profile?.id else { return }
        let rows: [Profile]? = try? await supabase.from("profiles")
            .select()
            .eq("id", value: id)
            .execute()
            .value
        if let fresh = rows?.first { profile = fresh }
    }

    private func loadProfile() async {
        do {
            let userID = try await supabase.auth.session.user.id
            let rows: [Profile] = try await supabase.from("profiles")
                .select()
                .eq("id", value: userID)
                .execute()
                .value
            if rows.first?.deletedAt != nil {          // a leftover login for an account that was deleted
                try? await supabase.auth.signOut(scope: .local)
                profile = nil
                state = .signedOut
                return
            }
            profile = rows.first
            state = (rows.first?.username == nil) ? .needsUsername : .ready
        } catch {
            errorMessage = "Couldn't load your profile: \(Self.describe(error))"
            state = .signedOut
        }
    }

    // MARK: Error text

    static func describe(_ error: Error) -> String {
        let raw = (error as? PostgrestError)?.message ?? error.localizedDescription
        let known: [(String, String)] = [
            ("username_taken", "That username is already taken."),
            ("username_invalid", "Use 3–20 letters, numbers, or underscores."),
            ("username_reserved", "That username isn't available."),
            ("account_disabled", "This account has been disabled."),
            ("profile_required", "Pick a username first."),
            ("group_not_found", "No group found with that code."),
            ("invalid_group_name", "Group names must be 1–60 characters."),
            ("invalid_starting_balance", "Starting balance must be between 1 and 1,000,000 coins."),
            ("invalid_buyback_amount", "Buyback amount must be between 1 and 1,000,000 coins."),
            ("invalid_buybacks_per_week", "Buybacks per week must be between 1 and 50."),
            ("invalid_buyback_policy", "Pick a buyback policy."),
            ("not_signed_in", "You're signed out. Please sign in again."),
            ("insufficient_balance", "You don't have enough available coins for that."),
            ("market_not_open", "This game has started or betting on it is closed."),
            ("market_not_found", "That market isn't available."),
            ("market_started", "The game has started, so this can't be changed. Unfilled shares cancel automatically."),
            ("invalid_outcome", "Pick a side."),
            ("invalid_price", "Price must be between 1¢ and 99¢."),
            ("invalid_shares", "Enter a whole number of shares, 1 or more."),
            ("not_enough_shares", "Not enough shares left — someone else may have just taken some."),
            ("offer_not_open", "This offer is no longer open."),
            ("offer_not_found", "That offer isn't available."),
            ("cannot_take_own_offer", "You can't take your own offer."),
            ("not_offer_maker", "Only the person who made an offer can cancel it."),
            ("not_a_member", "You're not a member of that group."),
            ("owner_must_transfer", "You own this group. Make another member the owner first, then you can leave."),
            ("has_unsettled_bets", "You still have unsettled bets in this group. You can leave once they're settled."),
            ("not_group_owner", "Only the group's owner can do that."),
            ("invalid_transfer", "Pick another member to hand ownership to."),
            ("target_not_member", "That person isn't an active member of this group."),
            ("buyback_requires_vote", "This group uses buyback votes (coming in a later update)."),
            ("buyback_limit_reached", "You've used this week's buybacks."),
            ("user_not_found", "No one with that username — or you can't add them."),
            ("request_pending", "You already sent them a request."),
            ("already_friends", "You're already friends."),
            ("too_many_requests", "You have too many requests waiting. Cancel a few first."),
            ("request_not_found", "That request isn't there any more."),
            ("invalid_token", "That notification setting couldn't be saved."),
            ("invalid_pref", "That notification setting couldn't be saved."),
            ("content_not_allowed", "That text isn't allowed in Fade. Please rephrase it."),
            ("invalid_comment", "Comments must be 1–500 characters."),
            ("slow_down", "You're commenting too fast. Wait a minute and try again."),
            ("item_not_found", "That post isn't available any more."),
            ("invalid_emoji", "That reaction isn't available."),
            ("invalid_report", "That can't be reported."),
            ("report_target_not_found", "That can't be reported."),
            ("invalid_target", "That person can't be selected."),
            ("vote_already_open", "A vote like that is already open — go vote on it."),
            ("vote_closed", "That vote has closed."),
            ("vote_not_found", "That vote isn't available."),
            ("invalid_vote_kind", "Pick a kind of vote."),
            ("invalid_ballot", "Pick yes or no."),
            ("buyback_vote_not_allowed", "This group doesn't use buyback votes."),
            ("not_busted", "You can only buy back in when you have no coins left (including coins in bets and offers)."),
        ]
        for (code, message) in known where raw.contains(code) { return message }
        return raw
    }
}
