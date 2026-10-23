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
                // Full size when there's room; shrinks on short screens (iPhone SE) so the menu fits.
                GeometryReader { geo in
                    HeroCards().fixedCardLayout()
                        .scaleEffect(min(1, geo.size.height / (190 * s)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minHeight: 100 * s, maxHeight: 190 * s)
                .layoutPriority(1)
                Text(verbatim: "HADRON 64")
                    .font(.rounded(38 * s, .heavy))
                    .tracking(4 * s)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 28 * s)
                Spacer(minLength: 24)

                VStack(spacing: 14 * s) {
                    HStack(spacing: 10 * s) {
                        Button { session = .game(.freePlay) } label: {
                            Label("Free Play", systemImage: "infinity")
                        }
                        .buttonStyle(MenuButtonStyle(filled: true))

                        Button(action: openMultiplayer) {
                            Label("Multiplayer", systemImage: "person.2.fill")
                        }
                        .buttonStyle(MenuButtonStyle())
                        .overlay(alignment: .topTrailing) {
                            if supporter.isLocked(.multiplayer(.freePlay)) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11 * s, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                    .padding(10 * s)
                                    .allowsHitTesting(false)
                            }
                        }
                    }

                    timeTrialRow

                    HStack(spacing: 10 * s) {
                        Button { path.append(Route.training) } label: {
                            Label("Training", systemImage: "dumbbell.fill")
                        }
                        .buttonStyle(MenuButtonStyle())

                        Button { path.append(Route.statistics) } label: {
                            Label("Statistics", systemImage: "chart.bar.fill")
                        }
                        .buttonStyle(MenuButtonStyle())
                    }
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
            // e.g. `-debugScreen freePlay` / `remainder` / `statistics`, for simulator screenshots.
            switch UserDefaults.standard.string(forKey: "debugScreen") {
            case "statistics"?: path.append(Route.statistics)
            case "training"?: path.append(Route.training)
            case "remainder"?: session = .remainder
            case "multiplayer"?: session = .multiplayer(.freePlay)
            case let m? where m.hasPrefix("multiplayer:"):   // e.g. `multiplayer:extraHard`
                if let mode = GameMode(rawValue: String(m.dropFirst("multiplayer:".count))) { session = .multiplayer(mode) }
            case "support"?: supportReason = .support
            case let mode? where GameMode(rawValue: mode) != nil: session = .game(GameMode(rawValue: mode)!)
            default: break
            }
            #endif
        }
    }

    /// Multiplayer is free once a day; after that it offers the unlock.
    private func openMultiplayer() {
        if supporter.allows(.multiplayer(.freePlay)) {
            supporter.recordPlay(.multiplayer(.freePlay))
            session = .multiplayer(.freePlay)
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
            // Simple Cards and Extra Hard: same tile, same choice of free play or a trial, solo or together.
            section("Choose Your Deck", icon: "rectangle.stack") {
                HStack(spacing: 10 * s) {
                    ForEach([GameMode.simple3, .simple4, .simple5]) { mode in
                        TrialOptionsButton(mode: mode, subtitle: "\(mode.dotCount) dots · \(mode.dealSize) cards", open: open) {
                            CardView(number: mode.dotMask)
                        } caption: {
                            Text("\(mode.dotCount)")
                        }
                    }
                    TrialOptionsButton(mode: .extraHard, subtitle: "Shaded backgrounds · 8 cards", open: open) {
                        // A shaded card: the background is the seventh thing to pair up.
                        CardView(number: 21 | CardMath.backgroundBit)
                    } caption: {
                        Image(systemName: "flame.fill")
                    }
                }
            }
            section("Remainder", icon: "plusminus") {
                Button { open(.remainder) } label: {
                    Label("Count the odd dots", systemImage: "circle.dotted")
                }
                .buttonStyle(MenuButtonStyle())
                .overlay(alignment: .topTrailing) { lockBadge(.remainder) }
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
}

/// A deck tile (a mini card and a caption). Tapping it offers free play, multiplayer, or a time trial with that deck.
private struct TrialOptionsButton<Card: View, Caption: View>: View {
    let mode: GameMode
    let subtitle: LocalizedStringKey
    let open: (Session) -> Void
    @ViewBuilder let card: Card
    @ViewBuilder let caption: Caption
    @State private var showsOptions = false
    @Environment(Supporter.self) private var supporter
    @Environment(\.uiScale) private var s

    var body: some View {
        Button { showsOptions = true } label: {
            VStack(spacing: 8 * s) {
                card.frame(width: 44 * s, height: 44 * s / CardGeometry.aspect)
                caption
            }
            .padding(.vertical, 12 * s)
        }
        .buttonStyle(MenuButtonStyle())
        .accessibilityLabel(mode.title)
        .overlay(alignment: .topTrailing) {
            if allLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11 * s, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .padding(10 * s)
                    .allowsHitTesting(false)
            }
        }
        .popover(isPresented: $showsOptions) {
            options
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Palette.paper)
        }
        #if DEBUG
        // e.g. `-debugScreen training -debugTrialOptions simple4`, for simulator screenshots.
        .task {
            try? await Task.sleep(for: .seconds(0.8))
            if UserDefaults.standard.string(forKey: "debugTrialOptions") == mode.rawValue { showsOptions = true }
        }
        #endif
    }

    private var sessions: [Session] {
        guard let trials = mode.trials else { return [.game(mode), .multiplayer(mode)] }
        return [.game(mode), .multiplayer(mode), .game(trials.easy), .game(trials.hard)]
    }

    private var allLocked: Bool { sessions.allSatisfy(supporter.isLocked) }

    private var options: some View {
        VStack(spacing: 10 * s) {
            VStack(spacing: 2 * s) {
                Text(mode.title)
                    .font(.rounded(17 * s, .bold))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.rounded(13 * s, .medium))
                    .foregroundStyle(Palette.muted)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 4 * s)

            ForEach(sessions, id: \.self) { option in
                let filled = option == .game(mode)
                Button {
                    showsOptions = false
                    open(option)
                } label: {
                    HStack(spacing: 10 * s) {
                        Image(systemName: icon(for: option))
                            .frame(width: 24 * s)
                        Text(title(for: option))
                        Spacer(minLength: 8 * s)
                        if case .game(let trial) = option, let tt = trial.timeTrial {
                            Text("\(Int(tt.start))s +\(Int(tt.bonus))")
                                .font(.rounded(13 * s, .medium))
                                .foregroundStyle(Palette.muted)
                        }
                        if supporter.isLocked(option) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11 * s, weight: .bold))
                                .foregroundStyle(filled ? Palette.paper.opacity(0.7) : Palette.muted)
                        }
                    }
                    .padding(.horizontal, 6 * s)
                }
                .buttonStyle(MenuButtonStyle(filled: filled))
            }
        }
        .padding(16 * s)
        .frame(width: 270 * s)
    }

    private func icon(for option: Session) -> String {
        switch option {
        case .multiplayer: "person.2.fill"
        case .game(let m) where m.isTimeTrial: "timer"
        default: "infinity"
        }
    }

    private func title(for option: Session) -> LocalizedStringKey {
        switch option {
        case .multiplayer: "Multiplayer"
        case .game(mode.trials?.easy): "Easy Trial"
        case .game(mode.trials?.hard): "Hard Trial"
        default: "Free Play"
        }
    }
}

#Preview {
    HomeView().environment(StatsStore(fileURL: nil)).environment(Supporter())
}
