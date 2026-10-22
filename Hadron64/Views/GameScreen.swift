import SwiftUI

/// Free Play, Time Trial, and the Simple Cards drills.
struct GameScreen: View {
    let mode: GameMode
    @State private var game: DeckGame
    @State private var summary: ResultSummary?
    @State private var paused = false
    @Environment(StatsStore.self) private var stats
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(mode: GameMode) {
        self.mode = mode
        _game = State(initialValue: DeckGame(mode: mode))
    }

    var body: some View {
        GeometryReader { geo in
            let layout = TableLayout(size: geo.size, slotCount: game.table.slots.count)
            ZStack {
                CardTableView(table: game.table, layout: layout, selected: game.selected,
                              marked: game.hintIncluded, crossed: game.hintExcluded) { game.toggle($0) }
                RemainderBar(value: game.parity, mask: mode.dotMask)
                    .position(layout.controlsCenter)
                topBar
                    .frame(height: TableLayout.topBarHeight)
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
        .animation(.easeInOut(duration: 0.25), value: paused)
        .animation(.spring(duration: 0.4), value: summary?.id)
        .sensoryFeedback(.selection, trigger: game.selected)
        .sensoryFeedback(.success, trigger: game.setsFound)
        .onAppear {
            GameCenterService.shared.setAccessPointVisible(false)
            begin(game)
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
        .padding(.horizontal, 16)
        .overlay { ClockLabel(game: game) }
    }

    private func begin(_ g: DeckGame) {
        g.onFind = { stats.log($0) }
        g.onFinish = { record in summary = stats.log(record) }
        g.start()
    }

    private func replay() {
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

    var body: some View {
        Button { game.hint() } label: {
            ZStack {
                if game.hintLevel == 0 {
                    Image(systemName: "lightbulb.fill").font(.system(size: 17, weight: .bold))
                } else {
                    Text("\(game.hintSet.count)").font(.rounded(21, .heavy))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 44, height: 44)
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

    var body: some View {
        let remaining = game.timeRemaining
        let urgent = (remaining ?? .infinity) < 10
        Text(remaining?.countdownString ?? game.clock.elapsed.clockString)
            .font(.rounded(30).monospacedDigit())
            .foregroundStyle(urgent ? Palette.red : Palette.ink)
            .scaleEffect(urgent ? 1.08 : 1)
            .animation(.spring(duration: 0.3), value: urgent)
            .overlay(alignment: .trailing) {
                if let bonus = game.mode.timeTrial?.bonus, game.setsFound > 0 {
                    RiseAndFade(text: "+\(Int(bonus))")
                        .id(game.setsFound)
                        .offset(x: 48)
                }
            }
    }
}

/// Floats up and fades away once, each time it's (re)created.
struct RiseAndFade: View {
    let text: String
    @State private var gone = false

    var body: some View {
        Text(text)
            .font(.rounded(20, .bold))
            .foregroundStyle(Palette.blue)
            .fixedSize()
            .offset(y: gone ? -26 : 0)
            .opacity(gone ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.1)) { gone = true } }
    }
}

/// Hides the board while paused so the clock can't be gamed.
struct PauseOverlay: View {
    let onResume: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            VStack(spacing: 28) {
                Button(action: onResume) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Palette.paper)
                        .frame(width: 104, height: 104)
                        .background(Circle().fill(Palette.ink))
                }
                IconButton(systemName: "house.fill", size: 52, action: onQuit)
            }
        }
    }
}
