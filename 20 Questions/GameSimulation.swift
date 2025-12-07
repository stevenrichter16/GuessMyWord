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
    private let llm: LLMScaffolding
    private let maxTurns: Int

    init(llm: LLMScaffolding = LLMScaffolding(), maxTurns: Int = 10) {
        self.llm = llm
        self.maxTurns = maxTurns
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
        var currentQuestion = await llm.nextQuestion(context: context(turn: turn, transcript: transcript, hint: nil))
        let plannedContradictions = Set((1...maxTurns).shuffled().prefix(contradictions))
        var appliedContradictions: [Int] = []

        while true {
            var answer = autoAnswer(to: currentQuestion.question, facts: facts)
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
            let entry = QAEntry(turn: turn, question: currentQuestion.question, answer: answer)
            let snapshot = SimulationStep(entry: entry, candidates: candidates(for: transcript))
            transcript.append(entry)
            steps.append(snapshot)

            if turn >= maxTurns { break }
            turn += 1
            currentQuestion = await llm.nextQuestion(context: context(turn: turn, transcript: transcript, hint: nil))
        }

        let guess = await llm.makeGuess(context: context(turn: turn + 1, transcript: transcript, hint: nil))
        let success = matches(guess.guess, target: target)
        return SimulationRun(target: target, transcript: transcript, steps: steps, guess: guess.guess, wasCorrect: success, flippedTurns: appliedContradictions.sorted())
    }

    private func candidates(for transcript: [QAEntry]) -> [String] {
        guard let dataset = LLMScaffolding.animalDataset else { return [] }
        let engine = AnimalQuestionEngine(dataset: dataset)
        return dataset.animals.filter { animal in
            guard let facts = dataset.rows[animal] else { return false }
            for entry in transcript {
                guard let key = engine.featureKey(for: entry.question), let value = facts[key] else { continue }
                switch entry.answer {
                case .yes:
                    if value != 1 { return false }
                case .no:
                    if value != 0 { return false }
                default:
                    continue
                }
            }
            return true
        }
    }

    private func context(turn: Int, transcript: [QAEntry], hint: String?) -> PromptContext {
        PromptContext(
            turn: turn,
            maxTurns: maxTurns,
            transcript: transcript,
            allowedCategories: LLMScaffolding.defaultCategories,
            canonicalItems: LLMScaffolding.defaultCanonicalItems,
            hint: hint
        )
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
#endif
