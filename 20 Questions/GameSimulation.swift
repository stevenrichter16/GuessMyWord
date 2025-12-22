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
    let log: SimulationRoundLog
}

struct SimulationStep {
    let entry: QAEntry
    let candidates: [String]
}

struct SimulationQuestionLog: Codable {
    let questionId: String
    let question: String
    let userAnswer: String
    let trueAnswer: String
    let persona: String?
    let usedUnknown: Bool
    let usedMistake: Bool
    let effectiveUnknownProb: Double?
    let effectiveMistakeProb: Double?
    let guessedFromUnknown: Bool?
    let wasContradiction: Bool?
    let answerOrigin: String?
    let topCandidates: [CandidateScore]?
}

struct CandidateScore: Codable {
    let name: String
    let score: Int
}

struct SimulationRoundLog: Codable {
    let target: String
    let guess: String
    let wasCorrect: Bool
    let questions: [SimulationQuestionLog]

    enum CodingKeys: String, CodingKey {
        case target
        case guess
        case wasCorrect
        case questions
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(guess, forKey: .guess)
        try container.encode(wasCorrect, forKey: .wasCorrect)
        try container.encode(questions, forKey: .questions)
    }

    init(target: String, guess: String, wasCorrect: Bool, questions: [SimulationQuestionLog]) {
        self.target = target
        self.guess = guess
        self.wasCorrect = wasCorrect
        self.questions = questions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(String.self, forKey: .target)
        guess = try container.decode(String.self, forKey: .guess)
        wasCorrect = try container.decode(Bool.self, forKey: .wasCorrect)
        questions = try container.decode([SimulationQuestionLog].self, forKey: .questions)
    }
}

struct GameSimulator {
    private let maxTurns: Int
    private let annStore: ANNDataStore?
    private let topKForQuestionSelection = 8
    private let personaConfig: SimPersonaConfig? = SimPersonaConfig.load()
    private let usePersonaSim: Bool
    private struct PersonaSample {
        let answer: Answer
        let usedUnknown: Bool
        let usedMistake: Bool
        let effectiveUnknown: Double
        let effectiveMistake: Double
        let guessedFromUnknown: Bool
    }

    init(maxTurns: Int = 20, usePersonaSim: Bool = false) {
        self.maxTurns = maxTurns
        self.annStore = LLMScaffolding.annStore
        self.usePersonaSim = usePersonaSim
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
        var questionLogs: [SimulationQuestionLog] = []
        var turn = 1
        let plannedContradictions = Set((1...maxTurns).shuffled().prefix(contradictions))
        var appliedContradictions: [Int] = []

        let personaContext = usePersonaSim ? pickPersona() : nil

        var annSession = ANNSession(store: annStore, topK: topKForQuestionSelection)

        while turn <= maxTurns {
            guard let nextQ = annSession.nextQuestion() else { break }
            let trueAnswer = autoAnswer(to: nextQ.text, facts: facts)
            let sampled = personaAnswer(
                questionId: nextQ.id,
                trueAnswer: trueAnswer,
                target: target,
                personaContext: personaContext
            )
            var answer = sampled.answer
            let contradictionApplied = plannedContradictions.contains(turn)
            if contradictionApplied {
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
            var usedUnknown = sampled.usedUnknown && answer == .notSure
            var usedMistake = sampled.usedMistake
            if contradictionApplied {
                usedMistake = true
            }
            if sampled.guessedFromUnknown && answer != trueAnswer && answer != .notSure {
                usedMistake = true
            }
            let origin: String
            if contradictionApplied {
                origin = "contradiction"
            } else if sampled.usedMistake {
                origin = "mistake"
            } else if sampled.guessedFromUnknown {
                origin = "unknown_guess"
            } else if usedUnknown {
                origin = "unknown"
            } else {
                origin = "truth"
            }
            let entry = QAEntry(turn: turn, question: nextQ.text, answer: answer)
            let snapshot = SimulationStep(entry: entry, candidates: annSession.currentCandidates())
            transcript.append(entry)
            steps.append(snapshot)
            annSession.recordAnswer(questionId: nextQ.id, answer: answer)
            let topCandidates = annSession.currentCandidatesWithScores(limit: 8)
            let questionLog = SimulationQuestionLog(
                questionId: nextQ.id,
                question: nextQ.text,
                userAnswer: answer.rawValue,
                trueAnswer: trueAnswer.rawValue,
                persona: personaContext?.name,
                usedUnknown: usedUnknown,
                usedMistake: usedMistake,
                effectiveUnknownProb: sampled.effectiveUnknown,
                effectiveMistakeProb: sampled.effectiveMistake,
                guessedFromUnknown: sampled.guessedFromUnknown,
                wasContradiction: contradictionApplied ? true : nil,
                answerOrigin: origin,
                topCandidates: topCandidates
            )
            questionLogs.append(questionLog)
            turn += 1
        }

        let guessName = annSession.bestGuess() ?? "unknown"
        let success = matches(guessName, target: target)
        let log = SimulationRoundLog(target: target, guess: guessName, wasCorrect: success, questions: questionLogs)
        return SimulationRun(target: target, transcript: transcript, steps: steps, guess: guessName, wasCorrect: success, flippedTurns: appliedContradictions.sorted(), log: log)
    }

    private func autoAnswer(to question: String, facts: AnimalFacts) -> Answer {
        return facts.answer(for: question)
    }

    private func pickPersona() -> (name: String, persona: SimPersonaConfig.Persona)? {
        guard let config = personaConfig, let entry = config.personas.randomElement() else { return nil }
        return (entry.key, entry.value)
    }

    private func personaAnswer(questionId: String, trueAnswer: Answer, target: String, personaContext: (name: String, persona: SimPersonaConfig.Persona)?) -> PersonaSample {
        guard let config = personaConfig, let personaContext = personaContext else {
            return PersonaSample(answer: trueAnswer, usedUnknown: false, usedMistake: false, effectiveUnknown: 0, effectiveMistake: 0, guessedFromUnknown: false)
        }
        let persona = personaContext.persona
        let lowerTarget = target.lowercased()
        // Determine familiarity tier multiplier
        let tier: String = config.familiarityTiers.first(where: { $0.value.contains(lowerTarget) })?.key ?? "medium"
        let tierMult = persona.tierMultiplier[tier] ?? 1.0
        // Determine question tags
        let tags = config.questionTags[questionId] ?? []
        let confidences = tags.compactMap { persona.questionTagConfidence[$0] }
        let avgConfidence = confidences.isEmpty ? 0.6 : confidences.reduce(0, +) / Double(confidences.count)

        let effectiveUnknown = max(0, min(1, persona.baseUnknown * tierMult * (1 - avgConfidence)))
        let effectiveMistake = max(0, min(1, persona.baseMistake * tierMult * (1 - avgConfidence)))

        // Sample unknown
        if Double.random(in: 0...1) < effectiveUnknown {
            // Riskiness/yesBias: occasionally turn uncertainty into a yes/no guess
            let risk = persona.riskiness
            if Double.random(in: 0...1) < risk {
                let yesTilt = 0.5 + persona.yesBias
                let guessedYes = Double.random(in: 0...1) < yesTilt
                return PersonaSample(
                    answer: guessedYes ? .yes : .no,
                    usedUnknown: false,
                    usedMistake: false,
                    effectiveUnknown: effectiveUnknown,
                    effectiveMistake: effectiveMistake,
                    guessedFromUnknown: true
                )
            }
            return PersonaSample(
                answer: .notSure,
                usedUnknown: true,
                usedMistake: false,
                effectiveUnknown: effectiveUnknown,
                effectiveMistake: effectiveMistake,
                guessedFromUnknown: false
            )
        }

        // Sample mistake
        if Double.random(in: 0...1) < effectiveMistake {
            // Bias mistakes toward confusion clusters
            if let cluster = config.confusionClusters.first(where: { $0.members.contains(lowerTarget) }),
               !cluster.biasWrongToward.isEmpty {
                // If bias exists and true answer is yes, flip to no; else flip to yes.
                let wrong: Answer = (trueAnswer == .yes) ? .no : .yes
                return PersonaSample(
                    answer: wrong,
                    usedUnknown: false,
                    usedMistake: true,
                    effectiveUnknown: effectiveUnknown,
                    effectiveMistake: effectiveMistake,
                    guessedFromUnknown: false
                )
            } else {
                let wrong: Answer = (trueAnswer == .yes) ? .no : .yes
                return PersonaSample(
                    answer: wrong,
                    usedUnknown: false,
                    usedMistake: true,
                    effectiveUnknown: effectiveUnknown,
                    effectiveMistake: effectiveMistake,
                    guessedFromUnknown: false
                )
            }
        }

        return PersonaSample(
            answer: trueAnswer,
            usedUnknown: false,
            usedMistake: false,
            effectiveUnknown: effectiveUnknown,
            effectiveMistake: effectiveMistake,
            guessedFromUnknown: false
        )
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
    private var scores: [AnimalId: Int] = [:]
    private let specialQuestions: [QuestionId: [AnimalId]] = [
        "flamingo_beak_curved": ["flamingo"],
        "flamingo_one_leg": ["flamingo"],
        "pelican_throat_pouch": ["pelican"],
        "pigeon_city_flyer": ["pigeon"],
        "shrimp_thin_antennae": ["shrimp", "lobster"],
        "lobster_big_claws": ["lobster", "shrimp"],
        "shrimp_small_size": ["shrimp", "lobster"],
        "penguin_flipper_wings": ["penguin", "duck", "goose", "pelican"],
        "penguin_waddle": ["penguin", "duck", "goose", "pelican"],
        "walrus_tusks": ["walrus", "seal"],
        "jellyfish_soft_body": ["jellyfish", "starfish"],
        "jellyfish_drifts": ["jellyfish", "starfish"],
        "falcon_sickle_wings": ["falcon", "hawk"],
        "falcon_bird_prey": ["falcon", "hawk"],
        "moose_long_legs": ["moose", "deer"],
        "moose_dark_coat": ["moose", "deer"],
        "hamster_wheel_habitat": ["hamster", "chinchilla"],
        "chinchilla_big_ears": ["chinchilla", "hamster"],
        "alligator_broad_snout": ["alligator", "crocodile"],
        "has_shell": ["armadillo"]
    ]
    private var answers: [QuestionId: Answer] = [:]
    private var asked: Set<QuestionId> = []
    private var rankedAnimals: [Animal]

    init(store: ANNDataStore?, topK: Int) {
        self.annStore = store
        self.allAnimals = store?.config.animals.map { Animal(id: $0.id, name: $0.name) } ?? []
        self.allQuestions = store?.config.questions.map { Question(id: $0.id, text: $0.text) } ?? []
        self.topK = topK
        self.rankedAnimals = allAnimals
        for animal in allAnimals {
            scores[animal.id] = 0
        }
    }

    mutating func recordAnswer(questionId: QuestionId, answer: Answer) {
        answers[questionId] = answer
        asked.insert(questionId)
        rerankAnimals()
    }

    func currentCandidates() -> [String] {
        Array(rankedAnimals.prefix(topK)).map { $0.name }
    }

    func currentCandidatesWithScores(limit: Int) -> [CandidateScore] {
        let slice = rankedAnimals.prefix(limit)
        return slice.map { CandidateScore(name: $0.name, score: scores[$0.id] ?? 0) }
    }

    func bestGuess() -> String? {
        rankedAnimals.first?.name
    }

    mutating func nextQuestion() -> Question? {
        let topAnimals = Array(rankedAnimals.prefix(topK))
        let topFiveIds = Set(rankedAnimals.prefix(5).map { $0.id })

        var bestQuestion: Question?
        var bestEntropy: Double = -Double.infinity
        var bestCoverage: Double = -Double.infinity

        for q in allQuestions where !asked.contains(q.id) {
            if let targets = specialQuestions[q.id] {
                if topFiveIds.isDisjoint(with: Set(targets)) {
                    continue
                }
            }
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
        // If no splitter was found (e.g., only one candidate left), fall back to the first unasked question.
        if let bestQuestion {
            return bestQuestion
        }
        return allQuestions.first(where: { !asked.contains($0.id) })
    }

    private mutating func rerankAnimals() {
        guard let store = annStore else { return }
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
