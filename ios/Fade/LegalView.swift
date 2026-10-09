import SwiftUI

/// The one-line reminder shown on the main screens.
struct NoMoneyNotice: View {
    var body: some View {
        Text("Fade coins are free play money. They have no cash value and can't be bought, sold, or redeemed.")
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }
}

/// Full statement + problem-gambling resources.
struct LegalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("About Fade coins") {
                    Text("Fade is a free game for friends. Coins are play money only. They can't be purchased, cashed out, or exchanged for anything of value, and there are no prizes.")
                    Text("Sports results come from public prediction-market data. Fade does not accept or pay out real money.")
                }
                Section("Need help?") {
                    Text("Even play-money betting can be hard to put down for some people. If gambling is causing you stress, free confidential help is available.")
                    if let url = URL(string: "https://www.ncpgambling.org/help-treatment/") {
                        Link("National Council on Problem Gambling", destination: url)
                    }
                    if let url = URL(string: "tel:18004262537") {
                        Link("Call 1-800-GAMBLER", destination: url)
                    }
                }
                Section("Fade") {
                    if let url = URL(string: AppConfig.termsURL) { Link("Terms of use", destination: url) }
                    if let url = URL(string: AppConfig.privacyURL) { Link("Privacy policy", destination: url) }
                    if let url = URL(string: AppConfig.supportURL) { Link("Help & support", destination: url) }
                }
            }
            .navigationTitle("About & Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
