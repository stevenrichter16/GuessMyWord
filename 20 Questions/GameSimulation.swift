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
    private let tieBreakGap = 4
    private let tieBreakCandidateCount = 3
    private var scores: [AnimalId: Int] = [:]
    private var heuristicBoosts: [AnimalId: Int] = [:]
    private var gateBoostLedger: [QuestionId: (animals: Set<AnimalId>, value: Int, ttl: Int)] = [:]
    private var confirmQueue: [QuestionId] = []
    private var pendingGateBoosts: [QuestionId: Answer] = [:]
    private let gateConfirmers: [QuestionId: [QuestionId]] = [
        "is_bird": ["has_feathers", "can_fly"],
        "lives_in_water": ["has_gills", "has_fins_or_flippers"],
        "is_mammal": ["has_fur_or_hair"],
        "is_reptile": [],
        "is_amphibian": ["has_gills"],
        "is_fish": ["has_gills", "has_fins_or_flippers"]
    ]
    private let specialQuestions = SpecialQuestionConfig.targets
    private var answers: [QuestionId: Answer] = [:]
    private var asked: Set<QuestionId> = []
    private var rankedAnimals: [Animal]
    private var lastTop: AnimalId?
    private func logSpecial(_ message: String) {
        #if DEBUG
        print("[SpecialGate] \(message)")
        #endif
    }

    init(store: ANNDataStore?, topK: Int) {
        self.annStore = store
        self.allAnimals = store?.config.animals.map { Animal(id: $0.id, name: $0.name) } ?? []
        self.allQuestions = store?.config.questions.map { Question(id: $0.id, text: $0.text) } ?? []
        self.topK = topK
        self.rankedAnimals = allAnimals
        for animal in allAnimals {
            scores[animal.id] = 0
            heuristicBoosts[animal.id] = 0
        }
        self.lastTop = rankedAnimals.first?.id
    }

    mutating func recordAnswer(questionId: QuestionId, answer: Answer) {
        let previousTop = rankedAnimals.first?.id
        decayGateBoosts()
        answers[questionId] = answer
        asked.insert(questionId)
        applyHeuristicBoost(for: questionId, answer: answer)
        resolvePendingGateBoosts()
        rerankAnimals()
        applyFamilyConfirmIfNeeded(previousTop: previousTop)
    }

    func currentCandidates() -> [String] {
        Array(rankedAnimals.prefix(topK)).map { $0.name }
    }

    func currentCandidatesWithScores(limit: Int) -> [CandidateScore] {
        let slice = rankedAnimals.prefix(limit)
        return slice.map { CandidateScore(name: $0.name, score: scores[$0.id] ?? 0) }
    }

    private func shouldAskSpecial(_ questionId: QuestionId) -> Bool {
        let top3 = rankedAnimals.prefix(3).map { "\($0.id):\(scores[$0.id] ?? 0)" }.joined(separator: ",")
        let gates = [
            "is_bird": answers["is_bird"]?.rawValue ?? "nil",
            "lives_in_water": answers["lives_in_water"]?.rawValue ?? "nil",
            "is_mammal": answers["is_mammal"]?.rawValue ?? "nil",
            "is_reptile": answers["is_reptile"]?.rawValue ?? "nil"
        ]
        logSpecial("check \(questionId) top3=\(top3) gates=\(gates)")
        // Gate shrimp/lobster discriminators until those two are the clear leaders.
        if questionId == "shrimp_thin_antennae" || questionId == "lobster_big_claws" || questionId == "shrimp_small_size" {
            // Only consider these after we've confirmed an aquatic path and not a mammal.
            if answers["lives_in_water"] != .yes {
                logSpecial("block \(questionId): lives_in_water != yes")
                return false
            }
            if answers["is_mammal"] == .yes {
                logSpecial("block \(questionId): is_mammal == yes")
                return false
            }
            let topTwo = rankedAnimals.prefix(2).map { $0.id }
            guard Set(topTwo) == Set(["shrimp", "lobster"]) else {
                logSpecial("block \(questionId): topTwo \(topTwo) not shrimp+lobster")
                return false
            }
            let topScores = topTwo.compactMap { scores[$0] }
            let othersMax = rankedAnimals.dropFirst(2).compactMap { scores[$0.id] }.max() ?? Int.min
            let pass = topScores.allSatisfy { $0 > othersMax }
            logSpecial("shrimp/lobster gate pass=\(pass) topScores=\(topScores) othersMax=\(othersMax)")
            return pass
        }
        // General rule: only ask a special if it is clearly relevant to the top candidates.
        guard let targets = specialQuestions[questionId] else { return true }
        let topThree = rankedAnimals.prefix(3)
        let targetTop = topThree.filter { targets.contains($0.id) }
        if targets.count == 1 {
            guard let targetId = targets.first else {
                logSpecial("block \(questionId): missing single target")
                return false
            }
            guard let targetScore = scores[targetId] else {
                logSpecial("block \(questionId): missing target score")
                return false
            }
            let topTwo = rankedAnimals.prefix(2).map { $0.id }
            guard topTwo.contains(targetId), let topScore = scores[rankedAnimals[0].id] else {
                logSpecial("block \(questionId): single target not in top2")
                return false
            }
            let closenessThreshold = 5
            if (topScore - targetScore) > closenessThreshold {
                logSpecial("block \(questionId): single target not close to top (diff \(topScore - targetScore))")
                return false
            }
            let othersMax = rankedAnimals.dropFirst(2).compactMap { scores[$0.id] }.max() ?? Int.min
            let pass = targetScore > othersMax
            logSpecial("single-target gate \(questionId) pass=\(pass) targetScore=\(targetScore) othersMax=\(othersMax)")
            return pass
        }

        guard targetTop.count >= 2 else {
            logSpecial("block \(questionId): fewer than two targets in top3")
            return false
        }

        let targetScores = targetTop.compactMap { scores[$0.id] }
        guard let minTarget = targetScores.min(), let maxTarget = targetScores.max() else {
            logSpecial("block \(questionId): missing target scores")
            return false
        }
        let closenessThreshold = 5
        if (maxTarget - minTarget) > closenessThreshold {
            logSpecial("block \(questionId): targets not close (range \(maxTarget - minTarget))")
            return false
        }

        let maxNonTarget = rankedAnimals.filter { !targets.contains($0.id) }.compactMap { scores[$0.id] }.max() ?? Int.min
        let pass = minTarget > maxNonTarget
        logSpecial("general gate \(questionId) pass=\(pass) minTarget=\(minTarget) maxNonTarget=\(maxNonTarget)")
        return pass
    }

    func bestGuess() -> String? {
        rankedAnimals.first?.name
    }

    mutating func nextQuestion() -> Question? {
        if let confirmId = confirmQueue.first(where: { !asked.contains($0) }),
           let confirm = allQuestions.first(where: { $0.id == confirmId }) {
            confirmQueue.removeAll(where: { $0 == confirmId })
            return confirm
        }
        let topAnimals = entropyCandidates()
        let topFiveIds = Set(rankedAnimals.prefix(5).map { $0.id })

        if let mandatory = specialQuestions.first(where: { key, value in
            !asked.contains(key) && Set(value).intersection(topFiveIds).count >= 2
        })?.key {
            let allowed = shouldAskSpecial(mandatory)
            logSpecial("mandatory candidate \(mandatory) allowed=\(allowed)")
            if allowed, let q = allQuestions.first(where: { $0.id == mandatory }) {
                return q
            }
        }

        if shouldUseTieBreak() {
            let topCandidates = Array(rankedAnimals.prefix(tieBreakCandidateCount))
            if let tieBreak = tieBreakQuestion(topCandidates: topCandidates, topAnimals: topAnimals, topFiveIds: topFiveIds) {
                return tieBreak
            }
        }

        var bestQuestion: Question?
        var bestEntropy: Double = -Double.infinity
        var bestCoverage: Double = -Double.infinity

        for q in allQuestions where !asked.contains(q.id) {
            if let targets = specialQuestions[q.id] {
                if topFiveIds.isDisjoint(with: Set(targets)) {
                    continue
                }
                if !shouldAskSpecial(q.id) {
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

    private func entropyCandidates() -> [Animal] {
        guard !rankedAnimals.isEmpty else { return [] }
        let baseCount = min(topK, rankedAnimals.count)
        let base = Array(rankedAnimals.prefix(baseCount))
        guard let cutoffId = base.last?.id else { return base }
        let cutoffScore = scores[cutoffId] ?? 0
        let expanded = rankedAnimals.filter { (scores[$0.id] ?? 0) >= cutoffScore }
        return expanded.count > base.count ? expanded : base
    }

    private func shouldUseTieBreak() -> Bool {
        guard rankedAnimals.count >= 2,
              let topScore = scores[rankedAnimals[0].id],
              let secondScore = scores[rankedAnimals[1].id] else {
            return false
        }
        return (topScore - secondScore) <= tieBreakGap
    }

    private func tieBreakQuestion(
        topCandidates: [Animal],
        topAnimals: [Animal],
        topFiveIds: Set<AnimalId>
    ) -> Question? {
        guard topCandidates.count >= 2 else { return nil }
        var bestQuestion: Question?
        var bestDisagreement = 0
        var bestCoverage: Double = -Double.infinity
        var bestEntropy: Double = -Double.infinity

        for q in allQuestions where !asked.contains(q.id) {
            if let targets = specialQuestions[q.id] {
                if topFiveIds.isDisjoint(with: Set(targets)) {
                    continue
                }
                if !shouldAskSpecial(q.id) {
                    continue
                }
            }

            let disagreement = disagreementScore(qid: q.id, candidates: topCandidates)
            if disagreement == 0 { continue }

            var yes = 0
            var no = 0
            for animal in topAnimals {
                let w = weight(for: animal.id, qid: q.id)
                if w > 0 { yes += 1 }
                else if w < 0 { no += 1 }
            }
            let coverage = Double(yes + no) / Double(max(1, topAnimals.count))
            if (yes + no) < 2 || coverage < 0.1 { continue }

            let unknown = max(0, topAnimals.count - (yes + no))
            let ent = entropy([yes, no, unknown])

            if disagreement > bestDisagreement ||
                (disagreement == bestDisagreement && coverage > bestCoverage) ||
                (disagreement == bestDisagreement && coverage == bestCoverage && ent > bestEntropy) {
                bestDisagreement = disagreement
                bestCoverage = coverage
                bestEntropy = ent
                bestQuestion = q
            }
        }

        return bestQuestion
    }

    private func disagreementScore(qid: QuestionId, candidates: [Animal]) -> Int {
        var signs: [Int] = []
        signs.reserveCapacity(candidates.count)
        for animal in candidates {
            let w = weight(for: animal.id, qid: qid)
            if w == 0 {
                signs.append(0)
            } else {
                signs.append(w > 0 ? 1 : -1)
            }
        }

        var score = 0
        for i in 0..<signs.count {
            for j in (i + 1)..<signs.count {
                let a = signs[i]
                let b = signs[j]
                if a == b { continue }
                if a == 0 || b == 0 {
                    score += 1
                } else {
                    score += 2
                }
            }
        }
        return score
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
                let gateIds: Set<QuestionId> = ["is_bird", "lives_in_water", "is_mammal", "is_reptile", "is_amphibian", "is_fish"]
                if gateIds.contains(qid) || specialQuestions.keys.contains(qid) {
                    continue
                }
                for animal in allAnimals {
                    let cell = weight(for: animal.id, qid: qid)
                    if cell > 0 { scores[animal.id, default: 0] += 1 }
                    else if cell < 0 { scores[animal.id, default: 0] -= 1 }
                }
            }
        }
        for (aid, boost) in heuristicBoosts {
            scores[aid, default: 0] += boost
        }
        rankedAnimals = allAnimals.sorted { (scores[$0.id] ?? 0) > (scores[$1.id] ?? 0) }
    }

    private mutating func applyHeuristicBoost(for questionId: QuestionId, answer: Answer) {
        guard answer == .yes || answer == .no else { return }
        let relevant = ["is_bird", "lives_in_water", "is_mammal", "is_reptile", "is_amphibian", "is_fish"]
        guard relevant.contains(questionId) else { return }
        guard let topCandidate = rankedAnimals.first else { return }
        let targets = Set(allAnimals.compactMap { animal -> AnimalId? in
            let w = weight(for: animal.id, qid: questionId)
            return w > 0 ? animal.id : nil
        })
        let topWeight = weight(for: topCandidate.id, qid: questionId)
        let wantsPositive = answer == .yes
        let conflict = (wantsPositive && topWeight < 0) || (!wantsPositive && topWeight > 0)

        if conflict {
            pendingGateBoosts[questionId] = answer
            if let confirm = gateConfirmers[questionId]?.first(where: { !asked.contains($0) && !confirmQueue.contains($0) }) {
                confirmQueue.append(confirm)
            }
            return
        }

        enqueueForcedDiscriminatorIfNeeded(for: questionId, answer: answer)
        applyGateBoost(for: questionId, answer: answer, targets: targets)
    }

    private mutating func applyGateBoost(for questionId: QuestionId, answer: Answer, targets: Set<AnimalId>) {
        let boostValue = 10
        let cap = 20
        if let existing = gateBoostLedger[questionId] {
            for id in existing.animals {
                heuristicBoosts[id, default: 0] -= existing.value
            }
        }
        let consistent: Set<AnimalId> = Set(allAnimals.compactMap { animal in
            let w = weight(for: animal.id, qid: questionId)
            if answer == .yes && w > 0 { return animal.id }
            if answer == .no && w < 0 { return animal.id }
            return nil
        })
        for id in consistent {
            let current = heuristicBoosts[id, default: 0]
            let clamped = max(-cap, min(cap, current + boostValue))
            heuristicBoosts[id] = clamped
        }
        gateBoostLedger[questionId] = (animals: consistent, value: boostValue, ttl: 3)
    }

    private mutating func resolvePendingGateBoosts() {
        guard let top = rankedAnimals.first else { return }
        var toRemove: [QuestionId] = []
        for (gate, ans) in pendingGateBoosts {
            let topWeight = weight(for: top.id, qid: gate)
            let wantsPositive = ans == .yes
            let conflict = (wantsPositive && topWeight < 0) || (!wantsPositive && topWeight > 0)
            if conflict { continue }
            let targets = Set(allAnimals.compactMap { animal -> AnimalId? in
                let w = weight(for: animal.id, qid: gate)
                return w > 0 ? animal.id : nil
            })
            applyGateBoost(for: gate, answer: ans, targets: targets)
            toRemove.append(gate)
        }
        toRemove.forEach { pendingGateBoosts.removeValue(forKey: $0) }
    }

    private mutating func decayGateBoosts() {
        var expired: [QuestionId] = []
        for (qid, entry) in gateBoostLedger {
            let newTTL = entry.ttl - 1
            if newTTL <= 0 {
                for id in entry.animals {
                    heuristicBoosts[id, default: 0] -= entry.value
                }
                expired.append(qid)
            } else {
                gateBoostLedger[qid] = (entry.animals, entry.value, newTTL)
            }
        }
        expired.forEach { gateBoostLedger.removeValue(forKey: $0) }
    }

    private mutating func enqueueForcedDiscriminatorIfNeeded(for gateId: QuestionId, answer: Answer) {
        guard answer == .yes else { return }
        let topThree = Set(rankedAnimals.prefix(3).map { $0.id })
        func enqueue(_ qid: QuestionId) {
            if !asked.contains(qid) && !confirmQueue.contains(qid) {
                confirmQueue.append(qid)
            }
        }
        if topThree.contains("penguin") && (topThree.contains("pelican") || topThree.contains("flamingo") || topThree.contains("goose") || topThree.contains("duck") || topThree.contains("swan")) {
            enqueue("penguin_flipper_wings")
            enqueue("pelican_throat_pouch")
        }
        if topThree.contains("shrimp") && topThree.contains("lobster") {
            enqueue("lobster_big_claws")
        }
        if topThree.contains("hamster") && topThree.contains("chinchilla") {
            enqueue("chinchilla_big_ears")
            enqueue("hamster_wheel_habitat")
        }
        let hoofed: Set<AnimalId> = ["cow", "horse", "goat", "sheep", "bison", "zebra", "camel", "donkey", "alpaca", "llama", "deer", "moose"]
        if topThree.contains("porcupine") && !hoofed.intersection(topThree).isEmpty {
            enqueue("has_hooves")
        }
    }

    private mutating func applyFamilyConfirmIfNeeded(previousTop: AnimalId?) {
        defer { lastTop = rankedAnimals.first?.id }
        guard let old = previousTop, let newTop = rankedAnimals.first?.id, old != newTop else { return }
        let mammalWeightOld = weight(for: old, qid: "is_mammal")
        let mammalWeightNew = weight(for: newTop, qid: "is_mammal")
        let mismatch = (mammalWeightOld > 0) != (mammalWeightNew > 0)
        if mismatch {
            if !asked.contains("has_tail") && !confirmQueue.contains("has_tail") {
                confirmQueue.append("has_tail")
            } else if !asked.contains("has_hooves") && !confirmQueue.contains("has_hooves") {
                confirmQueue.append("has_hooves")
            }
        }
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
