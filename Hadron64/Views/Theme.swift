import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Dot colors are Paul Tol's colorblind-safe high-contrast palette (https://personal.sron.nl/~pault/).
enum Palette {
    static let yellow = Color(hex: 0xDDAA33)
    static let red = Color(hex: 0xBB5566)
    static let blue = Color(hex: 0x004488)
    static let rows = [yellow, red, blue]
    /// Success only (a found set), never a dot color.
    static let green = Color(hex: 0x2BC253)

    static let paper = Color(hex: 0xF3EFE6)
    static let ink = Color(hex: 0x1C1C1E)
    static let muted = Color(hex: 0x8A857A)
    static let faint = Color(hex: 0xD6D0C4)
    static let card = Color.white
    /// Extra Hard's shaded card background, dark enough to tell from white at a glance but light enough for every dot.
    static let shade = Color(hex: 0xC9C1B1)
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// How much bigger to draw text and chrome than on a phone. 1 on iPhone (and narrow iPad windows),
/// up to 1.5 on a full-screen iPad. Card sizes come from `TableLayout` instead.
private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

extension View {
    /// Sets `uiScale` for this view's subtree from the space it fills. Apply at the root of each
    /// window, sheet and full-screen cover.
    func adaptiveScale() -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            self.environment(\.uiScale, min(max(side / 460, 1), 1.5))
        }
    }
}

/// Big outlined menu button.
struct MenuButtonStyle: ButtonStyle {
    var filled = false
    @Environment(\.uiScale) private var s

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(19 * s))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8 * s)
            .frame(maxWidth: .infinity, minHeight: 56 * s)
            .foregroundStyle(filled ? Palette.paper : Palette.ink)
            .background(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).fill(filled ? Palette.ink : Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).strokeBorder(Palette.ink, lineWidth: 2))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Round icon button used in game top bars.
struct IconButton: View {
    let systemName: String
    var size: CGFloat = 44
    let action: () -> Void
    @Environment(\.uiScale) private var s

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * s * 0.4, weight: .bold))
                .frame(width: size * s, height: size * s)
                .foregroundStyle(Palette.ink)
                .background(Circle().fill(Palette.card))
                .overlay(Circle().strokeBorder(Palette.ink.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
