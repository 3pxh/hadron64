import Foundation
import Observation
import StoreKit

/// The one in-app purchase: a non-consumable "supporter" unlock that lifts the daily limits on
/// training modes and multiplayer. Free Play, Time Trial and the tutorial are always unlimited.
///
/// Each training mode can be started `freePlaysPerDay` times per calendar day, Extra Hard
/// `freeExtraHardPerDay` times, multiplayer `freeMultiplayerPerDay` times. Nothing about the limit shows until a mode has used its plays;
/// tapping it again then offers the unlock.
@Observable @MainActor
final class Supporter {
    static let productID = "com.hoqqanen.hadron64.supporter"
    static let freePlaysPerDay = 3
    static let freeMultiplayerPerDay = 1
    static let freeExtraHardPerDay = 1

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
    /// Daily limits are off in Debug builds (run from Xcode) so development devices never hit them;
    /// pass `-debugLimits YES` to test them. Release builds (TestFlight, App Store) always enforce them.
    @ObservationIgnored private let enforcesLimits: Bool

    init(defaults: UserDefaults = .standard, enforcesLimits: Bool = Supporter.defaultEnforcesLimits) {
        self.defaults = defaults
        self.enforcesLimits = enforcesLimits
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

    nonisolated static var defaultEnforcesLimits: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "debugLimits")
        #else
        true
        #endif
    }

    /// Whether `session` can start now. Unlimited sessions are always allowed.
    func allows(_ session: Session) -> Bool {
        guard enforcesLimits, !isUnlocked else { return true }
        return session.limitKeys.allSatisfy { playsToday($0) < Self.freePlays(for: $0) }
    }

    private static func freePlays(for key: String) -> Int {
        switch key {
        case Session.multiplayerKey: freeMultiplayerPerDay
        case let key where GameMode(rawValue: key)?.base == .extraHard: freeExtraHardPerDay
        default: freePlaysPerDay
        }
    }

    /// The lock appears on a mode only once its plays for today are used up.
    func isLocked(_ session: Session) -> Bool { !allows(session) }

    /// Count one start of `session` toward today's allowance.
    func recordPlay(_ session: Session) {
        guard !session.limitKeys.isEmpty else { return }
        rollOverIfNeeded()
        for key in session.limitKeys { plays[key, default: 0] += 1 }
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
    static let multiplayerKey = "multiplayer"

    /// The daily allowances `self` draws on; empty for anything that's always free.
    /// Multiplayer in a training mode uses up a play of both.
    var limitKeys: [String] {
        switch self {
        case .game(let mode): mode.isTraining ? [mode.rawValue] : []
        case .remainder: [GameMode.remainder.rawValue]
        case .multiplayer(let mode): [Self.multiplayerKey] + Session.game(mode).limitKeys
        case .tutorial: []
        }
    }
}
