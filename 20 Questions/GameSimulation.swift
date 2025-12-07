#if DEBUG
import Foundation

struct SimulationReport {
    let totalRuns: Int
    let correct: Int
    let accuracy: Double
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

        for _ in 0..<runs {
            guard let target = items.randomElement() else { continue }
            let success = await playSingle(target: target)
            if success { correct += 1 }
        }

        let accuracy = runs > 0 ? Double(correct) / Double(runs) : 0
        return SimulationReport(totalRuns: runs, correct: correct, accuracy: accuracy)
    }

    private func playSingle(target: String) async -> Bool {
        let facts = AnimalFacts(animal: target)
        var transcript: [QAEntry] = []
        var turn = 1
        var currentQuestion = await llm.nextQuestion(context: context(turn: turn, transcript: transcript, hint: nil))

        while true {
            let answer = autoAnswer(to: currentQuestion.question, facts: facts)
            transcript.append(QAEntry(turn: turn, question: currentQuestion.question, answer: answer))

            if turn >= maxTurns { break }
            turn += 1
            currentQuestion = await llm.nextQuestion(context: context(turn: turn, transcript: transcript, hint: nil))
        }

        let guess = await llm.makeGuess(context: context(turn: turn + 1, transcript: transcript, hint: nil))
        return matches(guess.guess, target: target)
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
