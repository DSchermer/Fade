import SwiftUI

/// Full statement that coins are play money, problem-gambling resources, and the legal pages.
struct LegalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("About & help").font(.fadeScreenTitle).foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(FadeButtonStyle(kind: .quiet, height: 44, fullWidth: false))
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        CoinIcon(size: 28)
                        Text("Fade coins are play money")
                            .font(.fadeHeadline.weight(.heavy))
                            .foregroundStyle(Theme.text)
                    }
                    Text("Coins are free. They can't be bought, cashed out, or exchanged for anything of value, and there are no prizes.")
                        .font(.fadeBody)
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Sports results come from public prediction-market data. Fade never accepts or pays out real money.")
                        .font(.fadeBody)
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fadeCard()

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Need help?")
                    VStack(spacing: 0) {
                        Text("Even play-money betting can be hard to put down for some people. If gambling is causing you stress, free confidential help is available.")
                            .font(.fadeBody)
                            .foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                        if let url = URL(string: "https://www.ncpgambling.org/help-treatment/") {
                            Link(destination: url) { linkRow("National Council on Problem Gambling", icon: "arrow.up.right", tint: Theme.text, iconTint: Theme.text3) }
                                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                        }
                        if let url = URL(string: "tel:18004262537") {
                            Link(destination: url) { linkRow("Call 1-800-GAMBLER", icon: "phone", tint: Theme.accent) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .fadeCardBackground()
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Fade")
                    VStack(spacing: 0) {
                        if let url = URL(string: AppConfig.termsURL) {
                            Link(destination: url) { linkRow("Terms of use", icon: "arrow.up.right", tint: Theme.text, iconTint: Theme.text3) }
                                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                        }
                        if let url = URL(string: AppConfig.privacyURL) {
                            Link(destination: url) { linkRow("Privacy policy", icon: "arrow.up.right", tint: Theme.text, iconTint: Theme.text3) }
                                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                        }
                        if let url = URL(string: AppConfig.supportURL) {
                            Link(destination: url) { linkRow("Help & support", icon: "arrow.up.right", tint: Theme.text, iconTint: Theme.text3) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .fadeCardBackground()
                }

                Text("Fade · you must be 18 or older to play")
                    .font(.caption)
                    .foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .fadeSheet()
    }

    private func linkRow(_ title: String, icon: String, tint: Color, iconTint: Color? = nil) -> some View {
        HStack {
            Text(title).font(.fadeHeadline.weight(.semibold)).foregroundStyle(tint)
            Spacer()
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(iconTint ?? tint)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}
