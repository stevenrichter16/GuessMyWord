#if DEBUG
import Foundation

#if canImport(_0_Questions)
@testable import _0_Questions
#endif

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
        let facts = ItemFacts(item: target)
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

    private func autoAnswer(to question: String, facts: ItemFacts) -> Answer {
        let text = question.lowercased()

        if text.contains("electronic") || text.contains("electric") || text.contains("battery") || text.contains("plug") {
            return facts.isElectronic ? .yes : .no
        }
        if text.contains("animal") || text.contains("pet") {
            return facts.isAnimal ? .yes : .no
        }
        if text.contains("food") || text.contains("eat") || text.contains("edible") {
            return facts.isFood ? .yes : .no
        }
        if text.contains("kitchen") {
            return facts.usedInKitchen ? .yes : .no
        }
        if text.contains("office") || text.contains("desk") {
            return facts.usedInOffice ? .yes : .no
        }
        if text.contains("tool") || text.contains("repair") || text.contains("build") {
            return facts.isTool ? .yes : .no
        }
        if text.contains("toy") || text.contains("play") {
            return facts.isToy ? .yes : .no
        }
        if text.contains("backpack") || text.contains("pocket") || text.contains("carry") {
            return facts.fitsInBackpack ? .yes : .no
        }
        if text.contains("alive") || text.contains("living") {
            return facts.isAnimal ? .yes : .no
        }
        if text.contains("metal") {
            return facts.mostlyMetal ? .yes : .no
        }
        if text.contains("bigger than a microwave") || text.contains("bigger than microwave") || text.contains("larger than a microwave") {
            return facts.biggerThanMicrowave ? .yes : .no
        }
        if text.contains("water") {
            return facts.livesInWater ? .yes : .no
        }

        return .notSure
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

struct ItemFacts {
    let item: String
    let isElectronic: Bool
    let isAnimal: Bool
    let isFood: Bool
    let isTool: Bool
    let isToy: Bool
    let usedInKitchen: Bool
    let usedInOffice: Bool
    var fitsInBackpack: Bool
    let biggerThanMicrowave: Bool
    let mostlyMetal: Bool
    let livesInWater: Bool

    init(item: String) {
        let lower = item.lowercased()
        self.item = item

        let kitchen = Set(LLMScaffolding.kitchenItems.map { $0.lowercased() })
        let office = Set(LLMScaffolding.officeItems.map { $0.lowercased() })
        let animals = Set(LLMScaffolding.animalItems.map { $0.lowercased() })
        let tools = Set(LLMScaffolding.toolItems.map { $0.lowercased() })
        let produce = Set(LLMScaffolding.produceItems.map { $0.lowercased() })
        let toys = Set(LLMScaffolding.toyItems.map { $0.lowercased() })
        let electronics = Set(LLMScaffolding.electronicItems.map { $0.lowercased() })
        let edc = Set(LLMScaffolding.edcItems.map { $0.lowercased() })

        isElectronic = electronics.contains(lower) || ["microwave", "blender", "kettle", "drill", "desk lamp"].contains(lower)
        isAnimal = animals.contains(lower)
        isFood = produce.contains(lower)
        isTool = tools.contains(lower)
        isToy = toys.contains(lower)
        usedInKitchen = kitchen.contains(lower) || isFood
        usedInOffice = office.contains(lower)
        fitsInBackpack = !(["microwave", "horse", "cow"].contains(lower)) && !["desk", "monitor"].contains(lower) && !["bicycle"].contains(lower)
        biggerThanMicrowave = ["horse", "cow", "desk"].contains(lower)
        mostlyMetal = isTool || ["knife", "fork", "spoon", "scissors", "kettle", "flashlight"].contains(lower)
        livesInWater = ["goldfish", "fish", "duck", "frog"].contains(lower)

        if edc.contains(lower) { fitsInBackpack = true }
    }
}
#endif
