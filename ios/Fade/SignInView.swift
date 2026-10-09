import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(Session.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var showLegal = false
    @State private var rawNonce = ""

    #if DEBUG
    @State private var debugEmail = ""
    @State private var debugPassword = ""
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 10) {
                (Text("fade").font(.system(size: 84, weight: .heavy)).tracking(-3)
                    + Text(".").font(.system(size: 84, weight: .heavy)).foregroundColor(Theme.accent))
                    .accessibilityLabel("Fade")
                    .accessibilityAddTraits(.isHeader)
                Text("Take the other side of your friends' picks.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                step(1, "Post your own odds on real games")
                step(2, "Friends take the other side of any part of it")
                step(3, "Climb your group's leaderboard")
            }
            .padding(.top, 28)

            Spacer(minLength: 24)

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    CoinIcon(size: 22)
                    Text("Fade coins are free play money. They have no cash value and can't be bought, sold or redeemed.")
                        .font(.fadeCaption)
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))

                if !AppConfig.isConfigured {
                    Text("Backend not configured yet. See SETUP.md (AppConfig.swift).")
                        .font(.fadeCaption)
                        .foregroundStyle(Theme.pending)
                        .multilineTextAlignment(.center)
                }

                if let message = session.errorMessage { ErrorLine(message) }

                SignInWithAppleButton(.signIn, onRequest: { request in
                    let nonce = Nonce.random()
                    rawNonce = nonce
                    request.requestedScopes = []          // we don't need the name or email
                    request.nonce = Nonce.sha256(nonce)
                }, onCompletion: { result in
                    handle(result)
                })
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(session.isBusy || !AppConfig.isConfigured)

                #if DEBUG
                debugLogin
                #endif

                Text(agreement)
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
                    .tint(Theme.accent)

                Button("About coins and help resources") { showLegal = true }
                    .font(.fadeCaption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fadeScreen()
        .sheet(isPresented: $showLegal) { LegalView() }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.fadeBody.weight(.bold))
                .foregroundStyle(Theme.text2)
                .frame(width: 36, height: 36)
                .background(Theme.raised, in: Circle())
            Text(text)
                .font(.fadeHeadline)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "By continuing you agree to the Terms of Use and Privacy Policy, and confirm you are 18 or older."
    private var agreement: AttributedString {
        let text = "By continuing you confirm you are 18 or older and agree to the [Terms of Use](\(AppConfig.termsURL)) and [Privacy Policy](\(AppConfig.privacyURL))."
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                session.errorMessage = "Apple didn't return a sign-in token. Please try again."
                return
            }
            let nonce = rawNonce
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            Task { await session.signInWithApple(idToken: token, nonce: nonce, authorizationCode: code) }
        case .failure(let error):
            // Tapping "Cancel" is not an error worth showing.
            if (error as? ASAuthorizationError)?.code != .canceled {
                session.errorMessage = "Apple sign in failed: \(error.localizedDescription)"
            }
        }
    }

    #if DEBUG
    private var debugLogin: some View {
        VStack(spacing: 8) {
            Text("Debug only — test accounts").font(.caption).foregroundStyle(Theme.pending)
            TextField("test email", text: $debugEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            SecureField("password (6+ characters)", text: $debugPassword)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button("Sign in / create test account") {
                Task { await session.debugEmailSignIn(email: debugEmail, password: debugPassword) }
            }
            .buttonStyle(.fadeQuiet)
            .disabled(debugEmail.isEmpty || debugPassword.count < 6 || session.isBusy || !AppConfig.isConfigured)
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.pending.opacity(0.6), lineWidth: 1))
    }
    #endif
}
