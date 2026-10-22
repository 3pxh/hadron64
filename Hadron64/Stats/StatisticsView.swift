import SwiftUI
import Charts

struct StatisticsView: View {
    @Environment(StatsStore.self) private var stats
    @State private var mode: GameMode = .freePlay
    /// 0 = all set sizes.
    @State private var setSize = 0
    @State private var span: Span = .month

    enum Span: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90, year = 365
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week: "7D"
            case .month: "30D"
            case .quarter: "90D"
            case .year: "1Y"
            }
        }
    }

    var body: some View {
        let events = stats.events(for: mode)
        let games = stats.scoredGames(for: mode)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                modePicker
                tiles(events: events, games: games)
                histogramCard(events: events)
                trendCard(events: events, games: games)
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("Statistics")
        .onChange(of: mode) { _, new in
            if !new.possibleSetSizes.contains(setSize) { setSize = 0 }
        }
    }

    // MARK: Controls

    private var modePicker: some View {
        Menu {
            Picker("Mode", selection: $mode) {
                ForEach(GameMode.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            HStack {
                Text(mode.title).font(.rounded(20, .bold))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Palette.ink)
        }
    }

    // MARK: Summary tiles

    private func tiles(events: [FindEvent], games: [GameRecord]) -> some View {
        let format: (Double) -> String = { mode.isTimeTrial ? "\(Int($0.rounded()))" : $0.clockString }
        let findTimes = events.map(\.duration).sorted()
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
            if mode.isDeckMode {
                tile(mode.isTimeTrial ? "Best cards" : "Best deck", stats.best(for: mode).map(format))
                tile(mode.isTimeTrial ? "Avg cards" : "Avg deck", stats.average(for: mode).map(format))
                tile("Games", "\(games.count)")
            }
            tile(mode.isDeckMode ? "Sets" : "Rounds", "\(events.count)")
            tile("Median", findTimes.isEmpty ? nil : findTimes[findTimes.count / 2].shortString)
            tile("Fastest", findTimes.first?.shortString)
        }
    }

    private func tile(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value ?? "–").font(.rounded(22, .bold).monospacedDigit()).foregroundStyle(Palette.ink)
            Text(title).font(.rounded(12, .medium)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
    }

    // MARK: Histogram

    private func histogramCard(events: [FindEvent]) -> some View {
        let filtered = setSize == 0 ? events : events.filter { $0.size == setSize }
        let bins = Histogram.bins(filtered.map(\.duration))
        let median = filtered.map(\.duration).sorted().dropFirst(filtered.count / 2).first
        return card(title: mode == .remainder ? "Time to find the remainder" : "Time to find a set") {
            if mode.possibleSetSizes.count > 1 {
                Picker("Set size", selection: $setSize) {
                    Text("All").tag(0)
                    ForEach(Array(mode.possibleSetSizes), id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if bins.isEmpty {
                empty
            } else {
                histogramChart(bins, median: median)
                Text("Last bar includes everything slower.")
                    .font(.rounded(11)).foregroundStyle(Palette.muted)
            }
        }
    }

    private func histogramChart(_ bins: [Histogram.Bin], median: Double?) -> some View {
        Chart {
            ForEach(bins) { (bin: Histogram.Bin) in
                RectangleMark(xStart: .value("From", bin.barStart),
                        xEnd: .value("To", bin.barEnd),
                        yStart: .value("Zero", 0.0),
                        yEnd: .value("Finds", Double(bin.count)))
                    .foregroundStyle(Palette.blue)
                    .cornerRadius(3)
            }
            if let median {
                RuleMark(x: .value("Median", median))
                    .foregroundStyle(Palette.ink)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("median \(median.shortString)")
                            .font(.rounded(11, .medium)).foregroundStyle(Palette.ink)
                    }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Palette.faint)
                AxisValueLabel { if let s = value.as(Double.self) { Text(s.shortString) } }
            }
        }
        .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Palette.faint); AxisValueLabel() } }
        .frame(height: 200)
    }

    // MARK: Trend

    private func trendCard(events: [FindEvent], games: [GameRecord]) -> some View {
        let start = Calendar.current.date(byAdding: .day, value: -(span.rawValue - 1),
                                          to: Calendar.current.startOfDay(for: .now))!
        let gameSeries = Daily.averages(games.filter { $0.date >= start }.map { ($0.date, $0.score) })
        let findSeries = Daily.averages(events.filter { $0.date >= start }.map { ($0.date, $0.duration) })
        return card(title: "Trend") {
            Picker("Range", selection: $span) {
                ForEach(Span.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            // Two separate charts rather than one dual-axis chart: deck times (minutes) and find times (seconds)
            // live on very different scales.
            if mode.isDeckMode {
                Text(mode.isTimeTrial ? "Average cards per game" : "Average deck time")
                    .font(.rounded(13, .semibold)).foregroundStyle(Palette.muted)
                trendChart(gameSeries, start: start, color: Palette.ink,
                           label: { mode.isTimeTrial ? "\(Int($0.rounded()))" : $0.clockString })
            }
            Text(mode == .remainder ? "Average remainder time" : "Average set time")
                .font(.rounded(13, .semibold)).foregroundStyle(Palette.muted)
            trendChart(findSeries, start: start, color: Palette.red, label: { $0.shortString })
        }
    }

    @ViewBuilder
    private func trendChart(_ points: [Daily.Point], start: Date, color: Color, label: @escaping (Double) -> String) -> some View {
        if points.isEmpty {
            empty
        } else {
            Chart(points) { p in
                LineMark(x: .value("Day", p.day, unit: .day), y: .value("Average", p.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Day", p.day, unit: .day), y: .value("Average", p.value))
                    .foregroundStyle(color)
                    .symbolSize(40)
            }
            .chartXScale(domain: start...Date.now)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Palette.faint)
                    AxisValueLabel { if let v = value.as(Double.self) { Text(label(v)) } }
                }
            }
            .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Palette.faint); AxisValueLabel() } }
            .frame(height: 160)
        }
    }

    // MARK: Pieces

    private var empty: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 26))
                Text("No data yet").font(.rounded(13, .medium))
            }
            .foregroundStyle(Palette.muted)
            Spacer()
        }
        .frame(height: 120)
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.rounded(17, .bold)).foregroundStyle(Palette.ink)
            content()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.card))
    }
}

enum Histogram {
    struct Bin: Identifiable {
        let lower: Double
        let upper: Double
        let count: Int
        var id: Double { lower }
        /// Bar edges, inset slightly so neighbouring bars don't touch.
        var barStart: Double { lower + (upper - lower) * 0.06 }
        var barEnd: Double { upper - (upper - lower) * 0.06 }
    }

    /// Bins up to the 95th percentile with a "nice" step; slower outliers pile into the last bin.
    static func bins(_ values: [Double]) -> [Bin] {
        guard !values.isEmpty else { return [] }
        let sorted = values.sorted()
        let p95 = max(sorted[Int(Double(sorted.count - 1) * 0.95)], 0.5)
        let steps: [Double] = [0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300]
        let step = steps.first { $0 >= p95 / 14 } ?? 600
        let count = max(1, Int((p95 / step).rounded(.up)))
        var counts = Array(repeating: 0, count: count)
        for v in values { counts[min(max(Int(v / step), 0), count - 1)] += 1 }
        return counts.enumerated().map { Bin(lower: Double($0) * step, upper: Double($0 + 1) * step, count: $1) }
    }
}

enum Daily {
    struct Point: Identifiable {
        let day: Date
        let value: Double
        var id: Date { day }
    }

    static func averages(_ samples: [(Date, Double)]) -> [Point] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.0) }
        return grouped
            .map { day, items in Point(day: day, value: items.map(\.1).reduce(0, +) / Double(items.count)) }
            .sorted { $0.day < $1.day }
    }
}
