import SwiftUI

/// People you've blocked or muted, with a way to undo it.
struct BlockedUsersView: View {
    @Environment(FeedStore.self) private var store

    @State private var rows: [BlockedUser] = []
    @State private var loaded = false

    private var blocked: [BlockedUser] { rows.filter { $0.kind == "blocked" } }
    private var muted: [BlockedUser] { rows.filter { $0.kind == "muted" } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loaded && rows.isEmpty {
                    EmptyStateCard(
                        systemImage: "person.crop.circle.badge.checkmark",
                        title: "No one blocked or muted",
                        message: "People you block or mute from a comment or a member list show up here."
                    )
                }
                if !blocked.isEmpty { section("Blocked · \(blocked.count)", blocked) }
                if !muted.isEmpty { section("Muted · \(muted.count)", muted) }

                VStack(alignment: .leading, spacing: 10) {
                    explainer("Block", "Two-way. You won't see each other's comments or posts, and you can't be friends.")
                    Rectangle().fill(Theme.line).frame(height: 1)
                    explainer("Mute", "One-way. You stop seeing their comments. They aren't told.")
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Text("Bets in a shared group still work either way. To avoid someone's offers entirely, leave the group.")
                        .font(.caption)
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fadeCard(padding: 14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .fadeScreen()
        .navigationTitle("Blocked & muted")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func section(_ title: String, _ people: [BlockedUser]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            VStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 12) {
                        Avatar(name: row.username ?? "?", size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("@\(row.username ?? "deleted user")")
                                .font(.fadeHeadline.weight(.semibold))
                                .foregroundStyle(row.username == nil ? Theme.text2 : Theme.text)
                            Text(row.kind == "blocked" ? "Blocked" : "Muted")
                                .font(.caption)
                                .foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        Button(row.kind == "blocked" ? "Unblock" : "Unmute") {
                            Task {
                                _ = row.kind == "blocked" ? await store.unblock(userID: row.userId) : await store.unmute(userID: row.userId)
                                await reload()
                            }
                        }
                        .buttonStyle(.fadeSecondaryCompact)
                    }
                    .frame(minHeight: 68)
                    .overlay(alignment: .bottom) {
                        if index < people.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .fadeCardBackground()
        }
    }

    private func explainer(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title).font(.fadeBody.weight(.bold)).foregroundStyle(Theme.text).frame(width: 52, alignment: .leading)
            Text(text).font(.fadeCaption).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reload() async {
        rows = await store.blockedAndMuted()
        loaded = true
    }
}
