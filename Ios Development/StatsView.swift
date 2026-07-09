import SwiftUI
import Charts

// MARK: - Stats Screen
//
// Reads directly from GameSessionStore (already populated by
// `store.recordSession(gameName:score:)` at the end of every round).
// No new persistence needed — this view is purely derived state.

struct StatsView: View {
    @EnvironmentObject var store: GameSessionStore

    // Keep a stable, sensible display order for known games, then
    // append anything unrecognized (e.g. future games) alphabetically.
    private var gameNames: [String] {
        let known = ["Tap Game", "Light Up", "Quiz Rush"]
        let present = Set(store.sessions.map(\.gameName))
        let extras = present.subtracting(known).sorted()
        return known.filter(present.contains) + extras
    }

    private var totalGames: Int { store.sessions.count }

    private var overallBest: Int {
        store.sessions.map(\.score).max() ?? 0
    }

    private func sessions(for game: String) -> [GameSession] {
        store.sessions.filter { $0.gameName == game }
    }

    private func bestScore(for game: String) -> Int {
        sessions(for: game).map(\.score).max() ?? 0
    }

    private func playCount(for game: String) -> Int {
        sessions(for: game).count
    }

    private var recentSessions: [GameSession] {
        Array(store.sessions.sorted { $0.date > $1.date }.prefix(10))
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            summaryCards
                            chartSection
                            personalBestsSection
                            recentSection
                        }
                        .padding(.vertical, 20)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Summary

    private var summaryCards: some View {
        HStack(spacing: 14) {
            StatSummaryCard(
                title: "Games Played",
                value: "\(totalGames)",
                systemImage: "gamecontroller.fill",
                color: .blue
            )
            StatSummaryCard(
                title: "Best Score",
                value: "\(overallBest)",
                systemImage: "trophy.fill",
                color: .yellow
            )
        }
        .padding(.horizontal)
    }

    // MARK: Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Best Score by Game")
                .font(.headline)
                .padding(.horizontal)

            Chart {
                ForEach(gameNames, id: \.self) { name in
                    BarMark(
                        x: .value("Game", name),
                        y: .value("Best Score", bestScore(for: name))
                    )
                    .foregroundStyle(color(for: name).gradient)
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        Text("\(bestScore(for: name))")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 220)
            .padding(.horizontal)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let name = value.as(String.self) {
                            Text(name)
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.horizontal)
    }

    // MARK: Personal bests

    private var personalBestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Bests")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 10) {
                ForEach(gameNames.filter { playCount(for: $0) > 0 }, id: \.self) { name in
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: name))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(color(for: name))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.subheadline.bold())
                            Text("\(playCount(for: name)) games played")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(bestScore(for: name))")
                            .font(.title3.bold())
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: Recent games

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Games")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 10) {
                ForEach(recentSessions) { session in
                    RecentSessionRow(session: session)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No stats yet")
                .font(.headline)
            Text("Finish a round in any game and your stats will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: Shared styling helpers (mirrors GameMapView's icon/color mapping)

    private func icon(for gameName: String) -> String {
        switch gameName {
        case "Tap Game": return "hand.tap.fill"
        case "Light Up": return "lightbulb.fill"
        case "Quiz Rush": return "brain.head.profile"
        default: return "gamecontroller.fill"
        }
    }

    private func color(for gameName: String) -> Color {
        switch gameName {
        case "Tap Game": return .blue
        case "Light Up": return .yellow
        case "Quiz Rush": return .purple
        default: return .gray
        }
    }
}

private struct StatSummaryCard: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct RecentSessionRow: View {
    let session: GameSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: session.gameName))
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color(for: session.gameName))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(session.gameName)
                    .font(.subheadline.bold())
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(session.score)")
                .font(.headline)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func icon(for gameName: String) -> String {
        switch gameName {
        case "Tap Game": return "hand.tap.fill"
        case "Light Up": return "lightbulb.fill"
        case "Quiz Rush": return "brain.head.profile"
        default: return "gamecontroller.fill"
        }
    }

    private func color(for gameName: String) -> Color {
        switch gameName {
        case "Tap Game": return .blue
        case "Light Up": return .yellow
        case "Quiz Rush": return .purple
        default: return .gray
        }
    }
}

#Preview {
    StatsView()
        .environmentObject(GameSessionStore.shared)
}
