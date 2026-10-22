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

    static let paper = Color(hex: 0xF3EFE6)
    static let ink = Color(hex: 0x1C1C1E)
    static let muted = Color(hex: 0x8A857A)
    static let faint = Color(hex: 0xD6D0C4)
    static let card = Color.white
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Big outlined menu button.
struct MenuButtonStyle: ButtonStyle {
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(19))
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(filled ? Palette.paper : Palette.ink)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(filled ? Palette.ink : Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.ink, lineWidth: 2))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Round icon button used in game top bars.
struct IconButton: View {
    let systemName: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .bold))
                .frame(width: size, height: size)
                .foregroundStyle(Palette.ink)
                .background(Circle().fill(Palette.card))
                .overlay(Circle().strokeBorder(Palette.ink.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
