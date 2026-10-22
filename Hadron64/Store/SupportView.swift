import SwiftUI

/// The single purchase screen, opened two ways: from Home ("Support the game") or by tapping a
/// training mode whose free plays for today are used up.
struct SupportView: View {
    enum Reason: String, Identifiable {
        case support, dailyLimit
        var id: Self { self }
    }

    let reason: Reason

    var body: some View {
        // Sheets get their own scale: on iPad they're narrower than the window behind them.
        SupportContent(reason: reason).adaptiveScale()
    }
}

private struct SupportContent: View {
    let reason: SupportView.Reason
    @Environment(Supporter.self) private var supporter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.uiScale) private var s

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                IconButton(systemName: "xmark", size: 36) { dismiss() }
            }
            .padding([.top, .horizontal], 16 * s)

            Spacer(minLength: 8)
            card
            Spacer(minLength: 8)

            VStack(spacing: 14 * s) {
                if supporter.isUnlocked {
                    Button { dismiss() } label: { Text("Back to the game") }
                        .buttonStyle(MenuButtonStyle(filled: true))
                } else {
                    Button { Task { await supporter.purchase() } } label: {
                        if supporter.isPurchasing {
                            ProgressView().tint(Palette.paper)
                        } else if let product = supporter.product {
                            Text("Unlock · \(product.displayPrice)")
                        } else if let price = Self.debugPrice {
                            Text("Unlock · \(price)")
                        } else {
                            Text(supporter.loadFailed ? "Store unavailable" : "Loading…")
                        }
                    }
                    .buttonStyle(MenuButtonStyle(filled: true))
                    .disabled(supporter.product == nil || supporter.isPurchasing)

                    Button("Restore Purchase") { Task { await supporter.restore() } }
                        .font(.rounded(15 * s, .semibold))
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(maxWidth: 420 * s)
            .padding(.horizontal, 24)
            .padding(.bottom, 24 * s)
        }
        .background(Palette.paper.ignoresSafeArea())
        .alert("Purchase failed", isPresented: .constant(supporter.errorMessage != nil)) {
            Button("OK") { supporter.errorMessage = nil }
        } message: {
            Text(supporter.errorMessage ?? "")
        }
        .animation(.spring(duration: 0.35), value: supporter.isUnlocked)
    }

    private var card: some View {
        VStack(spacing: 18 * s) {
            CardView(number: supporter.isUnlocked ? 63 : 42)
                .frame(width: 92 * s, height: 92 * s / CardGeometry.aspect)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                .contentTransition(.opacity)

            Text(title)
                .font(.rounded(28 * s, .heavy))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.rounded(17 * s, .medium))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 380 * s)
        .padding(.horizontal, 28)
    }

    /// Simulator screenshots run without the StoreKit configuration, so the product never loads.
    /// `-debugPrice 2.99` shows the button as it will look in the store.
    private static var debugPrice: String? {
        #if DEBUG
        let value = UserDefaults.standard.double(forKey: "debugPrice")
        if value > 0 { return value.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")) }
        #endif
        return nil
    }

    private var title: String {
        if supporter.isUnlocked { return String(localized: "Thank you") }
        switch reason {
        case .support: return String(localized: "Support Hadron 64")
        case .dailyLimit: return String(localized: "That's it for today")
        }
    }

    private var message: String {
        if supporter.isUnlocked {
            return String(localized: "Training and multiplayer are unlimited. Your support keeps the game going.")
        }
        switch reason {
        case .support:
            return String(localized: "A one-time purchase supports the game and unlocks unlimited training and multiplayer.")
        case .dailyLimit:
            return String(localized: "Each training mode is free \(Supporter.freePlaysPerDay) times a day, and multiplayer once a day. A one-time purchase unlocks unlimited play and supports the game.\n\nFree Play and Time Trial are always unlimited.")
        }
    }
}

#Preview {
    SupportView(reason: .dailyLimit).environment(Supporter())
}
