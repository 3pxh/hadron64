import SwiftUI

/// Pass-and-play for up to four people around one phone lying flat on the table.
/// Anyone can tap cards; when a set is collected it waits in the middle until it's slid toward
/// the edge of whoever found it, which credits that player with the set and its cards.
struct MultiplayerScreen: View {
    @State private var game = DeckGame(mode: .freePlay)
    @State private var scores: [Seat: Score] = [:]
    /// The collected set waiting to be claimed. The board is blocked until it is.
    @State private var pending: [Int]?
    @State private var drag: CGSize = .zero
    @State private var showsUnlock = false
    @Environment(Supporter.self) private var supporter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.uiScale) private var s

    /// Thickness of the score strips along each edge.
    private var strip: (side: CGFloat, end: CGFloat) { (40 * s, 52 * s) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let inner = CGSize(width: size.width - 2 * strip.side, height: size.height - 2 * strip.end)
            let layout = TableLayout(size: inner, slotCount: game.table.slots.count, scale: s)
            ZStack {
                ZStack {
                    CardTableView(table: game.table, layout: layout, selected: game.selected,
                                  celebrating: game.celebrating, showsCounts: false) { game.toggle($0) }
                        .allowsHitTesting(pending == nil)
                    ParityCard(value: game.parity, height: layout.controlsHeight, success: !game.celebrating.isEmpty)
                        .position(layout.controlsCenter)
                    IconButton(systemName: "xmark") { dismiss() }
                        .position(x: 30 * s, y: layout.topBarHeight / 2)
                }
                .frame(width: inner.width, height: inner.height)
                .position(x: size.width / 2, y: size.height / 2)

                if pending != nil {
                    Palette.paper.opacity(0.45)
                }

                // Above the dimming, so the players can see where the set is going.
                ForEach(Seat.allCases) { seat in
                    badge(seat, size: size)
                }

                if let pending {
                    claim(pending, size: size)
                        .position(x: size.width / 2, y: size.height / 2)
                }

                if game.isFinished && pending == nil {
                    results.transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        // Seats are physical edges of the phone, so left and right must not swap in right-to-left languages.
        .fixedCardLayout()
        .background(Palette.paper.ignoresSafeArea())
        .statusBarHidden()
        .onAppear {
            begin(game)
            #if DEBUG
            Task { await stage(game) }
            #endif
        }
        .sheet(isPresented: $showsUnlock) { SupportView(reason: .dailyLimit) }
        .animation(.spring(duration: 0.35), value: pending)
        .animation(.spring(duration: 0.4), value: game.isFinished)
        .sensoryFeedback(.selection, trigger: game.selected)
        .sensoryFeedback(.success, trigger: game.setsFound)
    }

    private func begin(_ g: DeckGame) {
        g.onFind = { event in pending = event.cards }
        g.start()
    }

    #if DEBUG
    /// Screenshot staging (`-debugFinds N`): find N sets and hand them around the table,
    /// then find one more and leave it waiting to be claimed.
    private func stage(_ g: DeckGame) async {
        let finds = UserDefaults.standard.integer(forKey: "debugFinds")
        guard finds > 0 else { return }
        let seats: [Seat] = [.bottom, .top, .right, .bottom, .left, .top, .bottom, .right]
        try? await Task.sleep(for: .seconds(1.2))
        for i in 0...finds {
            guard let set = CardMath.allSets(in: g.table.boardCards).min(by: { $0.count < $1.count }) else { return }
            set.forEach(g.toggle)
            try? await Task.sleep(for: .seconds(DeckGame.celebrationTime + 0.8))
            if i < finds { award(seats[i % seats.count], cards: set, size: CGSize(width: 800, height: 800)) }
            try? await Task.sleep(for: .seconds(0.6))
        }
    }
    #endif

    private func replay() {
        guard supporter.allows(.multiplayer) else { showsUnlock = true; return }
        supporter.recordPlay(.multiplayer)
        let next = DeckGame(mode: .freePlay)
        scores = [:]
        pending = nil
        game = next
        begin(next)
    }

    // MARK: Claiming a set

    private func claim(_ cards: [Int], size: CGSize) -> some View {
        let w: CGFloat = 96 * s
        return VStack(spacing: 20 * s) {
            ZStack {
                ForEach(Array(cards.enumerated()), id: \.offset) { i, n in
                    let mid = Double(cards.count - 1) / 2
                    CardView(number: n)
                        .frame(width: w, height: w / CardGeometry.aspect)
                        .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                        .rotationEffect(.degrees((Double(i) - mid) * 9), anchor: .bottom)
                        .offset(x: (CGFloat(i) - CGFloat(mid)) * 22 * s)
                }
            }
            .padding(36 * s)
            .overlay {
                ForEach(Seat.allCases) { seat in
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 26 * s, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .rotationEffect(.degrees(seat.rotation))
                        .offset(seat.unit * 150 * s)
                        .opacity(drag == .zero ? 0.8 : 0)
                }
            }
            .offset(drag)
            .gesture(
                DragGesture()
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        if let seat = Seat.toward(value.predictedEndTranslation) {
                            award(seat, cards: cards, size: size)
                        } else {
                            withAnimation(.spring(duration: 0.3)) { drag = .zero }
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Found set")
            .accessibilityActions {
                ForEach(Seat.allCases) { seat in
                    Button(seat.giveLabel) { award(seat, cards: cards, size: size) }
                }
            }
        }
    }

    private func award(_ seat: Seat, cards: [Int], size: CGSize) {
        withAnimation(.easeIn(duration: 0.22)) {
            drag = CGSize(width: seat.unit.width * size.width, height: seat.unit.height * size.height)
        }
        Task {
            try? await Task.sleep(for: .seconds(0.22))
            scores[seat, default: Score()].sets += 1
            scores[seat, default: Score()].cards += cards.count
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { drag = .zero }
            pending = nil
        }
    }

    // MARK: Scores

    /// A score strip along `seat`'s edge, turned to face the person sitting there.
    private func badge(_ seat: Seat, size: CGSize) -> some View {
        let score = scores[seat] ?? Score()
        let along = seat.isSide ? size.height : size.width
        let across = seat.isSide ? strip.side : strip.end
        let target = pending != nil && Seat.toward(drag, threshold: 40) == seat
        let leader = game.isFinished && pending == nil && isWinner(seat)
        return HStack(spacing: 14 * s) {
            if leader { Image(systemName: "crown.fill").foregroundStyle(Palette.yellow) }
            Text("\(score.sets) sets", comment: "Multiplayer score: sets collected")
            Text("\(score.cards) cards", comment: "Multiplayer score: cards collected").foregroundStyle(Palette.muted)
        }
        .font(.rounded(16 * s, .bold).monospacedDigit())
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 16 * s)
        .frame(height: across - 12 * s)
        .background(Capsule().fill(target ? Palette.yellow.opacity(0.45) : Palette.card))
        .overlay(Capsule().strokeBorder(target ? Palette.yellow : Palette.ink.opacity(0.12), lineWidth: target ? 2 : 1))
        .scaleEffect(target ? 1.08 : 1)
        .animation(.spring(duration: 0.2), value: target)
        .frame(width: along, height: across)
        .rotationEffect(.degrees(seat.rotation))
        .position(x: size.width / 2 + seat.unit.width * (size.width - across) / 2,
                  y: size.height / 2 + seat.unit.height * (size.height - across) / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(seat.name): \(String(localized: "\(score.sets) sets")), \(String(localized: "\(score.cards) cards"))",
                                 comment: "Multiplayer score for one player, e.g. Bottom player: 2 sets, 7 cards"))
    }

    private func isWinner(_ seat: Seat) -> Bool {
        let best = scores.values.map(\.cards).max() ?? 0
        return best > 0 && scores[seat]?.cards == best
    }

    private var results: some View {
        VStack(spacing: 18 * s) {
            Image(systemName: "crown.fill")
                .font(.system(size: 40 * s, weight: .semibold))
                .foregroundStyle(Palette.yellow)
            Text("DECK CLEARED")
                .font(.rounded(13 * s, .bold))
                .tracking(2)
                .foregroundStyle(Palette.muted)
            HStack(spacing: 12 * s) {
                Button(action: replay) { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(MenuButtonStyle(filled: true))
                Button { dismiss() } label: { Image(systemName: "house.fill") }
                    .buttonStyle(MenuButtonStyle())
            }
            .frame(width: 200 * s)
        }
        .padding(28 * s)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.paper))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.ink.opacity(0.12)))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

/// The four edges of the phone, one per player.
enum Seat: Int, CaseIterable, Identifiable {
    case bottom, right, top, left
    var id: Int { rawValue }

    var name: String {
        switch self {
        case .bottom: String(localized: "Bottom player")
        case .right: String(localized: "Right player")
        case .top: String(localized: "Top player")
        case .left: String(localized: "Left player")
        }
    }

    var giveLabel: String {
        switch self {
        case .bottom: String(localized: "Give to bottom player")
        case .right: String(localized: "Give to right player")
        case .top: String(localized: "Give to top player")
        case .left: String(localized: "Give to left player")
        }
    }

    var isSide: Bool { self == .left || self == .right }

    /// Outward direction from the center of the screen.
    var unit: CGSize {
        switch self {
        case .bottom: CGSize(width: 0, height: 1)
        case .right: CGSize(width: 1, height: 0)
        case .top: CGSize(width: 0, height: -1)
        case .left: CGSize(width: -1, height: 0)
        }
    }

    /// Turns content so its bottom edge faces this seat.
    var rotation: Double {
        switch self {
        case .bottom: 0
        case .right: -90
        case .top: 180
        case .left: 90
        }
    }

    /// The seat a drag is heading for, by its dominant direction.
    static func toward(_ t: CGSize, threshold: CGFloat = 90) -> Seat? {
        guard max(abs(t.width), abs(t.height)) > threshold else { return nil }
        if abs(t.width) > abs(t.height) { return t.width > 0 ? .right : .left }
        return t.height > 0 ? .bottom : .top
    }
}

struct Score: Hashable {
    var sets = 0
    var cards = 0
}

private func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
    CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
}
