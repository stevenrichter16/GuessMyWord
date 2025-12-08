import SwiftUI

struct Animal: Identifiable, Equatable {
    let id: AnimalId
    let name: String
}

struct Question: Identifiable, Equatable {
    let id: QuestionId
    let text: String
}

final class ANNGameViewModel: ObservableObject {
    @Published var currentQuestion: Question?
    @Published var currentGuess: Animal?
    @Published var isFinished: Bool = false
    @Published var debugRemainingNames: [String] = []
    @Published var statusMessage: String?

    private let annStore: ANNDataStore
    private let allAnimals: [Animal]
    private let allQuestions: [Question]

    private var remainingAnimals: [Animal] = []
    private var answers: [QuestionId: Answer] = [:]
    private var askedQuestions: Set<QuestionId> = []

    private let maxQuestions = 20
    private let topKForQuestionSelection = 8

    init?(annStore: ANNDataStore? = LLMScaffolding.annStore ?? ANNDataStore()) {
        guard let store = annStore else { return nil }
        self.annStore = store

        self.allAnimals = store.config.animals.map { Animal(id: $0.id, name: $0.name) }
        self.allQuestions = store.config.questions.map { Question(id: $0.id, text: $0.text) }
        self.remainingAnimals = allAnimals
        self.debugRemainingNames = remainingAnimals.map(\.name)
        runStep()
    }

    func answerCurrentQuestion(_ answer: Answer) {
        guard let q = currentQuestion else { return }
        answers[q.id] = answer
        askedQuestions.insert(q.id)
        rerankAnimals()
        runStep()
    }

    func restart() {
        answers.removeAll()
        askedQuestions.removeAll()
        remainingAnimals = allAnimals
        currentQuestion = nil
        currentGuess = nil
        isFinished = false
        debugRemainingNames = remainingAnimals.map(\.name)
        runStep()
    }

    var currentTurn: Int {
        // 1-based index of the next question to ask.
        return answers.count + 1
    }

    var maxTurnCount: Int { maxQuestions }

    func finalizeGame(correct: Bool) {
        guard let guessed = currentGuess else { return }
        if correct {
            learnFromGame(correctAnimalId: guessed.id)
            statusMessage = "Updated weights for \(guessed.name)."
        } else {
            statusMessage = "No weight changes applied."
        }
        isFinished = true
    }

    private func runStep() {
        if remainingAnimals.count == 1 {
            currentGuess = remainingAnimals.first
            currentQuestion = nil
            isFinished = true
            return
        }

        if answers.count >= maxQuestions {
            if let best = remainingAnimals.first {
                currentGuess = best
            }
            currentQuestion = nil
            isFinished = true
            return
        }

        if let nextQ = chooseNextQuestion() {
            currentQuestion = nextQ
            currentGuess = nil
            isFinished = false
        } else {
            if let best = remainingAnimals.first {
                currentGuess = best
            }
            currentQuestion = nil
            isFinished = true
        }
    }

    private func rerankAnimals() {
        var scores: [AnimalId: Int] = [:]
        for animal in allAnimals {
            scores[animal.id] = 0
        }

        for (qId, answer) in answers {
            guard let key = answerWeightKey(for: answer),
                  let answerWeight = annStore.config.answerWeights[key],
                  answerWeight != 0 else { continue }

            let deltaMagnitude = abs(answerWeight)

            for animal in allAnimals {
                let cellWeight = annStore.weight(for: animal.id, questionId: qId)
                guard cellWeight != 0 else { continue }

                let agree = (answerWeight > 0 && cellWeight > 0) ||
                            (answerWeight < 0 && cellWeight < 0)

                if agree {
                    scores[animal.id, default: 0] += deltaMagnitude
                } else {
                    scores[animal.id, default: 0] -= deltaMagnitude
                }
            }
        }

        let ranked = allAnimals.sorted { a, b in
            let sa = scores[a.id] ?? 0
            let sb = scores[b.id] ?? 0
            return sa > sb
        }

        let topSlice = ranked.prefix(topKForQuestionSelection)
        remainingAnimals = Array(topSlice)
        debugRemainingNames = remainingAnimals.map(\.name)
    }

    private func chooseNextQuestion() -> Question? {
        let topAnimals = remainingAnimals
        let n = topAnimals.count
        guard n > 1 else { return nil }

        var bestQuestion: Question?
        var bestMargin: Int?

        for q in allQuestions {
            if askedQuestions.contains(q.id) { continue }

            var yesCount = 0
            var noCount = 0
            var usedCount = 0

            for animal in topAnimals {
                let w = annStore.weight(for: animal.id, questionId: q.id)
                if w > 0 {
                    yesCount += 1
                    usedCount += 1
                } else if w < 0 {
                    noCount += 1
                    usedCount += 1
                }
            }

            if usedCount < 2 { continue }

            let margin = abs(yesCount - noCount)

            if let best = bestMargin {
                if margin < best {
                    bestMargin = margin
                    bestQuestion = q
                }
            } else {
                bestMargin = margin
                bestQuestion = q
            }
        }

        return bestQuestion
    }

    private func learnFromGame(correctAnimalId: AnimalId) {
        for (qId, answer) in answers {
            guard let key = answerWeightKey(for: answer),
                  let delta = annStore.config.answerWeights[key],
                  delta != 0 else { continue }

            if answer == .maybe || answer == .notSure { continue }
            annStore.addToWeight(delta, for: correctAnimalId, questionId: qId)
        }
    }

    private func answerWeightKey(for answer: Answer) -> String? {
        switch answer {
        case .yes: return "YES"
        case .no: return "NO"
        case .maybe, .notSure: return "UNKNOWN"
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ANNGameViewModel()!
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    header
                    progressBar

                    Group {
                        if let question = viewModel.currentQuestion, !viewModel.isFinished {
                            questionCard(question)
                            answerButtons
                        } else if let guess = viewModel.currentGuess {
                            guessCard(guess)
                        } else {
                            fallbackCard
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.currentQuestion?.id)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.currentGuess?.id)

                    debugStrip
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("20 Questions: Animals")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Think of an animal")
                .font(.largeTitle.bold())
            Text("Answer up to \(viewModel.maxTurnCount) questions. We'll adapt as you teach us.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressBar: some View {
        let fraction = max(0, min(1, Double(viewModel.currentTurn - 1) / Double(viewModel.maxTurnCount)))
        let track = Color.primary.opacity(colorScheme == .dark ? 0.25 : 0.08)
        let active = colorScheme == .dark
            ? LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [.blue, .pink], startPoint: .leading, endPoint: .trailing)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Progress")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Q\(viewModel.currentTurn) / \(viewModel.maxTurnCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                    .frame(height: 10)
                Capsule()
                    .fill(active)
                    .frame(width: max(24, fraction * UIScreen.main.bounds.width * 0.6), height: 10)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardFill)
                .shadow(color: shadowColor, radius: 10, x: 0, y: 6)
        )
    }

    private func questionCard(_ question: Question) -> some View {
        VStack(spacing: 12) {
            Text("Question \(viewModel.currentTurn)")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(question.text)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(cardFill)
                .shadow(color: shadowColor, radius: 12, x: 0, y: 8)
        )
    }

    private var answerButtons: some View {
        HStack(spacing: 12) {
            AnswerButton(title: "Yes", color: .green, scheme: colorScheme) {
                viewModel.answerCurrentQuestion(.yes)
            }
            AnswerButton(title: "No", color: .red, scheme: colorScheme) {
                viewModel.answerCurrentQuestion(.no)
            }
            AnswerButton(title: "Not sure", color: .blue, scheme: colorScheme) {
                viewModel.answerCurrentQuestion(.notSure)
            }
        }
        .padding(.horizontal, 4)
    }

    private func guessCard(_ guess: Animal) -> some View {
        VStack(spacing: 14) {
            Text("Your animal is...")
                .font(.headline)
            Text(guess.name)
                .font(.largeTitle.bold())
            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Confirm to teach the ANN.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                AnswerButton(title: "Correct", color: .green, scheme: colorScheme) {
                    viewModel.finalizeGame(correct: true)
                }
                AnswerButton(title: "Wrong", color: .orange, scheme: colorScheme) {
                    viewModel.finalizeGame(correct: false)
                }
            }

            Button {
                viewModel.restart()
            } label: {
                Text("Play again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(cardFill)
                .shadow(color: shadowColor, radius: 14, x: 0, y: 8)
        )
    }

    private var fallbackCard: some View {
        VStack(spacing: 10) {
            Text("I'm out of ideas.")
                .font(.headline)
            Button("Play again") {
                viewModel.restart()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardFill)
                .shadow(color: shadowColor, radius: 10, x: 0, y: 6)
        )
    }

    private var debugStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top animals (debug)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(viewModel.debugRemainingNames.joined(separator: ", "))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardFill.opacity(0.9))
        )
    }

    private var cardFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white.opacity(0.9)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.1)
    }

    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.2), Color(red: 0.15, green: 0.05, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color.blue.opacity(0.12), Color.pink.opacity(0.12), Color.orange.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct AnswerButton: View {
    let title: String
    let color: Color
    let scheme: ColorScheme
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(buttonBackground)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(scheme == .dark ? 0.6 : 0.4), lineWidth: 1)
        )
        .shadow(color: color.opacity(0.35), radius: 8, x: 0, y: 5)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    private var buttonBackground: LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [color.opacity(0.35), color.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [color.opacity(0.18), color.opacity(0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
