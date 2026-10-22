import SwiftUI

/// End-of-game card: this run's result, best, average, and a "new record" badge.
struct ResultsView: View {
    let summary: ResultSummary
    let onReplay: () -> Void
    let onHome: () -> Void

    @Environment(\.uiScale) private var s
    /// Today's rank among Game Center friends, once the score has landed.
    @State private var friendsRank: (rank: Int, of: Int)?

    private var record: GameRecord { summary.record }
    private var isTimeTrial: Bool { record.mode.isTimeTrial }

    var body: some View {
        ZStack {
            Palette.paper.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 22 * s) {
                Image(systemName: headlineIcon)
                    .font(.system(size: 44 * s, weight: .semibold))
                    .foregroundStyle(summary.isNewRecord ? Palette.yellow : Palette.ink)
                    .symbolEffect(.bounce, value: summary.id)

                Text(record.mode.title.uppercased(with: .current))
                    .font(.rounded(13 * s, .bold))
                    .tracking(2)
                    .foregroundStyle(Palette.muted)

                Text(format(record.score))
                    .font(.rounded(64 * s, .bold).monospacedDigit())
                    .foregroundStyle(Palette.ink)

                if record.usedHints {
                    Label("\(record.hintsUsed ?? 0)", systemImage: "lightbulb.fill")
                        .font(.rounded(16 * s, .bold))
                        .foregroundStyle(Palette.muted)
                }

                if summary.isNewRecord {
                    Label("New Record", systemImage: "star.fill")
                        .font(.rounded(16 * s, .bold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14 * s).padding(.vertical, 6 * s)
                        .background(Capsule().fill(Palette.yellow.opacity(0.35)))
                }

                if let friendsRank {
                    Label("\(ordinal(friendsRank.rank)) of \(friendsRank.of) friends today",
                          systemImage: "person.2.fill")
                        .font(.rounded(15 * s, .semibold))
                        .foregroundStyle(Palette.muted)
                        .transition(.opacity)
                }

                HStack(spacing: 12 * s) {
                    stat("Best", icon: "crown.fill", value: summary.best)
                    stat("Average", icon: "chart.line.uptrend.xyaxis", value: summary.average)
                    statTile("Sets", icon: "square.stack.3d.up.fill", text: "\(record.setsFound)")
                }

                HStack(spacing: 20 * s) {
                    IconButton(systemName: "house.fill", size: 60, action: onHome)
                    Button(action: onReplay) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 26 * s, weight: .bold))
                            .foregroundStyle(Palette.paper)
                            .frame(width: 76 * s, height: 76 * s)
                            .background(Circle().fill(Palette.ink))
                    }
                }
                .padding(.top, 8 * s)
            }
            .padding(28 * s)
            .frame(maxWidth: 380 * s)
            .background(RoundedRectangle(cornerRadius: 28 * s, style: .continuous).fill(Palette.card))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
            .padding(20)
            .animation(.easeInOut, value: friendsRank?.rank)
        }
        .task(id: summary.id) {
            friendsRank = await GameCenterService.shared.dailyFriendsRank(after: record)
        }
    }

    private var headlineIcon: String {
        if summary.isNewRecord { return "trophy.fill" }
        return record.completed ? "flag.checkered" : "hourglass.bottomhalf.filled"
    }

    private func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: n as NSNumber) ?? "\(n)"
    }

    private func format(_ score: Double) -> String {
        isTimeTrial ? "\(Int(score))" : score.clockString
    }

    private func stat(_ title: LocalizedStringKey, icon: String, value: Double?) -> some View {
        statTile(title, icon: icon, text: value.map(format) ?? "–")
    }

    private func statTile(_ title: LocalizedStringKey, icon: String, text: String) -> some View {
        VStack(spacing: 4 * s) {
            Image(systemName: icon).font(.system(size: 14 * s, weight: .semibold)).foregroundStyle(Palette.muted)
            Text(text).font(.rounded(20 * s, .bold).monospacedDigit()).foregroundStyle(Palette.ink)
            Text(title).font(.rounded(12 * s, .medium)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10 * s)
        .background(RoundedRectangle(cornerRadius: 14 * s, style: .continuous).fill(Palette.paper))
    }
}
