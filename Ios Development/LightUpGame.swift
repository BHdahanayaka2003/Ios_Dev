import SwiftUI



struct PrimaryButtonStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.bold())
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}



struct HomeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Choose a game") {
                    NavigationLink(destination: ClickerGameView()) {
                        Label("Tap Frenzy", systemImage: "hand.tap.fill")
                    }
                    NavigationLink(destination: LightUpGame()) {
                        Label("Light It Up", systemImage: "square.grid.3x3.fill")
                    }
                }
            }
            .navigationTitle("Games")
        }
    }
}



struct ClickerGameView: View {
    @AppStorage("highScore_tapFrenzy") private var highScore: Int = 0

    @State private var score = 0
    @State private var timeRemaining = 60
    @State private var isGameRunning = false
    @State private var isGameOver = false
    @State private var isNewHighScore = false
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
        .navigationTitle("Tap Frenzy")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { endGame() }
    }

    var gameView: some View {
        VStack(spacing: 30) {
            Text("Time: \(timeRemaining)s")
                .font(.title2)
                .foregroundColor(timeRemaining <= 10 ? .red : .primary)

            Text("Score: \(score)")
                .font(.largeTitle)
                .bold()

            Text("Best: \(highScore)")
                .font(.caption)
                .foregroundColor(.secondary)

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
                Button("Start Game") { startGame() }
                    .buttonStyle(PrimaryButtonStyle(color: .green))
            }
        }
    }

    var gameOverView: some View {
        VStack(spacing: 20) {
            Text("Game Over!")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.red)

            Text("Final Score: \(score)")
                .font(.title)

            if isNewHighScore {
                Text("🎉 New High Score!")
                    .font(.headline)
                    .foregroundColor(.yellow)
            } else {
                Text("Best: \(highScore)")
                    .foregroundColor(.secondary)
            }

            Button("Play Again") { resetGame() }
                .buttonStyle(PrimaryButtonStyle(color: .blue))
        }
    }

    func startGame() {
        score = 0
        timeRemaining = 60
        isGameRunning = true
        isGameOver = false
        isNewHighScore = false

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
        if score > highScore {
            highScore = score
            isNewHighScore = true
        }
    }

    func resetGame() {
        isGameOver = false
        score = 0
        timeRemaining = 60
    }
}


enum GameLevel: Int, CaseIterable {
    case l1, l2, l3, l4

    
    var cardCount: Int {
        switch self {
        case .l1: return 3
        case .l2: return 4
        case .l3: return 6
        case .l4: return 9
        }
    }

    
    var columns: Int {
        switch self {
        case .l1: return 3
        case .l2: return 2
        case .l3: return 3
        case .l4: return 3
        }
    }

   
    var litWindow: Double {
        switch self {
        case .l1: return 1.5
        case .l2: return 1.2
        case .l3: return 1.0
        case .l4: return 0.8
        }
    }

    
    var simultaneousLit: Int {
        self == .l4 ? 2 : 1
    }

    
    var startsAtElapsed: Int {
        switch self {
        case .l1: return 0
        case .l2: return 15
        case .l3: return 30
        case .l4: return 45
        }
    }

    var color: Color {
        switch self {
        case .l1: return .green
        case .l2: return .blue
        case .l3: return .yellow
        case .l4: return .red
        }
    }

    var label: String { "L\(rawValue + 1)" }

    static func level(forElapsed elapsed: Int) -> GameLevel {
        if elapsed >= GameLevel.l4.startsAtElapsed { return .l4 }
        if elapsed >= GameLevel.l3.startsAtElapsed { return .l3 }
        if elapsed >= GameLevel.l2.startsAtElapsed { return .l2 }
        return .l1
    }
}

struct LightCard: Identifiable {
    let id: Int
    var isLit: Bool = false
}



struct LightUpGame: View {
    @AppStorage("highScore_lightItUp") private var highScore: Int = 0

    @State private var cards: [LightCard] = []
    @State private var score = 0
    @State private var timeRemaining = 60
    @State private var isGameRunning = false
    @State private var isGameOver = false
    @State private var isNewHighScore = false
    @State private var level: GameLevel = .l1
    @State private var showLevelUpFlash = false
    @State private var showSettings = false

    // Bonus: adjustable round length (30 / 60 / 90s)
    @State private var roundDuration = 60

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
        .navigationTitle("Light It Up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isGameRunning {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .onDisappear { endGame() }
        .overlay(levelUpOverlay)
    }

    

    var gameView: some View {
        VStack(spacing: 20) {
            header
            grid
            if !isGameRunning {
                Button("Start Game") { startGame() }
                    .buttonStyle(PrimaryButtonStyle(color: .green))
            }
        }
    }

    var header: some View {
        VStack(spacing: 8) {
            HStack {
                Label("\(timeRemaining)s", systemImage: "clock")
                    .foregroundColor(timeRemaining <= 10 ? .red : .primary)
                Spacer()
                Text(level.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(level.color)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .font(.title3)

            Text("Score: \(score)")
                .font(.largeTitle.bold())

            Text("Best: \(highScore)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: level.columns),
            spacing: 12
        ) {
            ForEach(cards) { card in
                Button(action: { tapCard(card.id) }) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(card.isLit ? level.color : Color.gray.opacity(0.25))
                        .frame(height: 80)
                        .scaleEffect(card.isLit ? 1.05 : 1.0)
                        .shadow(color: card.isLit ? level.color.opacity(0.6) : .clear, radius: 10)
                }
                .disabled(!isGameRunning)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: card.isLit)
            }
        }
        .padding(.horizontal)
    }

    var gameOverView: some View {
        VStack(spacing: 20) {
            Text("Game Over!")
                .font(.largeTitle.bold())
                .foregroundColor(.red)

            Text("Final Score: \(score)")
                .font(.title)

            if isNewHighScore {
                Text("🎉 New High Score!")
                    .font(.headline)
                    .foregroundColor(.yellow)
            } else {
                Text("Best: \(highScore)")
                    .foregroundColor(.secondary)
            }

            Button("Play Again") { resetGame() }
                .buttonStyle(PrimaryButtonStyle(color: .blue))
        }
    }

    var levelUpOverlay: some View {
        Group {
            if showLevelUpFlash {
                Text("Level \(level.label)!")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                    .padding()
                    .background(level.color.opacity(0.9))
                    .cornerRadius(20)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: showLevelUpFlash)
    }

    var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Round Length") {
                    Picker("Duration", selection: $roundDuration) {
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                        Text("90s").tag(90)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        .presentationDetents([.height(180)])
    }

   

    func startGame() {
        score = 0
        timeRemaining = roundDuration
        isGameRunning = true
        isGameOver = false
        isNewHighScore = false
        level = .l1
        setupCards(for: .l1)

        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async { tick() }
        }
        scheduleLightTimer()
    }

    func tick() {
        guard timeRemaining > 0 else { endGame(); return }
        timeRemaining -= 1

        let elapsed = roundDuration - timeRemaining
        let newLevel = GameLevel.level(forElapsed: elapsed)
        if newLevel != level {
            levelUp(to: newLevel)
        }

        if timeRemaining == 0 {
            endGame()
        }
    }

    func levelUp(to newLevel: GameLevel) {
        level = newLevel
        setupCards(for: newLevel)
        scheduleLightTimer()

        showLevelUpFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showLevelUpFlash = false
        }
    }

    func setupCards(for level: GameLevel) {
        cards = (0..<level.cardCount).map { LightCard(id: $0) }
    }

    func scheduleLightTimer() {
        lightTimer?.invalidate()
        lightTimer = Timer.scheduledTimer(withTimeInterval: level.litWindow, repeats: true) { _ in
            DispatchQueue.main.async { relight() }
        }
        relight()
    }

    
    func relight() {
        let missedCount = cards.filter { $0.isLit }.count
        if missedCount > 0 {
            score = max(0, score - missedCount)
        }
        for i in cards.indices { cards[i].isLit = false }

        var indices = Set<Int>()
        while indices.count < min(level.simultaneousLit, cards.count) {
            indices.insert(Int.random(in: 0..<cards.count))
        }
        for i in indices { cards[i].isLit = true }
    }

    func tapCard(_ id: Int) {
        guard isGameRunning, let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        if cards[idx].isLit {
            score += 1
            cards[idx].isLit = false
        } else {
            score = max(0, score - 1)
        }
    }

    func endGame() {
        gameTimer?.invalidate(); gameTimer = nil
        lightTimer?.invalidate(); lightTimer = nil
        isGameRunning = false
        isGameOver = true
        for i in cards.indices { cards[i].isLit = false }
        if score > highScore {
            highScore = score
            isNewHighScore = true
        }
    }

    func resetGame() {
        isGameOver = false
        score = 0
        timeRemaining = roundDuration
    }
}
