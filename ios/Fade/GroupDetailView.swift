import SwiftUI
import UIKit

struct GroupDetailView: View {
    @Environment(GroupStore.self) private var groups
    let membership: GroupMembership

    @State private var members: [GroupMember] = []
    @State private var copied = false

    private var group: GroupInfo { membership.group }

    var body: some View {
        List {
            Section("Your balance") {
                LabeledContent("Total", value: "\(Coins.format(membership.balance)) coins")
                LabeledContent("Available to bet", value: "\(Coins.format(membership.available)) coins")
            }

            Section {
                HStack {
                    Text(group.inviteCode)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                    Spacer()
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = group.inviteCode
                        copied = true
                    }
                    .buttonStyle(.bordered)
                }
                ShareLink(item: "Join my Fade group “\(group.name)”! Open Fade → Join with a code → \(group.inviteCode)") {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Invite friends")
            } footer: {
                Text("Anyone with this code can join. Invite links that open the app directly come later.")
            }

            Section("Bets") {
                NavigationLink {
                    GamesView()
                } label: {
                    Label("Browse games", systemImage: "sportscourt")
                }
            }

            Section("Members (\(members.count))") {
                ForEach(members) { member in
                    HStack {
                        Text(member.displayName)
                        if member.role == "owner" {
                            Text("owner").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Coins.format(member.balance))").monospacedDigit()
                    }
                }
            }

            Section("Group rules") {
                LabeledContent("Starting balance", value: "\(Coins.format(group.startingBalance)) coins")
                Text(group.buybackSummary).font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                NoMoneyNotice()
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { members = await groups.members(of: group.id) }
        .refreshable { members = await groups.members(of: group.id) }
    }
}
