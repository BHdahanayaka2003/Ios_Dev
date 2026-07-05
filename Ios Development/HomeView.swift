
import SwiftUI



struct GameOption: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let colors: [Color]
}



struct HomeViewHub: View {

    private let games: [GameOption] = [
        GameOption(
            title: "Light Up",
            subtitle: "Test your reflexes",
            systemImage: "lightbulb.fill",
            colors: [.yellow, .orange]
        ),
        GameOption(
            title: "Quiz Rush",
            subtitle: "Race against the clock",
            systemImage: "brain.head.profile",
            colors: [.purple, .pink]
        ),
        GameOption(
            title: "Tap Game",
            subtitle: "How fast can you tap?",
            systemImage: "hand.tap.fill",
            colors: [.blue, .cyan]
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    header

                    VStack(spacing: 18) {
                        ForEach(games) { game in
                            NavigationLink {
                                destination(for: game.title)
                            } label: {
                                GameCard(game: game)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 30)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Choose a Game")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("🎮 Game Hub")
                .font(.largeTitle.bold())
            Text("Pick a game to start playing")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    
    @ViewBuilder
    private func destination(for title: String) -> some View {
        switch title {
        case "Light Up":
            LightUpGame()
        case "Quiz Rush":
            QuizRushView()
        case "Tap Game":
            tapGame()
        default:
            EmptyView()
        }
    }
}



private struct GameCard: View {
    let game: GameOption

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: game.colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)

                Image(systemName: game.systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(game.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
}



#Preview {
    HomeViewHub()
}
