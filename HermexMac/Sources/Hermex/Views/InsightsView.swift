import SwiftUI
import Charts

struct InsightsView: View {
    let client: APIClient

    @Environment(\.colorScheme) private var colorScheme
    @State private var insights: InsightsResponse?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var periodDays = 30

    private static let periods = [7, 30, 90]

    /// Validated single-series hue: #2a78d6 on light, #3987e5 on dark.
    private var seriesColor: Color {
        colorScheme == .dark
            ? Color(red: 0x39 / 255.0, green: 0x87 / 255.0, blue: 0xE5 / 255.0)
            : Color(red: 0x2A / 255.0, green: 0x78 / 255.0, blue: 0xD6 / 255.0)
    }

    var body: some View {
        Group {
            if isLoading && insights == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 8) {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Button("Retry") {
                        Task { await load() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .navigationTitle("Insights")
        .toolbar {
            ToolbarItem {
                Picker("Period", selection: $periodDays) {
                    ForEach(Self.periods, id: \.self) { days in
                        Text("\(days)d").tag(days)
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button {
                    Task { await load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await load() }
        .onChange(of: periodDays) { _ in
            Task { await load() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statTiles
                dailyChart
                modelTable
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statTiles: some View {
        HStack(spacing: 12) {
            StatTile(title: "Sessions", value: formatted(insights?.totalSessions))
            StatTile(title: "Messages", value: formatted(insights?.totalMessages))
            StatTile(title: "Tokens", value: formatted(insights?.totalTokens))
            StatTile(
                title: "Cost",
                value: insights?.totalCost.map { String(format: "$%.2f", $0) } ?? "—"
            )
            if let hit = insights?.totalCacheHitPercent {
                StatTile(title: "Cache hits", value: String(format: "%.0f%%", hit))
            }
        }
    }

    @ViewBuilder
    private var dailyChart: some View {
        let rows = insights?.dailyTokens ?? []
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tokens per day")
                    .font(.headline)
                Chart(rows) { row in
                    BarMark(
                        x: .value("Day", shortDate(row.date)),
                        y: .value("Tokens", row.totalTokens),
                        width: .ratio(0.7)
                    )
                    .foregroundStyle(seriesColor)
                    .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5))
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .frame(height: 180)
            }
        }
    }

    @ViewBuilder
    private var modelTable: some View {
        let models = insights?.models ?? []
        if !models.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("By model")
                    .font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Model")
                        Text("Sessions")
                        Text("Tokens")
                        Text("Cost")
                        Text("Cache")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(models) { row in
                        GridRow {
                            Text(row.model ?? "—")
                                .lineLimit(1)
                            Text(formatted(row.sessions))
                            Text(formatted(row.totalTokens))
                            Text(row.cost.map { String(format: "$%.2f", $0) } ?? "—")
                            Text(row.cacheHitPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                        }
                        .font(.callout)
                    }
                }
            }
        } else if insights != nil {
            Text("No usage in this period")
                .foregroundStyle(.secondary)
        }
    }

    private func formatted(_ value: Int?) -> String {
        guard let value else { return "—" }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.0fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func shortDate(_ date: String?) -> String {
        guard let date else { return "" }
        // "2026-07-12" → "7/12"
        let parts = date.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return date }
        return "\(month)/\(day)"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            insights = try await client.insights(days: periodDays)
            loadError = nil
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary.opacity(0.5))
        )
    }
}
