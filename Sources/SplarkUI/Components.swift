import SplarkKit
import SwiftUI

/// The pieces setup and Settings share (design/prototype/setup.html).

/// A button: `.primary` (dark), `.secondary` (chip), `.ghost` (text only).
struct WindowButton: View {
    enum Kind { case primary, secondary, ghost }
    let title: String
    var kind: Kind = .primary
    var wide = false
    var enabled = true
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = Self.colors(kind, enabled: enabled, palette: Palette(scheme))
        Button(action: action) {
            Text(title)
                .font(Theme.font(13, kind == .primary ? .semibold : .medium))
                .foregroundStyle(colors.text)
                .frame(maxWidth: wide ? .infinity : nil)
                .padding(.vertical, wide ? 11 : 9)
                .padding(.horizontal, kind == .ghost ? 10 : 18)
                .background(RoundedRectangle(cornerRadius: 10).fill(colors.background))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// A disabled button is quiet but readable: the disabled grey, with secondary text. (Fading the whole button to 35%
    /// left a dark button's white label invisible.)
    static func colors(_ kind: Kind, enabled: Bool, palette: Palette) -> (background: Ink, text: Ink) {
        switch (kind, enabled) {
        case (.ghost, true): return (Ink(0, opacity: 0), palette.secondary)
        case (.ghost, false): return (Ink(0, opacity: 0), palette.tertiary)
        case (_, false): return (palette.disabledButton, palette.secondary)
        case (.primary, true): return (palette.button, palette.buttonText)
        case (.secondary, true): return (palette.chip, palette.text)
        }
    }
}

/// A small chip button: "Open api.slack.com/apps ↗".
struct MiniButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        Button(action: action) {
            Text(title).font(Theme.font(12, .medium)).foregroundStyle(palette.text).lineLimit(1).fixedSize()
                .padding(EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9))
                .background(RoundedRectangle(cornerRadius: 7).fill(palette.chip))
        }
        .buttonStyle(.plain)
    }
}

/// Body copy with **bold** runs, as in the prototype: secondary text, bold in the main text colour.
struct RichText: View {
    let markdown: String
    var size: CGFloat = 13
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        var attributed = (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            attributed[run.range].foregroundColor = palette.text.color
            attributed[run.range].font = Theme.font(size, .semibold)
        }
        return Text(attributed).font(Theme.font(size)).foregroundStyle(palette.secondary).lineSpacing(size * 0.27)   // CSS line-height ≈ 1.45
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A rounded panel of rows on the chip colour, with separators: workspace lists, switches.
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 12).fill(palette.chip))
    }
}

struct CardSeparator: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Rectangle().fill(Palette(scheme).separator).frame(height: 0.5) }
}

/// A note with a spark: errors, "needs approval", the ChatGPT usage note.
struct MessageBox: View {
    let level: SparkLevel
    let markdown: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        HStack(alignment: .top, spacing: 10) {
            SparkView(level: level).foregroundStyle(palette.spark).padding(.top, 3)
            RichText(markdown: markdown, size: 12.5)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.chip))
    }
}

/// "Creating your private Slack app…" with the cycling spark.
struct WorkingLine: View {
    let markdown: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            CyclingSpark().foregroundStyle(Palette(scheme).spark)
            RichText(markdown: markdown)
        }
        .padding(.vertical, 12)
    }
}

/// A workspace's or account's pixel-initial tile.
struct InitialTile: View {
    let text: String
    var size: CGFloat = 30
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        PixelText(String(text.prefix(2)).uppercased(), scale: 2)
            .foregroundStyle(palette.tileText)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.23).fill(palette.tile))
    }

    /// "Lumen" → "L", "Lumen Community" → "LC".
    static func initials(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first))
    }
}

/// A switch row: "Open at login", "Show count next to the spark".
struct SwitchRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.font(13)).foregroundStyle(palette.text)
                if let detail { Text(detail).font(Theme.font(11.5)).foregroundStyle(palette.tertiary) }
            }
            Spacer()
            Toggle(title, isOn: $isOn).toggleStyle(MonoSwitchStyle()).labelsHidden()
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
    }
}

/// The app icon, drawn from PixelArt.
struct AppIconView: View {
    let size: CGFloat
    var body: some View {
        Image(decorative: AppIconArt.cgImage(size: Int(size * 2 * 1024 / 824)), scale: 2)
            .resizable()
            .interpolation(.none)
            .frame(width: size * 1024 / 824, height: size * 1024 / 824)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: 9, y: 8)
    }
}

/// A token field: monospaced, with the prototype's border. Offscreen snapshots draw a look-alike.
struct TokenField: View {
    let placeholder: String
    @Binding var text: String
    var monospaced = true
    var onSubmit: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let palette = Palette(scheme)
        Group {
            if isSnapshot {
                Text(text.isEmpty ? placeholder : text).foregroundStyle(text.isEmpty ? palette.tertiary : palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $text, prompt: Text(placeholder).font(Theme.font(12.5)).foregroundColor(palette.tertiary.color))
                    .textFieldStyle(.plain)
                    .foregroundStyle(palette.text)
                    .onSubmit(onSubmit)
            }
        }
        .font(monospaced ? .system(size: 12.5, design: .monospaced) : Theme.font(12.5))
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 9).fill(palette.field))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.fieldBorder, lineWidth: 1))
    }
}

/// The prototype's monochrome switch: a grey track (#55555b when on; #a8a8ae in dark mode) and a white knob.
struct MonoSwitchStyle: ToggleStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Capsule()
            .fill(on ? Ink(scheme == .dark ? 0xa8a8ae : 0x55555b) : Ink(0x8e8e94))
            .frame(width: 34, height: 20)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.2), radius: 1, y: 1).padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() } }
            .accessibilityElement()
            .accessibilityLabel(Text("\(configuration.isOn ? "On" : "Off")"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { configuration.isOn.toggle() }
    }
}
