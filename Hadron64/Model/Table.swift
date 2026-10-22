import SwiftUI

/// One physical card on the table. `uid` gives each dealt card its own view identity, so the same
/// number can be dealt again (in training) while an earlier copy is still sitting in the collection stack.
struct PlacedCard: Identifiable, Hashable {
    let uid: Int
    let number: Int
    var id: Int { uid }
}

/// The physical state of the table: board slots, the deck, and the collection stack.
/// It owns the deal/collect animations; game rules live in the models that drive it.
@Observable @MainActor
final class Table {
    private(set) var slots: [PlacedCard?]
    /// Cards that have finished flying from the deck to their slot. Others are drawn on the deck.
    private(set) var arrived: Set<Int> = []
    /// The top of the collection stack (older cards are dropped — they're hidden underneath anyway).
    private(set) var stack: [PlacedCard] = []
    private(set) var collectedCount = 0
    private(set) var deck: [Int]

    @ObservationIgnored private var nextUID = 0
    @ObservationIgnored private var generation = 0

    static let stackDepth = 10
    static let dealStagger = 0.07
    static let flightTime = 0.45

    init(slotCount: Int, deck: [Int]) {
        slots = Array(repeating: nil, count: slotCount)
        self.deck = deck
    }

    var boardCards: [Int] { slots.compactMap { $0?.number } }
    var isCleared: Bool { deck.isEmpty && slots.allSatisfy { $0 == nil } }

    func isArrived(_ card: PlacedCard) -> Bool { arrived.contains(card.uid) }

    /// Roughly how long until `count` freshly dealt cards have all landed, after `delay`.
    static func settleTime(count: Int, delay: Double) -> Double {
        delay + Double(max(count - 1, 0)) * dealStagger + flightTime * 0.7
    }

    /// Fill empty slots from the deck. Cards appear on the deck immediately and fly out one by one.
    @discardableResult
    func deal(after delay: Double = 0) -> Double {
        var dealt: [PlacedCard] = []
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            for i in slots.indices where slots[i] == nil && !deck.isEmpty {
                let card = PlacedCard(uid: nextUID, number: deck.removeLast())
                nextUID += 1
                slots[i] = card
                dealt.append(card)
            }
        }
        let gen = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            for (i, card) in dealt.enumerated() {
                if i > 0 { try? await Task.sleep(for: .seconds(Self.dealStagger)) }
                guard let self, self.generation == gen else { return }
                withAnimation(.spring(duration: Self.flightTime, bounce: 0.18)) {
                    _ = self.arrived.insert(card.uid)
                }
            }
        }
        return Self.settleTime(count: dealt.count, delay: delay)
    }

    /// Sweep the given cards off the board into the collection stack, then refill from the deck.
    /// Returns when the refilled cards will have landed.
    @discardableResult
    func collect(_ numbers: [Int], refill: Bool = true) -> Double {
        withAnimation(.spring(duration: 0.5, bounce: 0.12)) {
            for i in slots.indices {
                guard let card = slots[i], numbers.contains(card.number) else { continue }
                slots[i] = nil
                arrived.remove(card.uid)
                stack.append(card)
                collectedCount += 1
            }
            if stack.count > Self.stackDepth { stack.removeFirst(stack.count - Self.stackDepth) }
        }
        return refill ? deal(after: 0.3) : 0
    }

    /// Replace what's left in the deck (endless drills choose their own next cards).
    func restock(_ numbers: [Int]) {
        deck = numbers
    }

    /// Training: sweep everything away and lay out a brand new hand (which may have a different size).
    @discardableResult
    func replace(with numbers: [Int]) -> Double {
        let hadCards = !boardCards.isEmpty
        collect(boardCards, refill: false)
        generation += 1
        let delay = hadCards ? 0.3 : 0.15
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            slots = Array(repeating: nil, count: numbers.count)
            deck = numbers.reversed()
        }
        return deal(after: delay)
    }
}
