import SwiftUI

/// A wordless, hands-on tutorial. Each step is a small table with one goal: make the remainder line empty.
///
/// 1. Three cards, the hand shows each tap. The player watches dots appear in the line and cancel in pairs.
/// 2. Four cards, one is a decoy. The hand only appears if the player stalls.
/// 3. Five cards with a set of four (no set of three exists), so "sets aren't always three".
/// 4. A real seven-card deal.
@Observable @MainActor
final class TutorialModel {
    static let scripted: [[Int]] = [
        [3, 6, 5],              // {Y░ R●} {R● B░} {Y░ B░}
        [9, 36, 18, 27],        // 9 ^ 18 ^ 27 = 0, 36 is the decoy
        [11, 22, 13, 44, 49],   // 11 ^ 22 ^ 44 ^ 49 = 0, 13 is the decoy; no 3-card set
    ]
    static let stepCount = scripted.count + 1

    let table = Table(slotCount: 3, deck: [])
    private(set) var step = 0
    private(set) var selected: Set<Int> = []
    private(set) var hint: Int?
    private(set) var celebrating = false
    /// The cards of the set just made, glowing on the board before they're collected.
    private(set) var found: Set<Int> = []
    private(set) var isDone = false

    @ObservationIgnored private var hintTask: Task<Void, Never>?

    var parity: Int { CardMath.parity(selected) }

    func start() { load() }

    private func load() {
        let cards = step < Self.scripted.count
            ? Self.scripted[step]
            : Array(CardMath.deck().shuffled().prefix(7))
        selected = []
        let settle = table.replace(with: cards)
        scheduleHint(after: settle + (step == 0 ? 0.3 : 6))
    }

    func toggle(_ card: Int) {
        guard !celebrating else { return }
        if selected.contains(card) { selected.remove(card) } else { selected.insert(card) }
        if !selected.isEmpty && parity == 0 {
            complete()
        } else {
            // First step: guide every tap. Later: back off and only help after a pause.
            scheduleHint(after: step == 0 ? 0.35 : 6)
        }
    }

    private func complete() {
        hintTask?.cancel()
        hint = nil
        celebrating = true
        found = selected
        selected = []
        Task {
            try? await Task.sleep(for: .seconds(DeckGame.celebrationTime))
            table.collect(table.boardCards.filter(found.contains), refill: false)
            found = []
            try? await Task.sleep(for: .seconds(1.0))
            celebrating = false
            step += 1
            if step >= Self.stepCount {
                isDone = true
                table.replace(with: [])
            } else {
                load()
            }
        }
    }

    private func scheduleHint(after delay: Double) {
        hintTask?.cancel()
        if step > 0 { hint = nil }
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.spring(duration: 0.4)) { self.hint = self.nextHint() }
        }
    }

    /// Point at a wrongly selected card to undo it, otherwise at the next card of the nearest set.
    private func nextHint() -> Int? {
        let board = table.boardCards
        guard let target = CardMath.nearestSet(in: board, to: selected) else { return nil }
        let targetSet = Set(target)
        return board.first { selected.contains($0) && !targetSet.contains($0) }
            ?? board.first { targetSet.contains($0) && !selected.contains($0) }
    }
}

struct TutorialScreen: View {
    @State private var model = TutorialModel()
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.uiScale) private var s

    var body: some View {
        GeometryReader { geo in
            let layout = TableLayout(size: geo.size, slotCount: model.table.slots.count, scale: s)
            ZStack {
                CardTableView(table: model.table, layout: layout, selected: model.selected,
                              celebrating: model.found, showsCounts: false) {
                    model.toggle($0)
                }
                ParityCard(value: model.parity, height: layout.controlsHeight, success: !model.found.isEmpty)
                    .position(layout.controlsCenter)

                if let hint = model.hint, let index = model.table.slots.firstIndex(where: { $0?.number == hint }) {
                    TapHint(cardSize: layout.cardSize)
                        .position(layout.slotCenters[index])
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if model.celebrating && model.found.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 96 * s, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if model.isDone {
                    finale.transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                topBar
                    .frame(height: layout.topBarHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .animation(.spring(duration: 0.4, bounce: 0.4), value: model.celebrating)
        .animation(.spring(duration: 0.5), value: model.isDone)
        .sensoryFeedback(.selection, trigger: model.selected)
        .sensoryFeedback(.success, trigger: model.step)
        .onAppear { model.start() }
        .onDisappear { hasSeenTutorial = true }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack {
            IconButton(systemName: "xmark") { dismiss() }
            Spacer()
        }
        .padding(.horizontal, 16 * s)
        .overlay {
            HStack(spacing: 8 * s) {
                ForEach(0..<TutorialModel.stepCount, id: \.self) { i in
                    Circle()
                        .fill(i < model.step ? Palette.ink : (i == model.step ? Palette.ink.opacity(0.5) : Palette.faint))
                        .frame(width: (i == model.step ? 12 : 9) * s, height: (i == model.step ? 12 : 9) * s)
                }
            }
            .animation(.spring(duration: 0.3), value: model.step)
        }
    }

    private var finale: some View {
        VStack(spacing: 28 * s) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 88 * s, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .symbolEffect(.bounce, value: model.isDone)
            Button { dismiss() } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 34 * s, weight: .bold))
                    .foregroundStyle(Palette.paper)
                    .frame(width: 96 * s, height: 96 * s)
                    .background(Circle().fill(Palette.ink))
            }
        }
    }
}

/// A pulsing ring around the card plus a bobbing finger: "tap here".
private struct TapHint: View {
    let cardSize: CGSize
    @State private var pulse = false

    var body: some View {
        ZStack {
            CardShape()
                .strokeBorder(Palette.ink.opacity(pulse ? 0.15 : 0.6), lineWidth: 3)
                .frame(width: cardSize.width + 14, height: cardSize.height + 14)
                .scaleEffect(pulse ? 1.05 : 1)
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: cardSize.width * 0.42))
                .foregroundStyle(Palette.ink)
                .shadow(color: Palette.paper, radius: 0, x: 1.5, y: 1.5)
                .shadow(color: Palette.paper, radius: 0, x: -1.5, y: -1.5)
                .offset(x: cardSize.width * 0.28, y: cardSize.height * (pulse ? 0.28 : 0.36))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
