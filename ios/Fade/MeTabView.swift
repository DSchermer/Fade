import SwiftUI

/// The Me tab: your lifetime score, a peek at the friends leaderboard, and settings.
struct MeTabView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(FriendStore.self) private var friendStore

    @State private var score: MyScore?
    @State private var friendScores: [FriendScore] = []
    @State private var requests: [FriendRequest] = []
    @State private var showLegal = false
    @State private var showDelete = false
    @State private var formatOverride: PriceFormat?

    private var username: String { session.profile?.username ?? "" }
    private var format: PriceFormat { formatOverride ?? session.profile?.priceFormat ?? .cents }
    private var incoming: Int { requests.filter { $0.direction == "incoming" }.count }
    private var totalBuybacks: Int { groups.summaries.values.reduce(0) { $0 + $1.myBuybacks } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    profileRow
                    scoreCard
                    friendsSection
                    settingsSection
                    aboutSection
                    accountSection
                    NoMoneyNotice()
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                }
                .padding(.top, 6)
            }
            .refreshable { await reload() }
            .fadeScreen()
            .toolbar(.hidden, for: .navigationBar)
            .fadeTabBar()
            .task { await reload() }
            .sheet(isPresented: $showLegal) { LegalView() }
            .sheet(isPresented: $showDelete) { DeleteAccountView() }
        }
    }

    // MARK: Sections

    private var profileRow: some View {
        HStack(spacing: 14) {
            Avatar(name: username, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(username)
                    .font(.system(.title, design: .default).weight(.heavy))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("@\(username) · \(groups.memberships.count) group\(groups.memberships.count == 1 ? "" : "s")")
                    .font(.fadeBody)
                    .foregroundStyle(Theme.text2)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel("Lifetime score · all groups")
                CoinAmount(centicoins: score?.score ?? 0, signed: true, font: .system(size: 44, weight: .heavy), iconSize: 30)
            }
            HStack(spacing: 8) {
                StatTile(label: "Record", value: "\(score?.wins ?? session.profile?.lifetimeWins ?? 0)–\(score?.losses ?? session.profile?.lifetimeLosses ?? 0)")
                StatTile(label: "Groups", value: "\(groups.memberships.count)")
                StatTile(label: "Buybacks", value: "\(totalBuybacks)")
            }
        }
        .fadeCard(padding: 18)
        .padding(.horizontal, 16)
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Friends").font(.fadeSectionTitle).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if incoming > 0 {
                    NavigationLink {
                        FriendsView(initialTab: .requests)
                    } label: {
                        Text("\(incoming) request\(incoming == 1 ? "" : "s")")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 26)
                            .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink {
                    FriendsView(initialTab: .board)
                } label: {
                    Text("See all")
                        .font(.fadeBody.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            if friendScores.count <= 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add friends to see how you rank against them.")
                        .font(.fadeBody)
                        .foregroundStyle(Theme.text2)
                    NavigationLink {
                        FriendsView(initialTab: .add)
                    } label: {
                        Text("Add a friend")
                            .font(.fadeBody.weight(.bold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .fadeCard(padding: 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(friendScores.prefix(5).enumerated()), id: \.element.id) { index, row in
                        FriendScoreRow(rank: index + 1, row: row, compact: true)
                            .overlay(alignment: .bottom) {
                                if index < min(friendScores.count, 5) - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .fadeCardBackground()
            }
        }
        .padding(.horizontal, 16)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings").font(.fadeSectionTitle).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                HStack {
                    Text("Show prices as").font(.fadeHeadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    FadeSegmented(options: PriceFormat.allCases, title: { $0 == .cents ? "¢" : "American" }, selection: formatBinding)
                        .frame(width: 190)
                }
                .frame(minHeight: 60)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                navRow("Notifications", showsDivider: true) { NotificationSettingsView() }
                navRow("Blocked and muted people", showsDivider: false) { BlockedUsersView() }
            }
            .padding(.horizontal, 14)
            .fadeCardBackground()
            Text("Same bet either way: 60¢ is the same price as -150. You always see the exact price in cents before you confirm.")
                .font(.caption)
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            if let message = session.errorMessage { ErrorLine(message) }
        }
        .padding(.horizontal, 16)
    }

    private var aboutSection: some View {
        VStack(spacing: 0) {
            Button { showLegal = true } label: {
                rowLabel("About coins and help", systemImage: "chevron.right")
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            if let url = URL(string: AppConfig.termsURL) {
                Link(destination: url) { rowLabel("Terms of use", systemImage: "arrow.up.right") }
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            if let url = URL(string: AppConfig.privacyURL) {
                Link(destination: url) { rowLabel("Privacy policy", systemImage: "arrow.up.right") }
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            if let url = URL(string: AppConfig.supportURL) {
                Link(destination: url) { rowLabel("Help and support", systemImage: "arrow.up.right") }
            }
        }
        .padding(.horizontal, 14)
        .fadeCardBackground()
        .padding(.horizontal, 16)
    }

    private var accountSection: some View {
        VStack(spacing: 10) {
            Button("Sign out") {
                Task {
                    groups.clear()
                    await session.signOut()
                }
            }
            .buttonStyle(.fadeSecondary)
            Button("Delete my account…") { showDelete = true }
                .buttonStyle(.fadeDestructiveOutline)
            Text("Deleting permanently removes your account and personal information. Coins have no cash value and can't be recovered.")
                .font(.caption)
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Pieces

    private func navRow<Destination: View>(_ title: String, showsDivider: Bool, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            rowLabel(title, systemImage: "chevron.right")
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(Theme.line).frame(height: 1) }
        }
    }

    private func rowLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            Text(title).font(.fadeHeadline.weight(.semibold)).foregroundStyle(Theme.text)
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text3)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var formatBinding: Binding<PriceFormat> {
        Binding(
            get: { format },
            set: { newFormat in
                formatOverride = newFormat
                Task { await session.setPriceFormat(newFormat) }
            }
        )
    }

    private func reload() async {
        guard let userID = session.profile?.id else { return }
        await session.refreshProfile()
        score = await groups.myScore()
        await groups.loadSummaries(userID: userID)
        friendScores = await friendStore.scores()
        requests = await friendStore.requests()
    }
}

/// One person on a friends leaderboard.
struct FriendScoreRow: View {
    let rank: Int
    let row: FriendScore
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.fadeBody.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(rank == 1 ? Theme.pending : Theme.text2)
                .frame(width: 22)
            Avatar(name: row.username ?? "?", size: compact ? 34 : 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.isMe ? "you" : (row.username ?? "deleted user"))
                    .font(.fadeHeadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("Record \(row.wins)–\(row.losses)")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 4)
            CoinAmount(centicoins: row.score, signed: true, font: .fadeHeadline.weight(.heavy), iconSize: 14)
        }
        .frame(minHeight: compact ? 56 : 64)
        .padding(.horizontal, row.isMe ? 8 : 0)
        .background(row.isMe ? Theme.accent.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
