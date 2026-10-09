import SwiftUI

/// The first tab: activity from every group you're in, with chips to focus on one group.
struct FeedHomeView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(AppRouter.self) private var router

    @State private var selectedGroup: UUID?

    /// The chosen group, unless you've left it since.
    private var activeGroup: UUID? {
        guard let selectedGroup, groups.memberships.contains(where: { $0.id == selectedGroup }) else { return nil }
        return selectedGroup
    }

    var body: some View {
        NavigationStack {
            FeedStream(groupID: activeGroup) {
                VStack(alignment: .leading, spacing: 12) {
                    titleRow
                    if !groups.memberships.isEmpty { chips }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fadeTabBar()
        }
    }

    private var titleRow: some View {
        HStack {
            (Text("fade").font(.system(size: 32, weight: .heavy)).tracking(-1)
                + Text(".").font(.system(size: 32, weight: .heavy)).foregroundColor(Theme.accent))
                .accessibilityLabel("Fade")
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                router.tab = .me
            } label: {
                Text(AvatarPalette.initials(session.profile?.username ?? "", count: 2))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Theme.raised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Me")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All groups", isSelected: activeGroup == nil) { selectedGroup = nil }
                ForEach(groups.memberships) { membership in
                    FilterChip(title: membership.group.name, isSelected: activeGroup == membership.id) {
                        selectedGroup = membership.id
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
