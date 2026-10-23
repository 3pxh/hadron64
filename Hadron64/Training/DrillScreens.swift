import SwiftUI

/// Common chrome for the endless drills: close button, solved count, average time, pause on background.
private struct DrillScaffold<Content: View>: View {
    let drill: Drill
    /// Height reserved for the controls under the board, before scaling.
    var controls: CGFloat = 80
    /// Reserve room for the deck and stack piles.
    var piles = true
    @ViewBuilder let content: (TableLayout) -> Content
    @State private var paused = false
    @Environment(StatsStore.self) private var stats
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.uiScale) private var s

    var body: some View {
        GeometryReader { geo in
            let layout = TableLayout(size: geo.size, slotCount: drill.table.slots.count, scale: s, controls: controls,
                                     piles: piles)
            ZStack {
                content(layout)
                topBar
                    .frame(height: layout.topBarHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .overlay {
            if paused {
                PauseOverlay(onResume: { paused = false; drill.resume() }, onQuit: { dismiss() })
            }
        }
        .sensoryFeedback(.success, trigger: drill.solved)
        .onAppear {
            drill.onFind = { stats.log($0) }
            drill.start()
        }
        .onDisappear { drill.pause() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { drill.pause(); paused = true }
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack(spacing: 18 * s) {
            IconButton(systemName: "xmark") { dismiss() }
            Spacer()
            Label("\(drill.solved)", systemImage: "checkmark")
                .contentTransition(.numericText())
                .animation(.default, value: drill.solved)
            Label(drill.averageTime?.shortString ?? "–", systemImage: "stopwatch")
        }
        .font(.rounded(18 * s).monospacedDigit())
        .foregroundStyle(Palette.ink)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 16 * s)
    }
}

struct RemainderDrillScreen: View {
    @State private var drill = RemainderDrill()

    var body: some View {
        // A taller hexagon than in play, so its dots make comfortable buttons. It leaves a margin in its space for
        // picked dots, which grow and get a ring.
        DrillScaffold(drill: drill, controls: 150, piles: false) { layout in
            CardTableView(table: drill.table, layout: layout, showsCounts: false, showsStack: false, showsDeck: false)
            ParityHex(value: drill.guess, height: layout.controlsHeight * 0.82, success: drill.isResolving) {
                drill.toggle($0)
            }
                .position(layout.controlsCenter)
        }
        .sensoryFeedback(.selection, trigger: drill.guess)
        #if DEBUG
        .task {
            // Screenshot staging (`-debugSelect N`): enter up to N of the odd dots, always leaving one to go.
            let n = UserDefaults.standard.integer(forKey: "debugSelect")
            guard n > 0 else { return }
            try? await Task.sleep(for: .seconds(1.5))
            let odd = Dot.readingOrder.filter { drill.answer & $0.bit != 0 }
            for dot in odd.prefix(min(n, odd.count - 1)) { drill.toggle(dot) }
        }
        #endif
    }
}
