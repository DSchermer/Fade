import SwiftUI
import UIKit

/// A small two-column table inside a sheet: label on the left, value on the right.
private struct SheetTable<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

private struct SheetRow<Value: View>: View {
    let title: String
    var detail: String?
    var showsDivider = true
    let value: Value

    init(_ title: String, detail: String? = nil, showsDivider: Bool = true, @ViewBuilder value: () -> Value) {
        self.title = title
        self.detail = detail
        self.showsDivider = showsDivider
        self.value = value()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.fadeBody.weight(.semibold)).foregroundStyle(Theme.text)
                if let detail { Text(detail).font(.caption).foregroundStyle(Theme.text2) }
            }
            Spacer(minLength: 8)
            value
        }
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(Theme.line).frame(height: 1) }
        }
    }
}

// MARK: - Invite

/// The group's invite code, with Copy and Share.
struct InviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let group: GroupInfo
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Invite friends").font(.fadeSectionTitle).foregroundStyle(Theme.text)
                    Spacer()
                    CircleIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                }
                Text("Anyone with this code can join \(group.name). They start with \(Coins.formatFixed(group.startingBalance)) coins.")
                    .font(.fadeBody)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(group.inviteCode)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    .accessibilityLabel("Invite code \(group.inviteCode.map { String($0) }.joined(separator: " "))")

                Button(copied ? "Copied" : "Copy code") {
                    UIPasteboard.general.string = group.inviteCode
                    copied = true
                }
                .buttonStyle(.fadeSecondaryLarge)

                ShareLink(item: "Join my Fade group “\(group.name)”! Open Fade → Groups → Join with a code → \(group.inviteCode)") {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.fadePrimaryLarge)

                Text("Invite links that open the app directly come later.")
                    .font(.caption)
                    .foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .fadeSheet()
    }
}

// MARK: - Buyback

/// Confirms a buyback: what you get, and that it doesn't count as winnings.
struct BuybackConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss

    let groupName: String
    let status: BuybackStatus
    /// My net profit in this group right now (a buyback leaves it where it is).
    let myNet: Int64
    let onConfirm: () async -> String?

    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    CoinIcon(size: 52)
                    Text("Buy back in?").font(.fadeSectionTitle).foregroundStyle(Theme.text)
                    Text("You'll get a fresh stack of coins in \(groupName).")
                        .font(.fadeBody)
                        .foregroundStyle(Theme.text2)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)

                SheetTable {
                    SheetRow("You receive") {
                        CoinAmount(centicoins: status.amount, signed: true, font: .title3.weight(.heavy), iconSize: 16)
                    }
                    SheetRow("Net profit", detail: "Buyback coins don't count as winnings", showsDivider: status.policy == "weekly") {
                        CoinAmount(centicoins: myNet, signed: true, font: .title3.weight(.heavy), iconSize: 16)
                    }
                    if status.policy == "weekly", let allowed = status.allowed {
                        SheetRow("Buybacks this week", showsDivider: false) {
                            Text("\(min(allowed, status.used + 1)) of \(allowed) used")
                                .font(.fadeBody.weight(.bold))
                                .foregroundStyle(Theme.text)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "eye").font(.system(size: 13, weight: .semibold))
                    Text("Everyone in \(groupName) can see this buyback in the feed.")
                }
                .font(.caption)
                .foregroundStyle(Theme.text2)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let errorMessage { ErrorLine(errorMessage) }

                VStack(spacing: 10) {
                    Button(isWorking ? "Buying back…" : "Buy back in for \(Coins.formatFixed(status.amount)) coins") {
                        Task { await confirm() }
                    }
                    .buttonStyle(.fadePrimaryLarge)
                    .disabled(isWorking)
                    Button("Not now") { dismiss() }
                        .buttonStyle(.fadeSecondaryLarge)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .fadeSheet()
    }

    private func confirm() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = await onConfirm()
        if errorMessage == nil { dismiss() }
    }
}

// MARK: - Leaving

/// Shows what leaving does before it happens.
struct LeaveGroupSheet: View {
    @Environment(\.dismiss) private var dismiss

    let groupName: String
    let openOffers: Int
    let coinsHeld: Int64
    let netProfit: Int64
    let onLeave: () async -> String?

    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Leave \(groupName)?").font(.fadeSectionTitle).foregroundStyle(Theme.text)
                    Text("Here's what happens to your stuff in this group.")
                        .font(.fadeBody)
                        .foregroundStyle(Theme.text2)
                }

                SheetTable {
                    SheetRow("Open offers", detail: "Cancelled and refunded first") {
                        Text("\(openOffers) offer\(openOffers == 1 ? "" : "s")")
                            .font(.fadeBody.weight(.bold))
                            .foregroundStyle(Theme.text)
                    }
                    SheetRow("Coins you hold here", detail: "Gone when you leave") {
                        CoinAmount(centicoins: coinsHeld, font: .title3.weight(.heavy), iconSize: 16, tint: Theme.loss)
                    }
                    SheetRow("Your net profit here", detail: "Kept in your lifetime score", showsDivider: false) {
                        CoinAmount(centicoins: netProfit, signed: true, font: .title3.weight(.heavy), iconSize: 16)
                    }
                }

                Text("If you rejoin later you start with 0 coins.")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)

                if let errorMessage { ErrorLine(errorMessage) }

                VStack(spacing: 10) {
                    Button(isWorking ? "Leaving…" : "Leave group") { Task { await leave() } }
                        .buttonStyle(.fadeDestructiveLarge)
                        .disabled(isWorking)
                    Button("Stay") { dismiss() }
                        .buttonStyle(.fadeSecondaryLarge)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .fadeSheet()
    }

    private func leave() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = await onLeave()
        if errorMessage == nil { dismiss() }
    }
}

/// You can't leave while bets are unsettled: lists them instead of failing afterwards.
struct LeaveBlockedSheet: View {
    @Environment(\.dismiss) private var dismiss

    let groupName: String
    let bets: [BetRow]
    let me: UUID
    let format: PriceFormat
    let onSeeBets: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You can't leave yet").font(.fadeSectionTitle).foregroundStyle(Theme.text)
                    Text("You have \(bets.count) bet\(bets.count == 1 ? "" : "s") in \(groupName) that \(bets.count == 1 ? "isn't" : "aren't") settled. You can leave once \(bets.count == 1 ? "it is" : "they are").")
                        .font(.fadeBody)
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 8) {
                    ForEach(bets) { bet in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(bet.mySide(me)).font(.fadeHeadline.weight(.bold)).foregroundStyle(Theme.text)
                                Spacer()
                                CoinAmount(centicoins: bet.myStake(me), font: .fadeBody.weight(.bold), iconSize: 14)
                            }
                            HStack(spacing: 8) {
                                if bet.isAwaitingResult() {
                                    StatusPill(text: "Pending", tone: .pending)
                                    Text(bet.statusText(me)).font(.fadeCaption).foregroundStyle(Theme.text2)
                                } else {
                                    StatusPill(text: "Upcoming", tone: .open)
                                    Text(GameTime.label(bet.gameStart)).font(.fadeCaption).foregroundStyle(Theme.text2)
                                }
                            }
                        }
                        .padding(12)
                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    }
                }

                Text("Your open offers are cancelled and refunded automatically when you leave. Only bets that someone has taken block you.")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)

                VStack(spacing: 10) {
                    Button("See my bets") {
                        dismiss()
                        onSeeBets()
                    }
                    .buttonStyle(.fadePrimaryLarge)
                    Button("Close") { dismiss() }
                        .buttonStyle(.fadeSecondaryLarge)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .fadeSheet()
    }
}

// MARK: - Ownership

/// Confirms handing the group to someone else.
struct HandOverSheet: View {
    @Environment(\.dismiss) private var dismiss

    let member: LeaderboardRow
    let onConfirm: () async -> String?

    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Avatar(name: member.username ?? "?", size: 56)
                    Text("Make \(member.displayName) the owner?")
                        .font(.fadeSectionTitle)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                    Text("You'll become an ordinary member. Only one person can own a group. After that you can leave if you want to.")
                        .font(.fadeBody)
                        .foregroundStyle(Theme.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)

                if let errorMessage { ErrorLine(errorMessage) }

                VStack(spacing: 10) {
                    Button(isWorking ? "Handing over…" : "Make owner") { Task { await confirm() } }
                        .buttonStyle(.fadePrimaryLarge)
                        .disabled(isWorking)
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.fadeSecondaryLarge)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .fadeSheet()
    }

    private func confirm() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = await onConfirm()
        if errorMessage == nil { dismiss() }
    }
}
