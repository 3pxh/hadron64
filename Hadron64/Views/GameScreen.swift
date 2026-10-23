import SwiftUI

/// Free Play, Time Trial, and the Simple Cards drills.
struct GameScreen: View {
    let mode: GameMode
    @State private var game: DeckGame
    @State private var summary: ResultSummary?
    @State private var paused = false
    @AppStorage("hidesFreePlayClock") private var hidesClock = false
    @Environment(StatsStore.self) private var stats
    @Environment(Supporter.self) private var supporter
    @State private var showsUnlock = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.uiScale) private var s

    init(mode: GameMode) {
        self.mode = mode
        _game = State(initialValue: DeckGame(mode: mode))
    }

    var body: some View {
        GeometryReader { geo in
            let layout = TableLayout(size: geo.size, slotCount: game.table.slots.count, scale: s)
            ZStack {
                CardTableView(table: game.table, layout: layout, selected: game.selected,
                              marked: game.hintIncluded, crossed: game.hintExcluded,
                              celebrating: game.celebrating, cancelled: game.cancelled) { game.toggle($0) }
                topBar
                    .frame(height: layout.topBarHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .overlay {
            if paused {
                PauseOverlay(onResume: resume, onQuit: { dismiss() })
                    .transition(.opacity)
            }
        }
        .overlay {
            if let summary {
                ResultsView(summary: summary, onReplay: replay, onHome: { dismiss() })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .sheet(isPresented: $showsUnlock) { SupportView(reason: .dailyLimit) }
        .animation(.easeInOut(duration: 0.25), value: paused)
        .animation(.spring(duration: 0.4), value: summary?.id)
        .sensoryFeedback(.selection, trigger: game.selected)
        .sensoryFeedback(.success, trigger: game.setsFound)
        .onAppear {
            GameCenterService.shared.setAccessPointVisible(false)
            begin(game)
            #if DEBUG
            Task { await stage(game) }
            #endif
        }
        .onDisappear { GameCenterService.shared.setAccessPointVisible(true) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && summary == nil { pause() }
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack {
            IconButton(systemName: "xmark") { dismiss() }
            Spacer()
            if game.hintsAllowed { HintButton(game: game) }
            IconButton(systemName: "pause.fill", action: pause)
        }
        .padding(.horizontal, 16 * s)
        .overlay {
            if mode == .freePlay {
                // Tap to hide the clock (and tap again to bring it back); remembered across games.
                ZStack {
                    if hidesClock {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 17 * s, weight: .semibold))
                            .foregroundStyle(Palette.faint)
                    } else {
                        ClockLabel(game: game)
                    }
                }
                .frame(width: 120 * s, height: 44 * s)
                .contentShape(Rectangle())
                .onTapGesture { hidesClock.toggle() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(hidesClock ? "Show clock" : "Hide clock")
            } else {
                ClockLabel(game: game)
            }
        }
    }

    private func begin(_ g: DeckGame) {
        g.onFind = { stats.log($0) }
        g.onFinish = { record in summary = stats.log(record) }
        g.start()
    }

    #if DEBUG
    /// Screenshot staging from launch arguments, e.g. `-debugFinds 5 -debugClock 214 -debugHint 1 -debugSelect 2`:
    /// collect some sets, push the clock forward, press the hint, then leave a partial selection.
    /// For the app preview video, `-debugAutoplay 0.9` instead plays the whole deck, one tap every 0.9s.
    private func stage(_ g: DeckGame) async {
        let d = UserDefaults.standard
        try? await Task.sleep(for: .seconds(1.2))
        let tap = d.double(forKey: "debugAutoplay")
        if tap > 0 {
            while !g.isFinished {
                // The smallest set each time keeps the rule easy to follow on video.
                guard let set = CardMath.allSets(in: g.table.boardCards).min(by: { $0.count < $1.count }) else { break }
                for card in set {
                    try? await Task.sleep(for: .seconds(tap))
                    g.toggle(card)
                }
                try? await Task.sleep(for: .seconds(tap * 1.2))
            }
            return
        }
        for _ in 0..<d.integer(forKey: "debugFinds") {
            guard let set = CardMath.allSets(in: g.table.boardCards).min(by: { $0.count < $1.count }) else { break }
            set.forEach(g.toggle)
            try? await Task.sleep(for: .seconds(1.2))
        }
        g.clock.debugAdvance(by: d.double(forKey: "debugClock"))
        for _ in 0..<d.integer(forKey: "debugHint") { g.hint() }
        let n = d.integer(forKey: "debugSelect")
        var rng = SeededGenerator(seed: 7)
        if n > 0, let set = CardMath.allSets(in: g.table.boardCards).filter({ $0.count > n }).randomElement(using: &rng) {
            set.prefix(n).forEach(g.toggle)
        }
    }
    #endif

    private func replay() {
        // Replaying a Simple Cards deck counts as another training play.
        guard supporter.allows(.game(mode)) else { showsUnlock = true; return }
        supporter.recordPlay(.game(mode))
        let next = DeckGame(mode: mode)
        summary = nil
        game = next
        begin(next)
    }

    private func pause() {
        guard !game.isFinished else { return }
        game.pause()
        paused = true
    }

    private func resume() {
        paused = false
        game.resume()
    }
}

/// Lightbulb; after the first press it shows the size of the hinted set, after the second it's spent.
struct HintButton: View {
    let game: DeckGame
    @Environment(\.uiScale) private var s

    var body: some View {
        Button { game.hint() } label: {
            ZStack {
                if game.hintLevel == 0 {
                    Image(systemName: "lightbulb.fill").font(.system(size: 17 * s, weight: .bold))
                } else {
                    Text("\(game.hintSet.count)").font(.rounded(21 * s, .heavy))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 44 * s, height: 44 * s)
            .foregroundStyle(Palette.ink)
            .background(Circle().fill(game.hintLevel > 0 ? Palette.yellow.opacity(0.45) : Palette.card))
            .overlay(Circle().strokeBorder(game.hintLevel > 0 ? Palette.yellow : Palette.ink.opacity(0.12),
                                           lineWidth: game.hintLevel == 1 ? 2 : 1))
            .opacity(game.hintLevel >= 2 ? 0.6 : 1)
            .animation(.spring(duration: 0.3), value: game.hintLevel)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hint")
    }
}

/// Count-up timer for Free Play, countdown (with a "+N" pop on each bonus) for Time Trial.
/// Kept separate so only this view re-renders on every clock tick.
struct ClockLabel: View {
    let game: DeckGame
    @Environment(\.uiScale) private var s

    var body: some View {
        let remaining = game.timeRemaining
        let urgent = (remaining ?? .infinity) < 10
        Text(remaining?.countdownString ?? game.clock.elapsed.clockString)
            .font(.rounded(30 * s).monospacedDigit())
            .foregroundStyle(urgent ? Palette.red : Palette.ink)
            .scaleEffect(urgent ? 1.08 : 1)
            .animation(.spring(duration: 0.3), value: urgent)
            .overlay(alignment: .trailing) {
                if let bonus = game.mode.timeTrial?.bonus, game.setsFound > 0 {
                    RiseAndFade(text: "+\(Int(bonus))")
                        .id(game.setsFound)
                        .offset(x: 48 * s)
                }
            }
    }
}

/// Floats up and fades away once, each time it's (re)created.
struct RiseAndFade: View {
    let text: String
    @State private var gone = false
    @Environment(\.uiScale) private var s

    var body: some View {
        Text(text)
            .font(.rounded(20 * s, .bold))
            .foregroundStyle(Palette.blue)
            .fixedSize()
            .offset(y: gone ? -26 * s : 0)
            .opacity(gone ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.1)) { gone = true } }
    }
}

/// Hides the board while paused so the clock can't be gamed.
struct PauseOverlay: View {
    let onResume: () -> Void
    let onQuit: () -> Void
    @Environment(\.uiScale) private var s

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            VStack(spacing: 28 * s) {
                Button(action: onResume) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 40 * s, weight: .bold))
                        .foregroundStyle(Palette.paper)
                        .frame(width: 104 * s, height: 104 * s)
                        .background(Circle().fill(Palette.ink))
                }
                IconButton(systemName: "house.fill", size: 52, action: onQuit)
            }
        }
    }
}
