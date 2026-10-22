import SwiftUI

/// Common chrome for the endless drills: close button, solved count, average time, pause on background.
private struct DrillScaffold<Content: View>: View {
    let drill: Drill
    @ViewBuilder let content: (TableLayout) -> Content
    @State private var paused = false
    @Environment(StatsStore.self) private var stats
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.uiScale) private var s

    var body: some View {
        GeometryReader { geo in
            let layout = TableLayout(size: geo.size, slotCount: drill.table.slots.count, scale: s)
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
        DrillScaffold(drill: drill) { layout in
            CardTableView(table: drill.table, layout: layout, showsCounts: false)
            RemainderBar(value: drill.guess, dotSize: 40 * layout.scale) { drill.toggle($0) }
                .scaleEffect(drill.isResolving ? 1.12 : 1)
                .animation(.spring(duration: 0.3, bounce: 0.5), value: drill.isResolving)
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

struct SetSizeDrillScreen: View {
    @State private var drill = SetSizeDrill()

    var body: some View {
        DrillScaffold(drill: drill) { layout in
            CardTableView(table: drill.table, layout: layout,
                          highlighted: drill.revealed ? Set(drill.answerSet) : [],
                          showsCounts: false)
            HStack(spacing: 10 * layout.scale) {
                ForEach(3...7, id: \.self) { n in sizeButton(n, scale: layout.scale) }
            }
            .position(layout.controlsCenter)
        }
        .sensoryFeedback(.error, trigger: drill.misses)
    }

    private func sizeButton(_ n: Int, scale s: CGFloat) -> some View {
        let isAnswer = drill.revealed && n == drill.answerSet.count
        let isMiss = drill.lastMiss == n
        return Button { drill.guess(n) } label: {
            Text("\(n)")
                .font(.rounded(22 * s, .bold))
                .frame(width: 50 * s, height: 50 * s)
                .foregroundStyle(isAnswer ? Palette.paper : Palette.ink)
                .background(Circle().fill(isAnswer ? Palette.ink : Palette.card))
                .overlay(Circle().strokeBorder(isMiss ? Palette.red : Palette.ink, lineWidth: 2))
                .opacity(isMiss ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .phaseAnimator([0, 10, -8, 5, 0], trigger: isMiss ? drill.misses : 0) { view, x in
            view.offset(x: isMiss ? x : 0)
        } animation: { _ in .linear(duration: 0.06) }
        .animation(.spring(duration: 0.25), value: isAnswer)
    }
}

struct RemainderMatchScreen: View {
    @State private var drill = RemainderMatchDrill()

    var body: some View {
        DrillScaffold(drill: drill) { layout in
            CardTableView(table: drill.table, layout: layout,
                          selected: drill.selected, marked: drill.locked,
                          showsCounts: false) { drill.toggle($0) }
            HStack(spacing: 14 * layout.scale) {
                lockButton(scale: layout.scale)
                RemainderBar(value: drill.parity, dotSize: 26 * layout.scale)
            }
            .scaleEffect(drill.isResolving ? 1.08 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.5), value: drill.isResolving)
            .position(layout.controlsCenter)
        }
        .sensoryFeedback(.selection, trigger: drill.selected)
        .sensoryFeedback(.impact, trigger: drill.locked)
        .sensoryFeedback(.error, trigger: drill.mismatchPulse)
    }

    /// Unlocked: a lock that lights up yellow when the current group qualifies.
    /// Locked: shows the remainder to match.
    private func lockButton(scale s: CGFloat) -> some View {
        let isLocked = !drill.locked.isEmpty
        return Button { drill.toggleLock() } label: {
            HStack(spacing: 6 * s) {
                Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 16 * s, weight: .bold))
                if isLocked {
                    RemainderBar(value: drill.lockedRemainder, mask: CardMath.yellowMask, dotSize: 18 * s)
                }
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12 * s)
            .frame(minWidth: 48 * s, minHeight: 48 * s)
            .background(Capsule().fill(drill.canLock || isLocked ? Palette.yellow.opacity(0.45) : Palette.card))
            .overlay(Capsule().strokeBorder(drill.canLock || isLocked ? Palette.yellow : Palette.faint, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .phaseAnimator([0, 8, -6, 4, 0], trigger: drill.mismatchPulse) { view, x in
            view.offset(x: x)
        } animation: { _ in .linear(duration: 0.06) }
        .animation(.spring(duration: 0.25), value: drill.canLock)
        .animation(.spring(duration: 0.25), value: isLocked)
    }
}
