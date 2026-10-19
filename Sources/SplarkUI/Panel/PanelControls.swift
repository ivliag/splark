import SplarkKit
import SwiftUI

/// A small borderless button with the prototype's hover chip: the row toolbar's actions, "Open in Slack". Compact in the
/// hover toolbar, which shares its line with where the item came from.
struct ChipButton<Label: View>: View {
    let help: String
    var compact = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let palette = Palette(scheme)
        Button(action: action) {
            label()
                .lineLimit(1)
                .fixedSize()
                .font(Theme.font(11.5, .medium))
                .foregroundStyle(hovering ? palette.text : palette.secondary)
                .frame(minWidth: compact ? 22 : 24, minHeight: 22)
                .padding(.horizontal, compact ? 2 : 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? palette.chipHover : Ink(0, opacity: 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// The round ✓ that marks a conversation read (and ✓✓ for all comments).
struct ReadButton: View {
    let help: String
    let double: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let palette = Palette(scheme)
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(lineWidth: 1.2)
                if double {
                    HStack(spacing: -3) {
                        Image(systemName: "checkmark")
                        Image(systemName: "checkmark")
                    }
                    .font(.system(size: 6.5, weight: .bold))
                } else {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                }
            }
            .frame(width: 17, height: 17)
            .foregroundStyle(hovering ? palette.text : palette.secondary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(hovering ? palette.chip : Ink(0, opacity: 0)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// The header's quiet icon buttons: Open Slack, Settings.
struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let palette = Palette(scheme)
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(hovering ? palette.text : palette.tertiary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? palette.rowHover : Ink(0, opacity: 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}
