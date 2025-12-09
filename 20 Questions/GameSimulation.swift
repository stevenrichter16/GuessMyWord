#if DEBUG
import Foundation

struct SimulationReport {
    let totalRuns: Int
    let correct: Int
    let accuracy: Double
    let lastRun: SimulationRun?
    let runs: [SimulationRun]
}

struct SimulationRun {
    let target: String
    let transcript: [QAEntry]
    let steps: [SimulationStep]
    let guess: String
    let wasCorrect: Bool
    let flippedTurns: [Int]
}

struct SimulationStep {
    let entry: QAEntry
    let candidates: [String]
}

struct GameSimulator {
    private let maxTurns: Int
    private let annStore: ANNDataStore?
    private let topKForQuestionSelection = 8

    init(maxTurns: Int = 20) {
        self.maxTurns = maxTurns
        self.annStore = LLMScaffolding.annStore
    }

    func runSimulations(_ runs: Int = 20) async -> SimulationReport {
        let items = LLMScaffolding.defaultCanonicalItems
        var correct = 0
        var lastRun: SimulationRun?
        var collected: [SimulationRun] = []

        for _ in 0..<runs {
            guard let target = items.randomElement() else { continue }
            let result = await playSingle(target: target, contradictions: 0)
            lastRun = result
            if result.wasCorrect { correct += 1 }
            collected.append(result)
        }

        let accuracy = runs > 0 ? Double(correct) / Double(runs) : 0
        return SimulationReport(totalRuns: runs, correct: correct, accuracy: accuracy, lastRun: lastRun, runs: collected)
    }

    func runSimulationsWithContradictions(_ runs: Int = 5, contradictions: Int = 2) async -> SimulationReport {
        let items = LLMScaffolding.defaultCanonicalItems
        var correct = 0
        var lastRun: SimulationRun?
        var collected: [SimulationRun] = []

        for _ in 0..<runs {
            guard let target = items.randomElement() else { continue }
            let result = await playSingle(target: target, contradictions: contradictions)
            lastRun = result
            if result.wasCorrect { correct += 1 }
            collected.append(result)
        }

        let accuracy = runs > 0 ? Double(correct) / Double(runs) : 0
        return SimulationReport(totalRuns: runs, correct: correct, accuracy: accuracy, lastRun: lastRun, runs: collected)
    }

    private func playSingle(target: String, contradictions: Int) async -> SimulationRun {
        let facts = AnimalFacts(animal: target)
        var transcript: [QAEntry] = []
        var steps: [SimulationStep] = []
        var turn = 1
        let plannedContradictions = Set((1...maxTurns).shuffled().prefix(contradictions))
        var appliedContradictions: [Int] = []

        var annSession = ANNSession(store: annStore, topK: topKForQuestionSelection)

        while turn <= maxTurns {
            guard let nextQ = annSession.nextQuestion() else { break }
            var answer = autoAnswer(to: nextQ.text, facts: facts)
            if plannedContradictions.contains(turn) {
                switch answer {
                case .yes:
                    answer = .no
                    appliedContradictions.append(turn)
                case .no:
                    answer = .yes
                    appliedContradictions.append(turn)
                default:
                    break
                }
            }
            let entry = QAEntry(turn: turn, question: nextQ.text, answer: answer)
            let snapshot = SimulationStep(entry: entry, candidates: annSession.currentCandidates())
            transcript.append(entry)
            steps.append(snapshot)
            annSession.recordAnswer(questionId: nextQ.id, answer: answer)
            turn += 1
        }

        let guessName = annSession.bestGuess() ?? "unknown"
        let success = matches(guessName, target: target)
        return SimulationRun(target: target, transcript: transcript, steps: steps, guess: guessName, wasCorrect: success, flippedTurns: appliedContradictions.sorted())
    }

    private func autoAnswer(to question: String, facts: AnimalFacts) -> Answer {
        return facts.answer(for: question)
    }

    private func matches(_ guess: String, target: String) -> Bool {
        func normalize(_ value: String) -> String {
            value
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        return normalize(guess) == normalize(target)
    }
}

struct AnimalFacts {
    private let dataset = LLMScaffolding.animalDataset
    private let animal: String

    init(animal: String) {
        self.animal = animal
    }

    func answer(for question: String) -> Answer {
        guard
            let dataset,
            let key = dataset.features.first(where: { $0.question.lowercased() == question.lowercased() })?.key,
            let values = dataset.rows[animal],
            let value = values[key]
        else { return .notSure }

        if value == 1 { return .yes }
        if value == 0 { return .no }
        return .notSure
    }
}

private struct ANNSession {
    private let annStore: ANNDataStore?
    private let allAnimals: [Animal]
    private let allQuestions: [Question]
    private let topK: Int
    private var answers: [QuestionId: Answer] = [:]
    private var asked: Set<QuestionId> = []
    private var rankedAnimals: [Animal]

    init(store: ANNDataStore?, topK: Int) {
        self.annStore = store
        self.allAnimals = store?.config.animals.map { Animal(id: $0.id, name: $0.name) } ?? []
        self.allQuestions = store?.config.questions.map { Question(id: $0.id, text: $0.text) } ?? []
        self.topK = topK
        self.rankedAnimals = allAnimals
    }

    mutating func recordAnswer(questionId: QuestionId, answer: Answer) {
        answers[questionId] = answer
        asked.insert(questionId)
        rerankAnimals()
    }

    func currentCandidates() -> [String] {
        Array(rankedAnimals.prefix(topK)).map { $0.name }
    }

    func bestGuess() -> String? {
        rankedAnimals.first?.name
    }

    mutating func nextQuestion() -> Question? {
        let topAnimals = Array(rankedAnimals.prefix(topK))
        if topAnimals.count <= 1 { return nil }

        var bestQuestion: Question?
        var bestEntropy: Double = -Double.infinity
        var bestCoverage: Double = -Double.infinity

        for q in allQuestions where !asked.contains(q.id) {
            var yes = 0
            var no = 0
            for animal in topAnimals {
                let w = weight(for: animal.id, qid: q.id)
                if w > 0 { yes += 1 }
                else if w < 0 { no += 1 }
            }
            let unknown = max(0, topAnimals.count - (yes + no))
            let coverage = Double(yes + no) / Double(max(1, topAnimals.count))
            if (yes + no) < 2 || coverage < 0.1 { continue }
            let ent = entropy([yes, no, unknown])
            if ent > bestEntropy || (ent == bestEntropy && coverage > bestCoverage) {
                bestEntropy = ent
                bestCoverage = coverage
                bestQuestion = q
            }
        }
        return bestQuestion
    }

    private mutating func rerankAnimals() {
        guard let store = annStore else { return }
        var scores: [AnimalId: Int] = [:]
        for animal in allAnimals { scores[animal.id] = 0 }

        for (qid, ans) in answers {
            if let key = answerWeightKey(for: ans),
               let answerWeight = store.config.answerWeights[key],
               answerWeight != 0 {
                let delta = abs(answerWeight)
                for animal in allAnimals {
                    let cell = weight(for: animal.id, qid: qid)
                    guard cell != 0 else { continue }
                    let agree = (answerWeight > 0 && cell > 0) || (answerWeight < 0 && cell < 0)
                    scores[animal.id, default: 0] += agree ? delta : -delta
                }
            } else if ans == .maybe || ans == .notSure {
                // Weak nudge
                for animal in allAnimals {
                    let cell = weight(for: animal.id, qid: qid)
                    if cell > 0 { scores[animal.id, default: 0] += 1 }
                    else if cell < 0 { scores[animal.id, default: 0] -= 1 }
                }
            }
        }
        rankedAnimals = allAnimals.sorted { (scores[$0.id] ?? 0) > (scores[$1.id] ?? 0) }
    }

    private func weight(for animal: AnimalId, qid: QuestionId) -> Int {
        annStore?.weights[animal]?[qid] ?? 0
    }

    private func answerWeightKey(for answer: Answer) -> String? {
        switch answer {
        case .yes: return "YES"
        case .no: return "NO"
        case .maybe, .notSure: return "UNKNOWN"
        }
    }

    private func entropy(_ counts: [Int]) -> Double {
        let total = counts.reduce(0, +)
        guard total > 0 else { return 0 }
        return counts.reduce(0.0) { acc, c in
            guard c > 0 else { return acc }
            let p = Double(c) / Double(total)
            return acc - p * log2(p)
        }
    }
}
#endif
