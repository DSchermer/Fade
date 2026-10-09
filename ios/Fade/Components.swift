import SwiftUI

// MARK: - Coins

/// The gold coin that sits beside every amount.
struct CoinIcon: View {
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().fill(Theme.coin)
                .frame(width: size * 0.875, height: size * 0.875)
            Circle().strokeBorder(Theme.coinRing, lineWidth: size * 0.075)
                .frame(width: size * 0.525, height: size * 0.525)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// An amount of coins with the coin icon: "100.00", or "+12.50" / "−8.00" in green / red when `signed`.
struct CoinAmount: View {
    let centicoins: Int64
    var signed = false
    var font: Font = .subheadline.weight(.bold)
    var iconSize: CGFloat = 14
    var tint: Color?

    private var text: String { signed ? Coins.formatSigned(centicoins) : Coins.formatFixed(centicoins) }

    private var color: Color {
        if let tint { return tint }
        guard signed else { return Theme.text }
        if centicoins > 0 { return Theme.win }
        if centicoins < 0 { return Theme.loss }
        return Theme.text
    }

    var body: some View {
        HStack(spacing: max(4, iconSize * 0.4)) {
            CoinIcon(size: iconSize)
            Text(text)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text) coins")
    }
}

// MARK: - People

/// A round avatar with the person's initial. The colour comes from the name, so it never changes.
struct Avatar: View {
    let name: String
    var size: CGFloat = 36
    var letters = 1

    var body: some View {
        Circle()
            .fill(Color(hex: AvatarPalette.hue(for: name)))
            .frame(width: size, height: size)
            .overlay(
                Text(AvatarPalette.initials(name, count: letters))
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(Theme.onAvatar)
            )
            .accessibilityHidden(true)
    }
}

/// A group's badge: its initials on a blue disc.
struct GroupBadge: View {
    let name: String
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(Color(hex: AvatarPalette.hues[0]))
            .frame(width: size, height: size)
            .overlay(
                Text(AvatarPalette.groupInitials(name))
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(Theme.onAvatar)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Labels and pills

/// The little capital-letter heading above a block ("TELL ME WHEN").
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.fadeLabel)
            .tracking(1)
            .foregroundStyle(Theme.text2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Status words are fixed: Open, Pending, Won, Lost, Void.
struct StatusPill: View {
    let text: String
    let tone: FeedTone

    private var color: Color {
        switch tone {
        case .open: return Theme.accent
        case .pending: return Theme.pending
        case .win: return Theme.win
        case .loss: return Theme.loss
        case .neutral: return Theme.text2
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
    }
}

/// A small box with a heading and a value, like "OPEN — 40 shares". Pass `coins` to show an amount with the coin icon.
struct StatTile: View {
    let label: String
    var value: String = ""
    var detail: String?
    var coins: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.fadeLabel)
                .tracking(0.8)
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let coins {
                CoinAmount(centicoins: coins, font: .fadeBody.weight(.bold), iconSize: 14)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.fadeBody.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text2)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Buttons

/// Fade's buttons: filled blue (primary), outlined (secondary), grey (quiet), red (destructive).
struct FadeButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, destructive, destructiveOutline }

    var kind: Kind = .primary
    var height: CGFloat = 48
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        FadeButtonBody(configuration: configuration, kind: kind, height: height, fullWidth: fullWidth)
    }
}

private struct FadeButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: FadeButtonStyle.Kind
    let height: CGFloat
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var foreground: Color {
        if !isEnabled { return Theme.text3 }
        switch kind {
        case .primary, .destructive: return Theme.onAccent
        case .secondary, .quiet: return Theme.text
        case .destructiveOutline: return Theme.loss
        }
    }

    private var fill: Color {
        if !isEnabled { return Theme.raised }
        switch kind {
        case .primary: return Theme.accent
        case .destructive: return Theme.loss
        case .quiet: return Theme.raised
        case .secondary, .destructiveOutline: return Color.clear
        }
    }

    private var borderColor: Color {
        guard isEnabled else { return Color.clear }
        switch kind {
        case .secondary: return Theme.line
        case .destructiveOutline: return Theme.loss.opacity(0.5)
        default: return Color.clear
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: height >= 56 ? 16 : Theme.Radius.button, style: .continuous)
        configuration.label
            .font(.fadeBody.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, fullWidth ? 8 : 20)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(borderColor, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(shape)
    }
}

extension ButtonStyle where Self == FadeButtonStyle {
    static var fadePrimary: FadeButtonStyle { FadeButtonStyle(kind: .primary) }
    static var fadeSecondary: FadeButtonStyle { FadeButtonStyle(kind: .secondary) }
    static var fadeQuiet: FadeButtonStyle { FadeButtonStyle(kind: .quiet) }
    static var fadeDestructiveOutline: FadeButtonStyle { FadeButtonStyle(kind: .destructiveOutline) }
    static var fadeDestructive: FadeButtonStyle { FadeButtonStyle(kind: .destructive) }
    static var fadePrimaryLarge: FadeButtonStyle { FadeButtonStyle(kind: .primary, height: 56) }
    static var fadeSecondaryLarge: FadeButtonStyle { FadeButtonStyle(kind: .secondary, height: 56) }
    static var fadeDestructiveLarge: FadeButtonStyle { FadeButtonStyle(kind: .destructive, height: 56) }
    /// A compact 44-point button that hugs its text (like "Fade this offer").
    static var fadePrimaryCompact: FadeButtonStyle { FadeButtonStyle(kind: .primary, height: 44, fullWidth: false) }
    static var fadeQuietCompact: FadeButtonStyle { FadeButtonStyle(kind: .quiet, height: 44, fullWidth: false) }
    static var fadeSecondaryCompact: FadeButtonStyle { FadeButtonStyle(kind: .secondary, height: 44, fullWidth: false) }
}

/// A 44-point round button with an icon, used in screen headers.
struct CircleIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .background(Theme.raised, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Chips

/// A pill-shaped filter ("All groups", "NHL"). The chosen one is inverted.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.fadeBody.weight(isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? Theme.bg : Theme.text2)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(isSelected ? Theme.text : Theme.raised, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A two-or-three way switch (like "Back Rangers | Back Capitals"). The chosen one is raised.
struct FadeSegmented<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.fadeBody.weight(selected ? .bold : .semibold))
                        .foregroundStyle(selected ? Theme.text : Theme.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selected ? Theme.bg : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
    }
}

/// − [ number ] + for a whole number you can also type. The text belongs to the screen, which turns it into a number.
struct QuantityStepper: View {
    @Binding var text: String
    var minimum = 1
    var maximum: Int?
    var step = 1
    var showsCoin = false
    var lessLabel = "Fewer"
    var moreLabel = "More"

    /// What's typed, kept in a sane range so a silly number can never overflow later maths.
    private var current: Int { min(1_000_000_000, max(0, Int(text.trimmingCharacters(in: .whitespaces)) ?? minimum)) }

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: lessLabel) {
                let next = max(minimum, current - step)
                text = String(maximum.map { min($0, next) } ?? next)
            }
            HStack(spacing: 6) {
                if showsCoin { CoinIcon(size: 22) }
                TextField("0", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title2.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: showsCoin ? 96 : .infinity)
            }
            .frame(maxWidth: .infinity)
            stepButton("plus", label: moreLabel) {
                let next = current + step
                text = String(maximum.map { min($0, next) } ?? next)
            }
        }
        .padding(4)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Text tabs with a blue underline under the chosen one ("All  NHL  NBA", or "Pending 2  Open offers 1  Settled").
struct UnderlineTabs<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: String
        var count: Int?
        var id: String { title }
    }

    let items: [Item]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let selected = item.value == selection
                Button {
                    selection = item.value
                } label: {
                    HStack(spacing: 5) {
                        Text(item.title)
                            .font(.fadeBody.weight(selected ? .bold : .semibold))
                            .foregroundStyle(selected ? Theme.text : Theme.text2)
                        if let count = item.count, count > 0 {
                            Text("\(count)")
                                .font(.fadeBody.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.text2)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(selected ? Theme.accent : Color.clear).frame(height: 2.5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

// MARK: - Empty states

/// A friendly card for a list with nothing in it yet.
struct EmptyStateCard<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    let actions: Actions

    init(systemImage: String, title: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.text2)
                .frame(width: 56, height: 56)
                .background(Theme.raised, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.fadeSectionTitle)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.fadeBody)
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .frame(maxWidth: .infinity)
        .fadeCard(padding: 20)
    }
}

extension EmptyStateCard where Actions == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

/// A line of red text for an error, in the same place on every screen.
struct ErrorLine: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.fadeCaption)
            .foregroundStyle(Theme.loss)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Footnotes

/// The one-line reminder shown on the main screens.
struct NoMoneyNotice: View {
    var body: some View {
        Text("Fade coins are free play money. They have no cash value and can't be bought, sold, or redeemed.")
            .font(.fadeCaption)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.text3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
