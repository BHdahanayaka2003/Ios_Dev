import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

final class ClickerGameViewModel: ObservableObject {

    enum GameState {
        case ready
        case playing
        case finished
    }

    @Published private(set) var score = 0
    @Published private(set) var timeRemaining = Constants.roundDuration
    @Published private(set) var state: ClickerGameViewModel.GameState = .ready

    @Published private(set) var highScore = UserDefaults.standard.integer(forKey: Constants.highScoreKey)

    @Published private(set) var comboMultiplier = 1
    private var lastTapTime: Date?

    @Published private(set) var buttonColor: Color = .blue
    @Published private(set) var isPenaltyColor = false
    private var colorCancellable: AnyCancellable?

    enum Constants {
        static let roundDuration = 10          // ← updated to match spec
        static let lowTimeThreshold = 4
        static let highScoreKey = "com.tapgame.highScore"

        static let comboWindow: TimeInterval = 0.5
        static let maxCombo = 5

        static let colorSwitchInterval: TimeInterval = 2.0
    }

    private var cancellable: AnyCancellable?

    var isLowOnTime: Bool { timeRemaining <= Constants.lowTimeThreshold }

    func startGame() {
        cancellable?.cancel()
        colorCancellable?.cancel()

        score = 0
        timeRemaining = Constants.roundDuration
        state = .playing
        comboMultiplier = 1
        lastTapTime = nil
        buttonColor = .blue
        isPenaltyColor = false

        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }

        colorCancellable = Timer.publish(every: Constants.colorSwitchInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.cycleButtonColor()
            }
    }

    func tap() {
        guard state == .playing else { return }

        let now = Date()
        if let last = lastTapTime, now.timeIntervalSince(last) <= Constants.comboWindow {
            comboMultiplier = min(comboMultiplier + 1, Constants.maxCombo)
        } else {
            comboMultiplier = 1
        }
        lastTapTime = now

        if isPenaltyColor {
            comboMultiplier = 1
            // no score added on penalty tap
        } else {
            let bonus = (buttonColor == .green) ? 2 : 1
            score += comboMultiplier * bonus
        }
    }

    func playAgain() {
        startGame()
    }

    private func tick() {
        guard timeRemaining > 0 else {
            endGame()
            return
        }
        timeRemaining -= 1
    }

    private func endGame() {
        cancellable?.cancel()
        cancellable = nil
        colorCancellable?.cancel()
        colorCancellable = nil
        state = .finished

        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: Constants.highScoreKey)
        }
    }

    private func cycleButtonColor() {
        let outcomes: [(Color, Bool)] = [
            (.blue, false),
            (.green, false),   // bonus
            (.gray, true)      // penalty
        ]
        let choice = outcomes.randomElement()!
        buttonColor = choice.0
        isPenaltyColor = choice.1
    }
}

#if canImport(UIKit)
enum ClickerHaptics {
    private static let tapGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let resultGenerator = UINotificationFeedbackGenerator()

    static func tap() {
        tapGenerator.impactOccurred()
    }

    static func gameOver(isNewHighScore: Bool) {
        resultGenerator.notificationOccurred(isNewHighScore ? .success : .warning)
    }
}
#else
// Fallback for platforms without UIKit (e.g., macOS, watchOS)
enum ClickerHaptics {
    static func tap() {
        // No-op on platforms without UIKit haptics
    }

    static func gameOver(isNewHighScore: Bool) {
        // No-op on platforms without UIKit haptics
    }
}
#endif

// Renamed from `tapGame` to `ClickerGameView` so it matches the routing
// used in HomeViewHub.destination(for:) — previously that switch pointed
// at a `ClickerGameView` that didn't exist here, and this view was never
// actually reachable in the tab flow.
struct TapClickerGameView: View {
    @EnvironmentObject var store: GameSessionStore
    @StateObject private var game = ClickerGameViewModel()
    @State private var tapScale: CGFloat = 1.0
    @State private var didRecordThisRound = false

    var body: some View {
        VStack(spacing: 30) {
            switch game.state {
            case .ready, .playing:
                gameView
            case .finished:
                gameOverView
            }
        }
        .padding()
        .animation(.easeInOut, value: game.state)
        .onChange(of: game.state) { newState in
            if newState == ClickerGameViewModel.GameState.finished {
                ClickerHaptics.gameOver(isNewHighScore: game.score >= game.highScore)
                recordSessionIfNeeded()
            } else if newState == ClickerGameViewModel.GameState.playing {
                didRecordThisRound = false
            }
        }
    }

    private var gameView: some View {
        VStack(spacing: 30) {
            Text("Time: \(game.timeRemaining)s")
                .font(.title2)
                .foregroundColor(game.isLowOnTime ? .red : .primary)
                .contentTransition(.numericText())
                .accessibilityLabel("\(game.timeRemaining) seconds remaining")

            VStack(spacing: 4) {
                Text("Score: \(game.score)")
                    .font(.largeTitle)
                    .bold()
                    .contentTransition(.numericText())

                Text("Best: \(game.highScore)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if game.comboMultiplier > 1 {
                    Text("Combo ×\(game.comboMultiplier)")
                        .font(.headline)
                        .foregroundColor(.orange)
                        .transition(.scale)
                }
            }

            Button(action: tapButtonTapped) {
                Text(game.isPenaltyColor ? "AVOID!" : "TAP ME")
                    .font(.title)
                    .frame(width: 200, height: 200)
                    .background(game.buttonColor)
                    .foregroundColor(.white)
                    .clipShape(Circle())
                    .scaleEffect(tapScale)
                    .animation(.easeInOut(duration: 0.3), value: game.buttonColor)
            }
            .disabled(game.state != .playing)
            .opacity(game.state == .playing ? 1 : 0.5)
            .accessibilityHint("Tap rapidly to increase your score")

            if game.state == .ready {
                Button("Start Game") {
                    game.startGame()
                }
                .font(.title2)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
    }

    private var gameOverView: some View {
        VStack(spacing: 20) {
            Text("Game Over!")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.red)

            Text("Final Score: \(game.score)")
                .font(.title)

            if game.score >= game.highScore && game.score > 0 {
                Label("New High Score!", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundColor(.yellow)
            } else {
                Text("Best: \(game.highScore)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button("Play Again") {
                game.playAgain()
            }
            .font(.title2)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }

    private func tapButtonTapped() {
        game.tap()
        ClickerHaptics.tap()

        withAnimation(.easeOut(duration: 0.08)) {
            tapScale = 0.9
        }
        withAnimation(.easeOut(duration: 0.08).delay(0.08)) {
            tapScale = 1.0
        }
    }

    // Guards against double-recording if `.onChange` ever fires more than once
    // for the same finished state (e.g. due to SwiftUI re-evaluations).
    private func recordSessionIfNeeded() {
        guard !didRecordThisRound else { return }
        didRecordThisRound = true
        store.recordSession(gameName: "Tap Game", score: game.score)
    }
}

#Preview {
    TapClickerGameView()
        .environmentObject(GameSessionStore.shared)
}

