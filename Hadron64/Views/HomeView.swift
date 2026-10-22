import SwiftUI

struct HomeView: View {
    @State private var session: Session?
    @State private var path = NavigationPath()
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false

    enum Route: Hashable { case training, statistics }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                HeroCards()
                    .frame(height: 190)
                Text("HADRON 64")
                    .font(.rounded(38, .heavy))
                    .tracking(4)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 28)
                Spacer(minLength: 24)

                VStack(spacing: 14) {
                    Button { session = .game(.freePlay) } label: {
                        Label("Free Play", systemImage: "infinity")
                    }
                    .buttonStyle(MenuButtonStyle(filled: true))

                    timeTrialRow

                    Button { path.append(Route.training) } label: {
                        Label("Training", systemImage: "dumbbell.fill")
                    }
                    .buttonStyle(MenuButtonStyle())

                    Button { path.append(Route.statistics) } label: {
                        Label("Statistics", systemImage: "chart.bar.fill")
                    }
                    .buttonStyle(MenuButtonStyle())
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 24)
                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { session = .tutorial } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 20, weight: .semibold))
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
            case let mode? where GameMode(rawValue: mode) != nil: session = .game(GameMode(rawValue: mode)!)
            default: break
            }
            #endif
        }
    }

    private var timeTrialRow: some View {
        VStack(spacing: 8) {
            Label("Time Trial", systemImage: "timer")
                .font(.rounded(15, .bold))
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
            HStack(spacing: 10) {
                trialButton("Easy", .timeTrialEasy)
                trialButton("Medium", .timeTrialMedium)
                trialButton("Hard", .timeTrialHard)
            }
        }
        .padding(.vertical, 4)
    }

    private func trialButton(_ title: String, _ mode: GameMode) -> some View {
        Button { session = .game(mode) } label: {
            VStack(spacing: 2) {
                Text(title)
                if let tt = mode.timeTrial {
                    Text("\(Int(tt.start))s +\(Int(tt.bonus))")
                        .font(.rounded(12, .medium))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .buttonStyle(MenuButtonStyle())
    }
}

/// Three fanned cards that form a set (21 ^ 42 ^ 63 = 0).
private struct HeroCards: View {
    var body: some View {
        let w: CGFloat = 104
        ZStack {
            ForEach(Array([21, 63, 42].enumerated()), id: \.offset) { i, n in
                CardView(number: n)
                    .frame(width: w, height: w / CardGeometry.aspect)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    .rotationEffect(.degrees(Double(i - 1) * 12), anchor: .bottom)
                    .offset(x: CGFloat(i - 1) * 44, y: i == 1 ? -8 : 0)
                    .zIndex(i == 1 ? 1 : 0)
            }
        }
    }
}

struct TrainingMenuView: View {
    @Binding var session: Session?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                section("Simple Cards", icon: "circle.grid.2x1") {
                    HStack(spacing: 10) {
                        simpleButton(.simple3)
                        simpleButton(.simple4)
                        simpleButton(.simple5)
                    }
                }
                section("Remainder", icon: "plusminus") {
                    Button { session = .remainder } label: {
                        Label("Count the odd dots", systemImage: "circle.dotted")
                    }
                    .buttonStyle(MenuButtonStyle())
                }
                section("Remainder Matching", icon: "equal.circle") {
                    Button { session = .remainderMatch } label: {
                        Label("Match yellow remainders", systemImage: "lock.fill")
                    }
                    .buttonStyle(MenuButtonStyle())
                }
                section("Set Size", icon: "number") {
                    Button { session = .setSize } label: {
                        Label("How many cards?", systemImage: "square.stack.3d.up")
                    }
                    .buttonStyle(MenuButtonStyle())
                }
                section("Tutorial", icon: "hand.point.up.left") {
                    Button { session = .tutorial } label: {
                        Label("How to play", systemImage: "play.fill")
                    }
                    .buttonStyle(MenuButtonStyle())
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("Training")
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.rounded(15, .bold))
                .foregroundStyle(Palette.muted)
            content()
        }
    }

    /// Shows a mini card with only that mode's dots, so the choice reads without words.
    private func simpleButton(_ mode: GameMode) -> some View {
        Button { session = .game(mode) } label: {
            VStack(spacing: 8) {
                CardView(number: mode.dotMask)
                    .frame(width: 44, height: 44 / CardGeometry.aspect)
                Text("\(mode.dotCount)")
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(MenuButtonStyle())
    }
}

#Preview {
    HomeView().environment(StatsStore(fileURL: nil))
}
