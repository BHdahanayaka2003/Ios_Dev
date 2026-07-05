import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: ClickerGameView()) {
                    Text("Tap score game")
                }
                NavigationLink(destination: LightUpGame()) {
                    Text("Light it up")
                }
            }
            .navigationTitle("Games")
        }
    }
}


struct ClickerGameView: View {
    @State private var score = 0
    @State private var timeRemaining = 60
    @State private var isGameRunning = false
    @State private var isGameOver = false
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 30) {
            if isGameOver {
                gameOverView
            } else {
                gameView
            }
        }
        .padding()
        .navigationTitle("Tap score game")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            
            endGame()
        }
    }

    var gameView: some View {
        VStack(spacing: 30) {
            Text("Time: \(timeRemaining)s")
                .font(.title2)
                .foregroundColor(timeRemaining <= 10 ? .red : .primary)

            Text("Score: \(score)")
                .font(.largeTitle)
                .bold()

            Button(action: tapButton) {
                Text("TAP ME")
                    .font(.title)
                    .frame(width: 200, height: 200)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
            .disabled(!isGameRunning)
            .opacity(isGameRunning ? 1 : 0.5)

            if !isGameRunning {
                Button("Start game") {
                    startGame()
                }
                .font(.title2)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
    }

    var gameOverView: some View {
        VStack(spacing: 20) {
            Text("Game over!")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.red)

            Text("Final score: \(score)")
                .font(.title)

            Button("Play again") {
                resetGame()
            }
            .font(.title2)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }

    func startGame() {
        score = 0
        timeRemaining = 60
        isGameRunning = true
        isGameOver = false

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                } else {
                    self.endGame()
                }
            }
        }
    }

    func tapButton() {
        guard isGameRunning else { return }
        score += 1
    }

    func endGame() {
        timer?.invalidate()
        timer = nil
        isGameRunning = false
        isGameOver = true
    }

    func resetGame() {
        isGameOver = false
        score = 0
        timeRemaining = 60
    }
}


struct LightUpGame: View {
    private let gridSize = 3
    @State private var activeIndex: Int? = nil
    @State private var score = 0
    @State private var timeRemaining = 60
    @State private var isGameRunning = false
    @State private var isGameOver = false
    @State private var gameTimer: Timer?
    @State private var lightTimer: Timer?
 
    var body: some View {
        VStack(spacing: 24) {
            if isGameOver {
                gameOverView
            } else {
                gameView
            }
        }
        .padding()
        .navigationTitle("Light it up")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            endGame()
        }
    }
 
    var gameView: some View {
        VStack(spacing: 24) {
            Text("Time: \(timeRemaining)s")
                .font(.title2)
                .foregroundColor(timeRemaining <= 10 ? .red : .primary)
 
            Text("Score: \(score)")
                .font(.largeTitle)
                .bold()
 
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: gridSize), spacing: 12) {
                ForEach(0..<(gridSize * gridSize), id: \.self) { index in
                    Button(action: { tapTile(index) }) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(index == activeIndex ? Color.yellow : Color.blue.opacity(0.3))
                            .frame(height: 80)
                    }
                    .disabled(!isGameRunning)
                }
            }
            .padding(.horizontal)
 
            if !isGameRunning {
                Button("Start game") {
                    startGame()
                }
                .font(.title2)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
    }
 
    var gameOverView: some View {
        VStack(spacing: 20) {
            Text("Game over!")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.red)
 
            Text("Final score: \(score)")
                .font(.title)
 
            Button("Play again") {
                resetGame()
            }
            .font(.title2)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }
 
    func startGame() {
        score = 0
        timeRemaining = 60
        isGameRunning = true
        isGameOver = false
        activeIndex = nil
 
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                } else {
                    self.endGame()
                }
            }
        }
 
        lightTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            DispatchQueue.main.async {
                self.moveLight()
            }
        }
        moveLight()
    }
 
    func moveLight() {
        let total = gridSize * gridSize
        var newIndex = Int.random(in: 0..<total)
        while newIndex == activeIndex && total > 1 {
            newIndex = Int.random(in: 0..<total)
        }
        activeIndex = newIndex
    }
 
    func tapTile(_ index: Int) {
        guard isGameRunning else { return }
        if index == activeIndex {
            score += 1
            moveLight()
        }
    }
 
    func endGame() {
        gameTimer?.invalidate()
        gameTimer = nil
        lightTimer?.invalidate()
        lightTimer = nil
        isGameRunning = false
        isGameOver = true
        activeIndex = nil
    }
 
    func resetGame() {
        isGameOver = false
        score = 0
        timeRemaining = 60
    }
}
