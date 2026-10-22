import Foundation
import Observation

/// A pausable stopwatch that publishes `elapsed` ~20 times a second.
/// Only views that read `elapsed` re-render on each tick.
@Observable @MainActor
final class GameClock {
    private(set) var elapsed: TimeInterval = 0
    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored var onTick: (() -> Void)?

    var isRunning: Bool { startedAt != nil }

    /// Exact time right now (not rounded to the last tick).
    var current: TimeInterval {
        accumulated + (startedAt.map { Date.now.timeIntervalSince($0) } ?? 0)
    }

    func start() {
        guard startedAt == nil else { return }
        startedAt = .now
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                self.elapsed = self.current
                self.onTick?()
            }
        }
    }

    func pause() {
        guard startedAt != nil else { return }
        accumulated = current
        elapsed = accumulated
        startedAt = nil
        ticker?.cancel()
        ticker = nil
    }

    func reset() {
        pause()
        accumulated = 0
        elapsed = 0
    }
}

extension TimeInterval {
    /// 75.3 -> "1:15"
    var clockString: String {
        let s = Int(self.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// For countdowns: 0.2s left still shows "0:01".
    var countdownString: String {
        let s = Int(self.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// 4.25 -> "4.3s", 75 -> "1:15"
    var shortString: String {
        self < 60 ? String(format: "%.1fs", self) : clockString
    }
}
