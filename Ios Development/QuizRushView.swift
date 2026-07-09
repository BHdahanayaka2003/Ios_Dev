import SwiftUI
import Combine


// Matches the raw JSON shape returned by https://opentdb.com/api.php


struct QuizRushTriviaResponse: Codable {
    let responseCode: Int
    let results: [QuizRushAPIQuestion]

    enum CodingKeys: String, CodingKey {
        case responseCode = "response_code"
        case results
    }
}


struct QuizRushAPIQuestion: Codable {
    let category: String
    let type: String
    let difficulty: String
    let question: String
    let correctAnswer: String
    let incorrectAnswers: [String]

    enum CodingKeys: String, CodingKey {
        case category, type, difficulty, question
        case correctAnswer = "correct_answer"
        case incorrectAnswers = "incorrect_answers"
    }
}


struct QuizRushQuestion: Identifiable {
    let id = UUID()
    let category: String
    let difficulty: String
    let text: String
    let correctAnswer: String
    var answers: [String] = []
}



extension String {
    var quizRushHTMLDecoded: String {
        guard let data = self.data(using: .utf8) else { return self }
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) else { return self }
        return attributed.string
    }
}



enum QuizRushNetworkError: Error, LocalizedError {
    case badURL
    case badResponse
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid URL."
        case .badResponse: return "The server returned an unexpected response."
        case .decodingFailed: return "Couldn't read the trivia data."
        }
    }
}

struct QuizRushTriviaService {
    
    private let urlString = "https://opentdb.com/api.php?amount=10&type=multiple"

    func fetchQuestions() async throws -> [QuizRushQuestion] {
        guard let url = URL(string: urlString) else { throw QuizRushNetworkError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw QuizRushNetworkError.badResponse
        }

        let decoded: QuizRushTriviaResponse
        do {
            decoded = try JSONDecoder().decode(QuizRushTriviaResponse.self, from: data)
        } catch {
            throw QuizRushNetworkError.decodingFailed
        }

        
        var questions: [QuizRushQuestion] = decoded.results.map { raw in
            let correct = raw.correctAnswer.quizRushHTMLDecoded
            let incorrect = raw.incorrectAnswers.map { $0.quizRushHTMLDecoded }
            return QuizRushQuestion(
                category: raw.category.quizRushHTMLDecoded,
                difficulty: raw.difficulty.quizRushHTMLDecoded,
                text: raw.question.quizRushHTMLDecoded,
                correctAnswer: correct,
                answers: ([correct] + incorrect)
            )
        }

        
        let allAnswerPool: [String] = questions.flatMap { $0.answers }

        for i in questions.indices {
            var existing = Set(questions[i].answers)
            var candidates = allAnswerPool.shuffled()

            while questions[i].answers.count < 5, let candidate = candidates.popLast() {
                if !existing.contains(candidate) {
                    questions[i].answers.append(candidate)
                    existing.insert(candidate)
                }
            }

            questions[i].answers.shuffle()
        }

        return questions
    }
}



enum QuizRushViewState: Equatable {
    case loading
    case loaded
    case failed(String)
}

@MainActor
final class QuizRushViewModel: ObservableObject {

    
    @Published var state: QuizRushViewState = .loading
    @Published var questions: [QuizRushQuestion] = []
    @Published var currentIndex: Int = 0
    @Published var score: Int = 0
    @Published var streak: Int = 0
    @Published var selectedAnswer: String? = nil
    @Published var lastAnswerWasCorrect: Bool? = nil
    @Published var showResults: Bool = false

    private let service: QuizRushTriviaService
    private let correctPoints = 10
    private let wrongPenalty = 5
    private let streakBonus = 5

    var currentQuestion: QuizRushQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var progressLabel: String {
        "\(min(currentIndex + 1, questions.count)) of \(questions.count)"
    }

    init(service: QuizRushTriviaService = QuizRushTriviaService()) {
        self.service = service
    }

    /// Fetches a fresh round of 10 questions from the API.
    func load() async {
        state = .loading
        resetRound()
        do {
            let fetched = try await service.fetchQuestions()
            questions = fetched
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func retry() {
        Task { await load() }
    }

    private func resetRound() {
        questions = []
        currentIndex = 0
        score = 0
        streak = 0
        selectedAnswer = nil
        lastAnswerWasCorrect = nil
        showResults = false
    }

    
    func selectAnswer(_ answer: String) {
        guard let question = currentQuestion, selectedAnswer == nil else { return }

        selectedAnswer = answer
        let isCorrect = (answer == question.correctAnswer)
        lastAnswerWasCorrect = isCorrect

        if isCorrect {
            streak += 1
            let bonus = streak >= 2 ? streakBonus : 0
            score += correctPoints + bonus
        } else {
            streak = 0
            score = max(0, score - wrongPenalty)
        }

        
        Task {
            try? await Task.sleep(nanoseconds: 550_000_000)
            advance()
        }
    }

    private func advance() {
        selectedAnswer = nil
        lastAnswerWasCorrect = nil

        if currentIndex + 1 < questions.count {
            currentIndex += 1
        } else {
            showResults = true
        }
    }

    func playAgain() {
        Task { await load() }
    }
}


struct QuizRushView: View {
    @EnvironmentObject var store: GameSessionStore
    @StateObject private var viewModel = QuizRushViewModel()
    @State private var didRecordThisRound = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            switch viewModel.state {
            case .loading:
                loadingView
            case .failed(let message):
                errorView(message: message)
            case .loaded:
                if viewModel.showResults {
                    QuizRushResultsView(viewModel: viewModel)
                } else {
                    quizContent
                }
            }
        }
        .navigationTitle("Quiz Rush")
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.showResults) { showResults in
            if showResults {
                recordSessionIfNeeded()
            } else {
                // A fresh round (via Play Again / retry) starts here.
                didRecordThisRound = false
            }
        }
    }

    
    private func recordSessionIfNeeded() {
        guard !didRecordThisRound else { return }
        didRecordThisRound = true
        store.recordSession(gameName: "Quiz Rush", score: viewModel.score)
    }

    

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Fetching trivia…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Couldn't load questions")
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                viewModel.retry()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
    }

   

    private var quizContent: some View {
        VStack(spacing: 20) {
            header

            if let question = viewModel.currentQuestion {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(question.category.uppercased())
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Text(question.text)
                            .font(.title3.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 12) {
                            ForEach(question.answers, id: \.self) { answer in
                                QuizRushAnswerButton(
                                    text: answer,
                                    state: buttonState(for: answer, question: question)
                                ) {
                                    viewModel.selectAnswer(answer)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                }
                .modifier(QuizRushShakeEffect(shake: viewModel.lastAnswerWasCorrect == false))
                .animation(.default, value: viewModel.lastAnswerWasCorrect)
            }

            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.progressLabel)
                    .font(.subheadline.bold())
                Text("Score: \(viewModel.score)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("\(viewModel.streak)")
                    .font(.subheadline.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.15))
            .clipShape(Capsule())
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private func buttonState(for answer: String, question: QuizRushQuestion) -> QuizRushAnswerButton.VisualState {
        guard let selected = viewModel.selectedAnswer else { return .idle }

        if answer == question.correctAnswer {
            return .correct
        } else if answer == selected {
            return .wrong
        } else {
            return .disabled
        }
    }
}


struct QuizRushAnswerButton: View {
    enum VisualState {
        case idle, correct, wrong, disabled
    }

    let text: String
    let state: VisualState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.body.weight(.medium))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(border, lineWidth: 2)
                )
        }
        .disabled(state == .disabled || state == .correct || state == .wrong)
        .animation(.easeInOut(duration: 0.25), value: state)
    }

    private var background: Color {
        switch state {
        case .idle: return Color(.secondarySystemBackground)
        case .correct: return .green.opacity(0.25)
        case .wrong: return .red.opacity(0.25)
        case .disabled: return Color(.secondarySystemBackground).opacity(0.5)
        }
    }

    private var foreground: Color {
        switch state {
        case .disabled: return .secondary
        default: return .primary
        }
    }

    private var border: Color {
        switch state {
        case .correct: return .green
        case .wrong: return .red
        default: return .clear
        }
    }
}

/// A simple horizontal shake, applied to the question card on a wrong answer.
struct QuizRushShakeEffect: GeometryEffect {
    var shake: Bool
    var animatableData: CGFloat = 0

    init(shake: Bool) {
        self.shake = shake
        self.animatableData = shake ? 1 : 0
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let amount: CGFloat = 6
        let offset = sin(animatableData * .pi * 6) * amount * animatableData
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}


struct QuizRushResultsView: View {
    @ObservedObject var viewModel: QuizRushViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)

            Text("Round Complete!")
                .font(.title.bold())

            VStack(spacing: 8) {
                Text("Final Score")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.score)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
            }

            Text("out of \(viewModel.questions.count) questions")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                viewModel.playAgain()
            } label: {
                Label("Play Again", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 32)
        }
        .padding()
    }
}



#Preview {
    NavigationStack {
        QuizRushView()
            .environmentObject(GameSessionStore.shared)
    }
}
