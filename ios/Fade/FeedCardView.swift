import SwiftUI

/// One card in the feed: who did what, the bet itself, and reactions. Used in the feed list and at the top of a post.
struct FeedCardView: View {
    let item: FeedItem
    let format: PriceFormat
    let myID: UUID?
    let reactions: [String: Int]
    let myReactions: Set<String>
    /// For "vote called" cards: the live vote, so the card can show the Yes / No buttons.
    var openVote: VoteRow?
    var showCommentPreview = true
    /// false on a post's own screen, where reactions and comments have their own place: only the "Fade this offer" button stays.
    var showReactions = true
    var onOpen: () -> Void = {}
    var onReact: (String) -> Void = { _ in }
    var onFade: () -> Void = {}
    var onVote: (Bool) -> Void = { _ in }

    var body: some View {
        if item.kind == "vote_called", let vote = openVote {
            voteCard(vote)
        } else {
            card
        }
    }

    // MARK: Regular card

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            if showCommentPreview, let comment = item.latestComment {
                commentPreview(comment)
            }
            if showsFooter { footer }
        }
        .fadeCard()
    }

    private var header: some View {
        HStack(spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 1) {
                headline
                    .font(.fadeBody)
                    .lineLimit(2)
                Text(subheadline)
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            if let badge = badge { StatusPill(text: badge.text, tone: badge.tone) }
        }
    }

    private var badge: (text: String, tone: FeedTone)? {
        if item.kind == "vote_called" { return ("Ended", .neutral) }
        return item.statusBadge()
    }

    @ViewBuilder private var avatar: some View {
        if let name = item.header.name {
            Avatar(name: name, size: 36)
        } else {
            Image(systemName: item.kind == "vote_result" ? "hand.raised" : "arrow.uturn.backward")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .frame(width: 36, height: 36)
                .background(Theme.raised, in: Circle())
                .accessibilityHidden(true)
        }
    }

    private var headline: Text {
        let h = item.header
        if let name = h.name {
            return Text(name).fontWeight(.semibold).foregroundColor(Theme.text)
                + Text(" " + h.verb).foregroundColor(Theme.text2)
        }
        return Text(h.verb).foregroundColor(Theme.text2)
    }

    private var subheadline: String {
        let ago = RelativeTime.short(from: item.createdAt)
        guard let group = item.groupName else { return ago }
        return "\(group) · \(ago)"
    }

    // MARK: Kind-specific content

    @ViewBuilder private var content: some View {
        switch item.kind {
        case "offer_posted": offerContent
        case "offer_taken": takenContent
        case "bet_settled": settledContent
        case "buyback": buybackContent
        case "vote_called", "vote_result": voteTextContent
        default: titleBlock
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let line = item.contextLine() {
                Text(line)
                    .font(.fadeCaption)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var offerContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBlock
            if let cents = item.payload.priceCents, (1...99).contains(cents) {
                let theirs = Odds.parts(cents: cents, format: format)
                let yours = Odds.parts(cents: 100 - cents, format: format)
                HStack(spacing: 8) {
                    StatTile(label: "Their price", value: theirs.main, detail: theirs.alt)
                    StatTile(label: "Open", value: "\(item.offerSharesOpen ?? item.payload.shares ?? 0)", detail: "shares")
                    StatTile(label: "Fade at", value: yours.main, detail: yours.alt)
                }
            }
        }
    }

    private var takenContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBlock
            if let cents = item.payload.priceCents, (1...99).contains(cents) {
                let price = Odds.parts(cents: 100 - cents, format: format)
                HStack(spacing: 8) {
                    StatTile(label: "Price", value: price.main, detail: price.alt)
                    StatTile(label: "Shares", value: "\(item.payload.shares ?? 0)")
                    StatTile(label: "To win", coins: item.payload.makerStake ?? 0)
                }
            }
        }
    }

    private var settledContent: some View {
        HStack(alignment: .bottom, spacing: 12) {
            titleBlock
            if item.payload.result == "void" {
                Text("Stakes refunded")
                    .font(.fadeBody.weight(.semibold))
                    .foregroundStyle(Theme.text2)
            } else {
                CoinAmount(centicoins: item.payload.gain ?? 0, signed: true, font: .title2.weight(.heavy), iconSize: 20)
            }
        }
    }

    private var buybackContent: some View {
        HStack(alignment: .center, spacing: 12) {
            titleBlock
            CoinAmount(centicoins: item.payload.amount ?? 0, font: .title3.weight(.bold), iconSize: 18)
        }
    }

    private var voteTextContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleBlock
            if item.kind == "vote_result" {
                Text("\(item.payload.yes ?? 0) yes · \(item.payload.no ?? 0) no")
                    .font(.fadeCaption)
                    .foregroundStyle(Theme.text2)
            }
        }
    }

    private func commentPreview(_ comment: LatestComment) -> some View {
        let name = comment.username ?? "deleted user"
        return HStack(spacing: 8) {
            Avatar(name: name, size: 22)
            (Text(name).fontWeight(.semibold).foregroundColor(Theme.text) + Text(" " + comment.body).foregroundColor(Theme.text2))
                .font(.fadeBody)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    }

    // MARK: Footer

    private var showsFooter: Bool {
        guard !["buyback", "vote_result"].contains(item.kind) else { return false }
        return showReactions || canFade
    }

    private struct ReactionCount: Identifiable {
        let emoji: String
        let count: Int
        var id: String { emoji }
    }

    /// The three most-used reactions on the card, most popular first.
    private var topReactions: [ReactionCount] {
        let counted = reactions.filter { $0.value > 0 }.map { ReactionCount(emoji: $0.key, count: $0.value) }
        let ranked = counted.sorted { a, b in a.count != b.count ? a.count > b.count : a.emoji < b.emoji }
        return Array(ranked.prefix(3))
    }

    private var canFade: Bool {
        item.canBeFaded() && item.actorId != myID
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if showReactions { reactionChips }
            Spacer(minLength: 4)
            if canFade {
                Button("Fade this offer", action: onFade)
                    .buttonStyle(.fadePrimaryCompact)
            }
        }
    }

    @ViewBuilder private var reactionChips: some View {
        HStack(spacing: 6) {
            ForEach(topReactions) { reaction in
                reactionChip(reaction.emoji, reaction.count)
            }
            if topReactions.isEmpty {
                Button(action: onOpen) {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 40, height: 32)
                        .background(Theme.raised, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a reaction")
            }
            if item.commentCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 13, weight: .medium))
                    Text("\(item.commentCount)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(Theme.raised, in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.commentCount) comments")
            }
        }
    }

    private func reactionChip(_ emoji: String, _ count: Int) -> some View {
        let mine = myReactions.contains(emoji)
        return Button {
            onReact(emoji)
        } label: {
            HStack(spacing: 5) {
                Text(emoji).font(.footnote)
                Text("\(count)")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(mine ? Theme.text : Theme.text2)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(mine ? Theme.accent.opacity(0.18) : Theme.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(mine ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(emoji) \(count)")
        .accessibilityAddTraits(mine ? .isSelected : [])
    }

    // MARK: Vote card

    private func voteCard(_ vote: VoteRow) -> some View {
        let caller = vote.calledByUsername ?? "deleted user"
        let subject = vote.subjectUsername ?? "deleted user"
        let title = vote.kind == "reset" ? "\(caller) wants to reset the group" : "\(subject) wants a buyback"
        let detail = vote.kind == "reset"
            ? "If it passes, unsettled bets are voided and refunded and everyone restarts at the starting balance."
            : "If it passes, \(subject) gets the group's buyback amount."
        let group = item.groupName ?? "Your group"
        return VStack(alignment: .leading, spacing: 12) {
            Text("Vote open · \(group) · closes in \(RelativeTime.remaining(until: vote.closesAt))".uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(Theme.pending)
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(.fadeHeadline)
                .foregroundStyle(Theme.text)
            Text(detail)
                .font(.fadeBody)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { onVote(true) } label: { Text("Yes · \(vote.yesCount)") }
                    .buttonStyle(FadeButtonStyle(kind: vote.myVote == true ? .primary : .quiet, height: 44))
                Button { onVote(false) } label: { Text("No · \(vote.noCount)") }
                    .buttonStyle(FadeButtonStyle(kind: vote.myVote == false ? .primary : .quiet, height: 44))
            }
        }
        .fadeCard(fill: Theme.pending.opacity(0.09), stroke: Theme.pending.opacity(0.32))
    }
}
