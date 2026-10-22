import Foundation
import Observation
import StoreKit

/// The one in-app purchase: a non-consumable "supporter" unlock that lifts the daily limits on
/// training modes and multiplayer. Free Play, Time Trial and the tutorial are always unlimited.
///
/// Each training mode can be started `freePlaysPerDay` times per calendar day, multiplayer
/// `freeMultiplayerPerDay` times. Nothing about the limit shows until a mode has used its plays;
/// tapping it again then offers the unlock.
@Observable @MainActor
final class Supporter {
    static let productID = "com.hoqqanen.hadron64.supporter"
    static let freePlaysPerDay = 3
    static let freeMultiplayerPerDay = 1

    private(set) var product: Product?
    private(set) var isUnlocked = false
    private(set) var isPurchasing = false
    private(set) var loadFailed = false
    var errorMessage: String?

    /// Plays per limited mode today. Reset lazily when the day changes.
    private(set) var plays: [String: Int]
    @ObservationIgnored private var playsDay: Date
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updates: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        plays = defaults.dictionary(forKey: "trainingPlays") as? [String: Int] ?? [:]
        playsDay = defaults.object(forKey: "trainingPlaysDay") as? Date ?? .distantPast
        #if DEBUG
        if defaults.bool(forKey: "debugSupporter") { isUnlocked = true }
        #endif
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates { await self?.handle(result) }
        }
        Task { await refresh() }
    }

    // MARK: Daily allowance

    /// Whether `session` can start now. Unlimited sessions are always allowed.
    func allows(_ session: Session) -> Bool {
        guard let key = session.limitKey, !isUnlocked else { return true }
        let free = session == .multiplayer ? Self.freeMultiplayerPerDay : Self.freePlaysPerDay
        return playsToday(key) < free
    }

    /// The lock appears on a mode only once its plays for today are used up.
    func isLocked(_ session: Session) -> Bool { !allows(session) }

    /// Count one start of `session` toward today's allowance.
    func recordPlay(_ session: Session) {
        guard let key = session.limitKey else { return }
        rollOverIfNeeded()
        plays[key, default: 0] += 1
        defaults.set(plays, forKey: "trainingPlays")
        defaults.set(playsDay, forKey: "trainingPlaysDay")
    }

    private func playsToday(_ key: String) -> Int {
        Calendar.current.isDateInToday(playsDay) ? plays[key] ?? 0 : 0
    }

    private func rollOverIfNeeded() {
        guard !Calendar.current.isDateInToday(playsDay) else { return }
        playsDay = Calendar.current.startOfDay(for: .now)
        plays = [:]
    }

    // MARK: StoreKit

    func refresh() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
            loadFailed = product == nil
        } catch {
            loadFailed = true
        }
        var owned = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil { owned = true }
        }
        #if DEBUG
        if defaults.bool(forKey: "debugSupporter") { owned = true }
        #endif
        isUnlocked = owned
    }

    func purchase() async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result): await handle(result)
            case .pending, .userCancelled: break
            @unknown default: break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let t) = result else { return }
        if t.productID == Self.productID { isUnlocked = t.revocationDate == nil }
        await t.finish()
    }
}

extension Session {
    /// Identifies a limited mode for the daily allowance; nil for anything that's always free.
    var limitKey: String? {
        switch self {
        case .game(let mode): mode.isTraining ? mode.rawValue : nil
        case .remainder: GameMode.remainder.rawValue
        case .remainderMatch: GameMode.remainderMatch.rawValue
        case .setSize: GameMode.setSize.rawValue
        case .multiplayer: "multiplayer"
        case .tutorial: nil
        }
    }
}
