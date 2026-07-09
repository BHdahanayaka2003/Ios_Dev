import SwiftUI

struct GameOption: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let colors: [Color]
    let badge: String
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeViewHub()
                .tabItem {
                    Label("Games", systemImage: "gamecontroller.fill")
                }

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.fill")
                }

            GameMapView()
                .tabItem {
                    Label("Play Map", systemImage: "map.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        
        .environmentObject(GameSessionStore.shared)
        .onAppear {
            
            LocationManager.shared.requestPermission()
            LocationManager.shared.requestOneShotLocation()
        }
    }
}



struct HomeViewHub: View {
    @EnvironmentObject var store: GameSessionStore
    @State private var cardsAppeared = false
    @State private var streakPulse = false

    private let games: [GameOption] = [
        GameOption(
            title: "Light Up",
            subtitle: "Test your reflexes",
            systemImage: "lightbulb.fill",
            colors: [.yellow, .orange],
            badge: "⚡ Fast"
        ),
        GameOption(
            title: "Quiz Rush",
            subtitle: "Race against the clock",
            systemImage: "brain.head.profile",
            colors: [.purple, .pink],
            badge: "🧠 Brainy"
        ),
        GameOption(
            title: "Tap Game",
            subtitle: "How fast can you tap?",
            systemImage: "hand.tap.fill",
            colors: [.blue, .cyan],
            badge: "🔥 Popular"
        )
    ]

    

    private var totalGames: Int { store.sessions.count }

    private var bestScore: Int { store.sessions.map(\.score).max() ?? 0 }

    private var lastSession: GameSession? {
        store.sessions.sorted { $0.date > $1.date }.first
    }

    
    private var currentStreak: Int {
        let calendar = Calendar.current
        let playedDays = Set(store.sessions.map { calendar.startOfDay(for: $0.date) })
        guard !playedDays.isEmpty else { return 0 }

        var streak = 0
        var day = calendar.startOfDay(for: Date())
        while playedDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning ☀️"
        case 12..<17: return "Good afternoon 🌤️"
        case 17..<22: return "Good evening 🌆"
        default: return "Still up? 🌙"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer

                ScrollView {
                    VStack(spacing: 24) {
                        header

                        statsStrip

                        if let lastSession {
                            continuePlayingCard(for: lastSession)
                        }

                        VStack(spacing: 18) {
                            ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                                NavigationLink {
                                    destination(for: game.title)
                                } label: {
                                    GameCard(game: game)
                                }
                                .buttonStyle(PressableCardStyle())
                                .simultaneousGesture(TapGesture().onEnded { ClickerHaptics.tap() })
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 24)
                                .animation(
                                    .spring(response: 0.5, dampingFraction: 0.75)
                                        .delay(Double(index) * 0.08),
                                    value: cardsAppeared
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .onAppear {
                cardsAppeared = true
                if currentStreak > 0 { streakPulse = true }
            }
        }
    }

    

    private var backgroundLayer: some View {
        AnimatedBlobBackground()
            .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(greeting)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("🎮 Game Hub")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple, .pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("Pick a game and beat your best")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var statsStrip: some View {
        HStack(spacing: 12) {
            StatChip(
                icon: "gamecontroller.fill",
                value: "\(totalGames)",
                label: "Played",
                tint: .blue
            )
            StatChip(
                icon: "trophy.fill",
                value: "\(bestScore)",
                label: "Best",
                tint: .yellow
            )
            StatChip(
                icon: "flame.fill",
                value: "\(currentStreak)",
                label: currentStreak == 1 ? "Day" : "Days",
                tint: .orange,
                pulse: streakPulse && currentStreak > 0
            )
        }
        .padding(.horizontal)
    }

    private func continuePlayingCard(for session: GameSession) -> some View {
        NavigationLink {
            destination(for: session.gameName)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color(for: session.gameName).gradient)
                        .frame(width: 46, height: 46)
                    Image(systemName: icon(for: session.gameName))
                        .foregroundStyle(.white)
                        .font(.system(size: 18, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue Playing")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(session.gameName)
                        .font(.headline)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Last score")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(session.score)")
                        .font(.title3.bold())
                }

                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(color(for: session.gameName).opacity(0.4), lineWidth: 1.5)
                    )
            )
            .padding(.horizontal)
        }
        .buttonStyle(PressableCardStyle())
        .simultaneousGesture(TapGesture().onEnded { ClickerHaptics.tap() })
    }

    // Routes to the REAL game views — no placeholders.
    @ViewBuilder
    private func destination(for title: String) -> some View {
        switch title {
        case "Light Up":
            LightUpGame()
        case "Quiz Rush":
            QuizRushView()
        case "Tap Game":
            
            TapClickerGameView()
        default:
            EmptyView()
        }
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



private struct GameCard: View {
    let game: GameOption

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: game.colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .shadow(color: game.colors.first?.opacity(0.5) ?? .clear, radius: 10, x: 0, y: 6)

                Image(systemName: game.systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(game.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(game.badge)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(game.colors.first?.opacity(0.18) ?? .clear)
                        )
                        .foregroundStyle(game.colors.first ?? .primary)
                }

                Text(game.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 5)
        )
    }
}



private struct StatChip: View {
    let icon: String
    let value: String
    let label: String
    let tint: Color
    var pulse: Bool = false

    @State private var animate = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .scaleEffect(pulse && animate ? 1.15 : 1.0)
                .onAppear {
                    guard pulse else { return }
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        animate = true
                    }
                }

            Text(value)
                .font(.title3.bold())
                .contentTransition(.numericText())

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}



private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}



private struct AnimatedBlobBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)

            Circle()
                .fill(
                    LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .opacity(0.35)
                .offset(x: animate ? -120 : -160, y: animate ? -300 : -260)

            Circle()
                .fill(
                    LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .opacity(0.3)
                .offset(x: animate ? 140 : 170, y: animate ? -120 : -160)

            Circle()
                .fill(
                    LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 200, height: 200)
                .blur(radius: 70)
                .opacity(0.25)
                .offset(x: animate ? -100 : -60, y: animate ? 420 : 460)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

#Preview {
    MainTabView()
}
