import SwiftUI

struct HomeView: View {
    @State private var session: Session?
    @State private var path = NavigationPath()
    @State private var supportReason: SupportView.Reason?
    @Environment(Supporter.self) private var supporter
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @Environment(\.uiScale) private var s

    enum Route: Hashable { case training, statistics }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                HeroCards().fixedCardLayout()
                    .frame(height: 190 * s)
                Text(verbatim: "HADRON 64")
                    .font(.rounded(38 * s, .heavy))
                    .tracking(4 * s)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 28 * s)
                Spacer(minLength: 24)

                VStack(spacing: 14 * s) {
                    Button { session = .game(.freePlay) } label: {
                        Label("Free Play", systemImage: "infinity")
                    }
                    .buttonStyle(MenuButtonStyle(filled: true))

                    timeTrialRow

                    HStack(spacing: 10 * s) {
                        Button { path.append(Route.training) } label: {
                            Label("Training", systemImage: "dumbbell.fill")
                        }
                        .buttonStyle(MenuButtonStyle())

                        Button(action: openMultiplayer) {
                            Label("Multiplayer", systemImage: "person.2.fill")
                        }
                        .buttonStyle(MenuButtonStyle())
                        .overlay(alignment: .topTrailing) {
                            if supporter.isLocked(.multiplayer) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11 * s, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                    .padding(10 * s)
                                    .allowsHitTesting(false)
                            }
                        }
                    }

                    Button { path.append(Route.statistics) } label: {
                        Label("Statistics", systemImage: "chart.bar.fill")
                    }
                    .buttonStyle(MenuButtonStyle())
                }
                .frame(maxWidth: 420 * s)
                .padding(.horizontal, 24)

                Button { supportReason = .support } label: {
                    Label(supporter.isUnlocked ? "Supporter" : "Support the Game", systemImage: "heart.fill")
                        .font(.rounded(16 * s, .semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(minHeight: 44 * s)
                }
                .padding(.top, 10 * s)
                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { session = .tutorial } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 20 * s, weight: .semibold))
                    }
                    .accessibilityLabel("How to play")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .training: TrainingMenuView(session: $session)
                case .statistics: StatisticsView()
                }
            }
        }
        .sessionCover($session)
        .sheet(item: $supportReason) { SupportView(reason: $0) }
        // A Game Center activity (Games app deep link) asked for a mode; public modes aren't gated.
        .onChange(of: GameCenterService.shared.requestedMode) { _, mode in
            guard let mode else { return }
            GameCenterService.shared.requestedMode = nil
            session = .game(mode)
        }
        .onAppear {
            if !hasSeenTutorial { session = .tutorial }
            #if DEBUG
            // e.g. `-debugScreen freePlay` / `remainderMatch` / `statistics`, for simulator screenshots.
            switch UserDefaults.standard.string(forKey: "debugScreen") {
            case "statistics"?: path.append(Route.statistics)
            case "training"?: path.append(Route.training)
            case "remainder"?: session = .remainder
            case "remainderMatch"?: session = .remainderMatch
            case "setSize"?: session = .setSize
            case "multiplayer"?: session = .multiplayer
            case "support"?: supportReason = .support
            case let mode? where GameMode(rawValue: mode) != nil: session = .game(GameMode(rawValue: mode)!)
            default: break
            }
            #endif
        }
    }

    /// Multiplayer is free once a day; after that it offers the unlock.
    private func openMultiplayer() {
        if supporter.allows(.multiplayer) {
            supporter.recordPlay(.multiplayer)
            session = .multiplayer
        } else {
            supportReason = .dailyLimit
        }
    }

    private var timeTrialRow: some View {
        VStack(spacing: 8 * s) {
            Label("Time Trial", systemImage: "timer")
                .font(.rounded(15 * s, .bold))
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4 * s)
            HStack(spacing: 10 * s) {
                trialButton("Easy", .timeTrialEasy)
                trialButton("Medium", .timeTrialMedium)
                trialButton("Hard", .timeTrialHard)
            }
        }
        .padding(.vertical, 4 * s)
    }

    private func trialButton(_ title: LocalizedStringKey, _ mode: GameMode) -> some View {
        Button { session = .game(mode) } label: {
            VStack(spacing: 2 * s) {
                Text(title)
                if let tt = mode.timeTrial {
                    Text("\(Int(tt.start))s +\(Int(tt.bonus))")
                        .font(.rounded(12 * s, .medium))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .buttonStyle(MenuButtonStyle())
    }
}

/// Three fanned cards that form a set (21 ^ 42 ^ 63 = 0).
private struct HeroCards: View {
    @Environment(\.uiScale) private var s

    var body: some View {
        let w: CGFloat = 104 * s
        ZStack {
            ForEach(Array([21, 63, 42].enumerated()), id: \.offset) { i, n in
                CardView(number: n)
                    .frame(width: w, height: w / CardGeometry.aspect)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    .rotationEffect(.degrees(Double(i - 1) * 12), anchor: .bottom)
                    .offset(x: CGFloat(i - 1) * 44 * s, y: i == 1 ? -8 * s : 0)
                    .zIndex(i == 1 ? 1 : 0)
            }
        }
    }
}

struct TrainingMenuView: View {
    @Binding var session: Session?
    @Environment(Supporter.self) private var supporter
    @State private var unlock: SupportView.Reason?
    @Environment(\.uiScale) private var s

    var body: some View {
        // Centered when it fits (iPad), scrolling when it doesn't.
        ViewThatFits(in: .vertical) {
            menu
            ScrollView { menu }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("Training")
        .sheet(item: $unlock) { SupportView(reason: $0) }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 26 * s) {
            section("Simple Cards", icon: "circle.grid.2x1") {
                HStack(spacing: 10 * s) {
                    simpleButton(.simple3)
                    simpleButton(.simple4)
                    simpleButton(.simple5)
                }
            }
            section("Remainder", icon: "plusminus") {
                Button { open(.remainder) } label: {
                    Label("Count the odd dots", systemImage: "circle.dotted")
                }
                .buttonStyle(MenuButtonStyle())
                .overlay(alignment: .topTrailing) { lockBadge(.remainder) }
            }
            section("Remainder Matching", icon: "equal.circle") {
                Button { open(.remainderMatch) } label: {
                    Label("Match yellow remainders", systemImage: "lock.fill")
                }
                .buttonStyle(MenuButtonStyle())
                .overlay(alignment: .topTrailing) { lockBadge(.remainderMatch) }
            }
            section("Set Size", icon: "number") {
                Button { open(.setSize) } label: {
                    Label("How many cards?", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(MenuButtonStyle())
                .overlay(alignment: .topTrailing) { lockBadge(.setSize) }
            }
            section("Tutorial", icon: "hand.point.up.left") {
                Button { session = .tutorial } label: {
                    Label("How to play", systemImage: "play.fill")
                }
                .buttonStyle(MenuButtonStyle())
            }
        }
        .padding(24)
        .frame(maxWidth: 480 * s)
        .frame(maxWidth: .infinity)
    }

    /// Starts a training mode, counting it toward today's free plays, or offers the unlock once they're used up.
    private func open(_ s: Session) {
        if supporter.allows(s) {
            supporter.recordPlay(s)
            session = s
        } else {
            unlock = .dailyLimit
        }
    }

    /// Only shown once a mode's free plays for today are used up.
    @ViewBuilder
    private func lockBadge(_ session: Session) -> some View {
        if supporter.isLocked(session) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11 * s, weight: .bold))
                .foregroundStyle(Palette.muted)
                .padding(10 * s)
                .allowsHitTesting(false)
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            Label(title, systemImage: icon)
                .font(.rounded(15 * s, .bold))
                .foregroundStyle(Palette.muted)
            content()
        }
    }

    /// Shows a mini card with only that mode's dots, so the choice reads without words.
    private func simpleButton(_ mode: GameMode) -> some View {
        Button { open(.game(mode)) } label: {
            VStack(spacing: 8 * s) {
                CardView(number: mode.dotMask)
                    .frame(width: 44 * s, height: 44 * s / CardGeometry.aspect)
                Text("\(mode.dotCount)")
            }
            .padding(.vertical, 12 * s)
        }
        .buttonStyle(MenuButtonStyle())
        .overlay(alignment: .topTrailing) { lockBadge(.game(mode)) }
    }
}

#Preview {
    HomeView().environment(StatsStore(fileURL: nil)).environment(Supporter())
}
