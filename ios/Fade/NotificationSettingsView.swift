import SwiftUI
import UserNotifications

struct NotificationPrefs: Decodable {
    var newOffer: Bool
    var offerTaken: Bool
    var betSettled: Bool
    var voteCalled: Bool
    var voteResult: Bool

    enum CodingKeys: String, CodingKey {
        case newOffer = "new_offer"
        case offerTaken = "offer_taken"
        case betSettled = "bet_settled"
        case voteCalled = "vote_called"
        case voteResult = "vote_result"
    }
}

/// Turn each kind of push notification on or off.
struct NotificationSettingsView: View {
    @State private var prefs: NotificationPrefs?
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    Label("Notifications are allowed on this iPhone", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .denied:
                    Text("Notifications are turned off for Fade in the iPhone's Settings app. Open Settings → Fade → Notifications to allow them.")
                        .foregroundStyle(.orange)
                default:
                    Button("Allow notifications") { Task { _ = await PushManager.shared.requestPermissionAndRegister(); await refreshStatus() } }
                }
            } footer: {
                Text("Notifications tell you about activity in your groups. They never contain real-money information — Fade coins have no cash value.")
            }

            if let prefs {
                Section("Tell me when…") {
                    toggle("A new offer is posted in my group", \.newOffer, "new_offer", prefs.newOffer)
                    toggle("Someone takes my offer", \.offerTaken, "offer_taken", prefs.offerTaken)
                    toggle("My bet is settled", \.betSettled, "bet_settled", prefs.betSettled)
                    toggle("A vote is called", \.voteCalled, "vote_called", prefs.voteCalled)
                    toggle("A vote passes or fails", \.voteResult, "vote_result", prefs.voteResult)
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshStatus()
            prefs = try? await supabase.rpc("my_notification_prefs").execute().value
        }
    }

    private func toggle(_ title: String, _ path: WritableKeyPath<NotificationPrefs, Bool>, _ kind: String, _ value: Bool) -> some View {
        Toggle(title, isOn: Binding(
            get: { value },
            set: { newValue in
                prefs?[keyPath: path] = newValue
                Task {
                    struct Params: Encodable {
                        let kind: String
                        let enabled: Bool
                        enum CodingKeys: String, CodingKey {
                            case kind = "p_kind"
                            case enabled = "p_enabled"
                        }
                    }
                    do {
                        _ = try await supabase.rpc("set_notification_pref", params: Params(kind: kind, enabled: newValue)).execute()
                        errorMessage = nil
                    } catch {
                        errorMessage = "Couldn't save that: \(Session.describe(error))"
                    }
                }
            }
        ))
    }

    private func refreshStatus() async {
        status = await PushManager.shared.authorizationStatus()
    }
}
