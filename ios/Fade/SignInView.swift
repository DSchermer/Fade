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
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 8) {
                Text("Fade")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                Text("Bet your friends. Play money only.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if !AppConfig.isConfigured {
                Text("Backend not configured yet — see SETUP.md (AppConfig.swift).")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            if let message = session.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            SignInWithAppleButton(.signIn, onRequest: { request in
                let nonce = Nonce.random()
                rawNonce = nonce
                request.requestedScopes = []          // we don't need the name or email
                request.nonce = Nonce.sha256(nonce)
            }, onCompletion: { result in
                handle(result)
            })
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .disabled(session.isBusy || !AppConfig.isConfigured)

            #if DEBUG
            debugLogin
            #endif

            Text(agreement)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .tint(.secondary)

            NoMoneyNotice()
            Button("About Fade coins & help resources") { showLegal = true }
                .font(.footnote)
        }
        .padding()
        .sheet(isPresented: $showLegal) { LegalView() }
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
            Text("Debug only — test accounts").font(.caption).foregroundStyle(.secondary)
            TextField("test email", text: $debugEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            SecureField("password (6+ characters)", text: $debugPassword)
                .textFieldStyle(.roundedBorder)
            Button("Sign in / create test account") {
                Task { await session.debugEmailSignIn(email: debugEmail, password: debugPassword) }
            }
            .buttonStyle(.bordered)
            .disabled(debugEmail.isEmpty || debugPassword.count < 6 || session.isBusy || !AppConfig.isConfigured)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.6)))
    }
    #endif
}
