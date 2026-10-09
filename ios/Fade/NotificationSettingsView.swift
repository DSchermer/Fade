import SwiftUI
import UIKit
import UserNotifications

/// Turn each kind of push notification on or off.
struct NotificationSettingsView: View {
    @State private var prefs: NotificationPrefs?
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                permissionCard

                if let prefs {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Tell me when")
                        VStack(spacing: 0) {
                            row("A new offer is posted in my group", \.newOffer, "new_offer", prefs.newOffer, divider: true)
                            row("Someone takes my offer", \.offerTaken, "offer_taken", prefs.offerTaken, divider: true)
                            row("My bet is settled", \.betSettled, "bet_settled", prefs.betSettled, divider: true)
                            row("A vote is called", \.voteCalled, "vote_called", prefs.voteCalled, divider: true)
                            row("A vote passes or fails", \.voteResult, "vote_result", prefs.voteResult, divider: false)
                        }
                        .padding(.horizontal, 16)
                        .fadeCardBackground()
                        Text("Notifications tell you about activity in your groups. They never contain real-money information: Fade coins have no cash value.")
                            .font(.caption)
                            .foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
                if let errorMessage { ErrorLine(errorMessage) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .fadeScreen()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            await refreshStatus()
            prefs = try? await supabase.rpc("my_notification_prefs").execute().value
        }
    }

    @ViewBuilder private var permissionCard: some View {
        switch status {
        case .authorized, .provisional, .ephemeral:
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.win)
                Text("Notifications are allowed on this iPhone")
                    .font(.fadeBody.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Theme.win.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.win.opacity(0.3), lineWidth: 1))
        case .denied:
            VStack(alignment: .leading, spacing: 10) {
                Text("Notifications are turned off for Fade in the iPhone's Settings app. Open Settings → Fade → Notifications to allow them.")
                    .font(.fadeBody)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: url) {
                        Text("Open Settings")
                            .font(.fadeBody.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(14)
            .background(Theme.pending.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.pending.opacity(0.3), lineWidth: 1))
        default:
            Button("Allow notifications") {
                Task {
                    _ = await PushManager.shared.requestPermissionAndRegister()
                    await refreshStatus()
                }
            }
            .buttonStyle(.fadePrimary)
        }
    }

    private func row(_ title: String, _ path: WritableKeyPath<NotificationPrefs, Bool>, _ kind: String, _ value: Bool, divider: Bool) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.fadeHeadline)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Toggle(title, isOn: Binding(
                get: { value },
                set: { newValue in
                    prefs?[keyPath: path] = newValue
                    Task { await save(kind, newValue) }
                }
            ))
            .labelsHidden()
            .tint(Theme.win)
        }
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) {
            if divider { Rectangle().fill(Theme.line).frame(height: 1) }
        }
    }

    private struct Params: Encodable {
        let kind: String
        let enabled: Bool

        enum CodingKeys: String, CodingKey {
            case kind = "p_kind"
            case enabled = "p_enabled"
        }
    }

    private func save(_ kind: String, _ enabled: Bool) async {
        do {
            _ = try await supabase.rpc("set_notification_pref", params: Params(kind: kind, enabled: enabled)).execute()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't save that: \(Session.describe(error))"
        }
    }

    private func refreshStatus() async {
        status = await PushManager.shared.authorizationStatus()
    }
}
