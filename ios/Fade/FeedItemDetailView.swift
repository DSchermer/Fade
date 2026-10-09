import SwiftUI

/// One feed post with its reactions and comments. Touch and hold a comment to report it, mute, or block its author.
struct FeedItemDetailView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(FeedStore.self) private var store
    @Environment(OfferStore.self) private var offerStore

    let item: FeedItem
    var openVote: VoteRow?
    let onChange: () async -> Void

    @State private var comments: [CommentRow] = []
    @State private var reactions: [String: Int] = [:]
    @State private var myReactions: Set<String> = []
    @State private var draft = ""
    @State private var errorMessage: String?
    @State private var reportTarget: ReportTarget?
    @State private var confirmBlock: CommentRow?
    @State private var offerToTake: OfferRow?
    @State private var isSending = false
    @State private var seeded = false

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }
    private var me: UUID? { session.profile?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FeedCardView(
                    item: item,
                    format: format,
                    myID: me,
                    reactions: reactions,
                    myReactions: myReactions,
                    openVote: openVote,
                    showCommentPreview: false,
                    showReactions: false,
                    onFade: { Task { await fade() } },
                    onVote: { yes in
                        if let openVote { Task { await cast(openVote, yes: yes) } }
                    }
                )
                reactionPicker
                commentsSection
                if let errorMessage { ErrorLine(errorMessage) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .fadeScreen()
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let actor = item.actorId, actor != me {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Report this post", systemImage: "flag") {
                            reportTarget = ReportTarget(
                                type: "feed_item", id: item.id, title: "this post",
                                userID: actor, userName: item.actorUsername
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .task {
            if !seeded {
                seeded = true
                reactions = item.reactions
                myReactions = Set(item.myReactions)
            }
            await reload()
        }
        .sheet(item: $reportTarget) { target in ReportView(target: target) }
        .sheet(item: $offerToTake) { offer in
            TakeOfferSheet(offer: offer) { await onChange() }
        }
        .confirmationDialog("Block \(confirmBlock?.displayName ?? "this person")?", isPresented: Binding(
            get: { confirmBlock != nil }, set: { if !$0 { confirmBlock = nil } }
        ), titleVisibility: .visible, presenting: confirmBlock) { comment in
            Button("Block", role: .destructive) { Task { await block(comment) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You won't see each other's comments or feed activity. You can unblock in Settings. To avoid someone's offers entirely, leave the group.")
        }
    }

    // MARK: Reactions

    private var reactionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(reactionEmoji, id: \.self) { emoji in
                    let count = reactions[emoji] ?? 0
                    let mine = myReactions.contains(emoji)
                    Button {
                        Task { await toggle(emoji) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(emoji).font(.body)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.footnote.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(mine ? Theme.text : Theme.text2)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(mine ? Theme.accent.opacity(0.18) : Theme.raised, in: Capsule())
                        .overlay(Capsule().strokeBorder(mine ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(count > 0 ? "\(emoji), \(count)" : emoji)
                    .accessibilityAddTraits(mine ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Comments · \(comments.count)")
            if comments.isEmpty {
                Text("No comments yet. Say something.")
                    .font(.fadeBody)
                    .foregroundStyle(Theme.text2)
            }
            ForEach(comments) { comment in
                commentRow(comment)
            }
            Text("Touch and hold a comment to report it, mute, or block its author. Comments with offensive language are rejected.")
                .font(.caption)
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func commentRow(_ comment: CommentRow) -> some View {
        let name = comment.username ?? "deleted user"
        return HStack(alignment: .top, spacing: 10) {
            Avatar(name: name, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                (Text(name).fontWeight(.semibold).foregroundColor(Theme.text)
                    + Text(" · " + RelativeTime.short(from: comment.createdAt)).foregroundColor(Theme.text2))
                    .font(.fadeCaption)
                Text(comment.body)
                    .font(.fadeBody)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if comment.userId == me {
                Button("Delete", systemImage: "trash", role: .destructive) { Task { await delete(comment) } }
            } else {
                Button("Report", systemImage: "flag") {
                    reportTarget = ReportTarget(
                        type: "comment", id: comment.id, title: "this comment",
                        userID: comment.userId, userName: comment.username
                    )
                }
                Button("Mute \(comment.displayName)", systemImage: "speaker.slash") { Task { await mute(comment) } }
                Button("Block \(comment.displayName)", systemImage: "hand.raised.slash", role: .destructive) { confirmBlock = comment }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Add a comment", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .font(.fadeBody)
                .foregroundStyle(Theme.text)
                .padding(.leading, 12)
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(canSend ? Theme.accent : Theme.raised, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.vertical, 6)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.bg)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    // MARK: Actions

    private func reload() async {
        comments = await store.comments(itemID: item.id)
    }

    private func toggle(_ emoji: String) async {
        errorMessage = await store.toggleReaction(itemID: item.id, emoji: emoji)
        guard errorMessage == nil else { return }
        if myReactions.contains(emoji) {
            myReactions.remove(emoji)
            reactions[emoji] = max(0, (reactions[emoji] ?? 1) - 1)
        } else {
            myReactions.insert(emoji)
            reactions[emoji, default: 0] += 1
        }
        await onChange()
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        errorMessage = await store.addComment(itemID: item.id, body: draft)
        if errorMessage == nil { draft = "" }
        await reload()
        await onChange()
    }

    private func delete(_ comment: CommentRow) async {
        errorMessage = await store.deleteComment(id: comment.id)
        await reload()
        await onChange()
    }

    private func mute(_ comment: CommentRow) async {
        errorMessage = await store.mute(userID: comment.userId)
        await reload()
    }

    private func block(_ comment: CommentRow) async {
        errorMessage = await store.block(userID: comment.userId)
        await reload()
        await onChange()
    }

    private func fade() async {
        guard let offerID = item.refId else { return }
        guard let offer = await offerStore.offer(id: offerID), offer.status == "open", offer.sharesOpen > 0, offer.gameStart > Date() else {
            errorMessage = "That offer isn't available any more."
            await onChange()
            return
        }
        errorMessage = nil
        offerToTake = offer
    }

    private func cast(_ vote: VoteRow, yes: Bool) async {
        guard let userID = me else { return }
        errorMessage = await groups.castVote(voteID: vote.id, yes: yes, userID: userID)
        await onChange()
    }
}
