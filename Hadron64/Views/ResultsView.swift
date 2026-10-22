import SwiftUI

/// End-of-game card: this run's result, best, average, and a "new record" badge.
struct ResultsView: View {
    let summary: ResultSummary
    let onReplay: () -> Void
    let onHome: () -> Void

    private var record: GameRecord { summary.record }
    private var isTimeTrial: Bool { record.mode.isTimeTrial }

    var body: some View {
        ZStack {
            Palette.paper.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: headlineIcon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(summary.isNewRecord ? Palette.yellow : Palette.ink)
                    .symbolEffect(.bounce, value: summary.id)

                Text(record.mode.title.uppercased())
                    .font(.rounded(13, .bold))
                    .tracking(2)
                    .foregroundStyle(Palette.muted)

                Text(format(record.score))
                    .font(.rounded(64, .bold).monospacedDigit())
                    .foregroundStyle(Palette.ink)

                if record.usedHints {
                    Label("\(record.hintsUsed ?? 0)", systemImage: "lightbulb.fill")
                        .font(.rounded(16, .bold))
                        .foregroundStyle(Palette.muted)
                }

                if summary.isNewRecord {
                    Label("New Record", systemImage: "star.fill")
                        .font(.rounded(16, .bold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Palette.yellow.opacity(0.35)))
                }

                HStack(spacing: 12) {
                    stat("Best", icon: "crown.fill", value: summary.best)
                    stat("Average", icon: "chart.line.uptrend.xyaxis", value: summary.average)
                    statTile("Sets", icon: "square.stack.3d.up.fill", text: "\(record.setsFound)")
                }

                HStack(spacing: 20) {
                    IconButton(systemName: "house.fill", size: 60, action: onHome)
                    Button(action: onReplay) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Palette.paper)
                            .frame(width: 76, height: 76)
                            .background(Circle().fill(Palette.ink))
                    }
                }
                .padding(.top, 8)
            }
            .padding(28)
            .frame(maxWidth: 380)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Palette.card))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
            .padding(20)
        }
    }

    private var headlineIcon: String {
        if summary.isNewRecord { return "trophy.fill" }
        return record.completed ? "flag.checkered" : "hourglass.bottomhalf.filled"
    }

    private func format(_ score: Double) -> String {
        isTimeTrial ? "\(Int(score))" : score.clockString
    }

    private func stat(_ title: String, icon: String, value: Double?) -> some View {
        statTile(title, icon: icon, text: value.map(format) ?? "–")
    }

    private func statTile(_ title: String, icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.muted)
            Text(text).font(.rounded(20, .bold).monospacedDigit()).foregroundStyle(Palette.ink)
            Text(title).font(.rounded(12, .medium)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.paper))
    }
}
