import SwiftUI

struct Animal: Identifiable, Equatable {
    let id: AnimalId
    let name: String
}

struct Question: Identifiable, Equatable {
    let id: QuestionId
    let text: String
}

struct ReplayStepData: Identifiable {
    let id = UUID()
    let question: String
    let answer: Answer
    let candidates: [String]
}

final class ANNGameViewModel: ObservableObject {
    @Published var currentQuestion: Question?
    @Published var currentGuess: Animal?
    @Published var isFinished: Bool = false
    @Published var debugRemainingNames: [String] = []
    @Published var statusMessage: String?
    @Published var lastGuessWasWrong: Bool = false
    @Published var replaySteps: [ReplayStepData] = []

    private let annStore: ANNDataStore
    private let allAnimals: [Animal]
    private let allQuestions: [Question]

    private var remainingAnimals: [Animal] = []
    private var rankedAnimals: [Animal] = []
    private var scores: [AnimalId: Int] = [:]
    private var answers: [QuestionId: Answer] = [:]
    private var askedQuestions: Set<QuestionId> = []

    private let maxQuestions = 20
    private let topKForQuestionSelection = 8
    private let tieBreakGap = 4
    private let tieBreakCandidateCount = 3
    private let topTwoDiscriminatorBoost = 0.5
    private let specialQuestions = SpecialQuestionConfig.targets
    private let questionImportance: [QuestionId: Int] = [
        // Reliability-heavy signal: if true, should swing the ranking harder.
        "is_venomous": 3,
        "has_feathers": 2,
        "is_bigger_than_car": 2
    ]

    init?(annStore: ANNDataStore? = LLMScaffolding.annStore ?? ANNDataStore()) {
        guard let store = annStore else { return nil }
        self.annStore = store

        self.allAnimals = store.config.animals.map { Animal(id: $0.id, name: $0.name) }
        self.allQuestions = store.config.questions.map { Question(id: $0.id, text: $0.text) }
        self.remainingAnimals = allAnimals
        self.rankedAnimals = allAnimals
        self.scores = Dictionary(uniqueKeysWithValues: allAnimals.map { ($0.id, 0) })
        self.debugRemainingNames = remainingAnimals.map(\.name)
        runStep()
    }

    func answerCurrentQuestion(_ answer: Answer) {
        guard let q = currentQuestion else { return }
        answers[q.id] = answer
        askedQuestions.insert(q.id)
        rerankAnimals()
        let snapshot = ReplayStepData(question: q.text, answer: answer, candidates: debugRemainingNames)
        replaySteps.append(snapshot)
        runStep()
    }

    func restart() {
        answers.removeAll()
        askedQuestions.removeAll()
        remainingAnimals = allAnimals
        rankedAnimals = allAnimals
        scores = Dictionary(uniqueKeysWithValues: allAnimals.map { ($0.id, 0) })
        currentQuestion = nil
        currentGuess = nil
        isFinished = false
        lastGuessWasWrong = false
        debugRemainingNames = remainingAnimals.map(\.name)
        replaySteps = []
        runStep()
    }

    var currentTurn: Int {
        // 1-based index of the next question to ask.
        return answers.count + 1
    }

    var maxTurnCount: Int { maxQuestions }
    var topCandidateNames: [String] {
        remainingAnimals.map { $0.name }
    }

    func finalizeGame(correct: Bool) {
        guard let guessed = currentGuess else { return }
        if correct {
            //learnFromGame(correctAnimalId: guessed.id)
            //statusMessage = "Updated weights for \(guessed.name)."
            lastGuessWasWrong = false
        } else {
            //statusMessage = "No weight changes applied."
            lastGuessWasWrong = true
        }
        isFinished = true
    }

    func topCandidatesIfWrong() -> [String]? {
        guard let guessName = currentGuess?.name else { return nil }
        let filtered = topCandidateNames.filter { $0 != guessName }
        let slice = filtered.prefix(6)
        return slice.isEmpty ? nil : Array(slice)
    }

    private func runStep() {
        if remainingAnimals.count == 1 {
            currentGuess = remainingAnimals.first
            currentQuestion = nil
            isFinished = false
            return
        }

        if answers.count >= maxQuestions {
            if let best = remainingAnimals.first {
                currentGuess = best
            }
            currentQuestion = nil
            isFinished = false
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
            isFinished = currentGuess == nil
        }
    }

    private func rerankAnimals() {
        var newScores: [AnimalId: Int] = [:]
        for animal in allAnimals {
            newScores[animal.id] = 0
        }

        for (qId, answer) in answers {
            guard let key = answerWeightKey(for: answer),
                  let answerWeight = annStore.config.answerWeights[key],
                  answerWeight != 0 else {
                // Handle weak evidence for unknown: use small magnitude in the direction of the cell sign.
                applyUnknownNudge(for: qId, to: &newScores, answer: answer)
                continue
            }

            let deltaMagnitude = abs(answerWeight) * importance(for: qId)

            for animal in allAnimals {
                let cellWeight = annStore.weight(for: animal.id, questionId: qId)
                guard cellWeight != 0 else { continue }

                let agree = (answerWeight > 0 && cellWeight > 0) ||
                            (answerWeight < 0 && cellWeight < 0)

                if agree {
                    newScores[animal.id, default: 0] += deltaMagnitude
                } else {
                    newScores[animal.id, default: 0] -= deltaMagnitude
                }
            }
        }

        let ranked = allAnimals.sorted { a, b in
            let sa = newScores[a.id] ?? 0
            let sb = newScores[b.id] ?? 0
            return sa > sb
        }

        scores = newScores
        rankedAnimals = ranked
        let topSlice = ranked.prefix(topKForQuestionSelection)
        remainingAnimals = Array(topSlice)
        debugRemainingNames = remainingAnimals.map(\.name)
    }

    private func applyUnknownNudge(for qId: QuestionId, to scores: inout [AnimalId: Int], answer: Answer) {
        guard answer == .maybe || answer == .notSure else { return }
        let weakDelta = 1
        for animal in allAnimals {
            let cellWeight = annStore.weight(for: animal.id, questionId: qId)
            if cellWeight > 0 {
                scores[animal.id, default: 0] += weakDelta
            } else if cellWeight < 0 {
                scores[animal.id, default: 0] -= weakDelta
            }
        }
    }

    private func chooseNextQuestion() -> Question? {
        let topAnimals = entropyCandidates()
        let n = topAnimals.count
        guard n > 1 else { return nil }
        let topFiveIds = Set(rankedAnimals.prefix(5).map { $0.id })

        // Build signature of already asked questions to avoid near-duplicate splits.
        var seenSignatures: Set<String> = []
        for qId in askedQuestions {
            let sig = splitSignature(questionId: qId, animals: topAnimals)
            if !sig.isEmpty { seenSignatures.insert(sig) }
        }

        if shouldUseTieBreak() {
            let topCandidates = Array(rankedAnimals.prefix(tieBreakCandidateCount))
            if let tieBreak = tieBreakQuestion(
                topCandidates: topCandidates,
                topAnimals: topAnimals,
                topFiveIds: topFiveIds,
                seenSignatures: seenSignatures
            ) {
                return tieBreak
            }
        }

        let turn = answers.count + 1
        let unknownRate = currentUnknownRate()

        var bestQuestion: Question?
        var bestScore: Double = -Double.infinity
        var bestCoverage: Double = -Double.infinity

        for q in allQuestions {
            if askedQuestions.contains(q.id) { continue }
            if shouldSkipQuestion(q.id) { continue }
            if let targets = specialQuestions[q.id] {
                if topFiveIds.isDisjoint(with: Set(targets)) {
                    continue
                }
                if !shouldAskSpecial(q.id) {
                    continue
                }
            }

            var yesCount = 0
            var noCount = 0

            for animal in topAnimals {
                let w = annStore.weight(for: animal.id, questionId: q.id)
                if w > 0 {
                    yesCount += 1
                } else if w < 0 {
                    noCount += 1
                }
            }

            let unknownCount = max(0, n - (yesCount + noCount))
            let entropyVal = entropy([yesCount, noCount, unknownCount])
            let coverage = Double(yesCount + noCount) / Double(n)
            // Require at least two non-zero responses and some coverage
            if (yesCount + noCount) < 2 || coverage < 0.1 { continue }

            // Repeat blocker: skip if signature matches a prior asked question.
            let sig = splitSignature(questionId: q.id, animals: topAnimals)
            if seenSignatures.contains(sig) { continue }

            let reliability = QuestionReliability.weight(
                questionId: q.id,
                turn: turn,
                unknownRate: unknownRate,
                persona: nil
            )
            let discriminatorBonus = topTwoDiscriminatorBonus(questionId: q.id)
            let score = entropyVal * reliability * discriminatorBonus
            if score > bestScore || (score == bestScore && coverage > bestCoverage) {
                bestScore = score
                bestCoverage = coverage
                bestQuestion = q
            }
        }

        return bestQuestion
    }

    private func currentUnknownRate() -> Double {
        guard !answers.isEmpty else { return 0 }
        let unknownCount = answers.values.filter { $0 == .maybe || $0 == .notSure }.count
        return Double(unknownCount) / Double(answers.count)
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
        topFiveIds: Set<AnimalId>,
        seenSignatures: Set<String>
    ) -> Question? {
        guard topCandidates.count >= 2 else { return nil }
        let turn = answers.count + 1
        let unknownRate = currentUnknownRate()
        var bestQuestion: Question?
        var bestDisagreement = -Double.infinity
        var bestCoverage: Double = -Double.infinity
        var bestEntropy: Double = -Double.infinity

        for q in allQuestions {
            if askedQuestions.contains(q.id) { continue }
            if shouldSkipQuestion(q.id) { continue }
            if let targets = specialQuestions[q.id] {
                if topFiveIds.isDisjoint(with: Set(targets)) {
                    continue
                }
                if !shouldAskSpecial(q.id) {
                    continue
                }
            }

            let disagreement = disagreementScore(questionId: q.id, candidates: topCandidates)
            if disagreement == 0 { continue }

            var yesCount = 0
            var noCount = 0
            for animal in topAnimals {
                let w = annStore.weight(for: animal.id, questionId: q.id)
                if w > 0 { yesCount += 1 }
                else if w < 0 { noCount += 1 }
            }
            let coverage = Double(yesCount + noCount) / Double(max(1, topAnimals.count))
            if (yesCount + noCount) < 2 || coverage < 0.1 { continue }

            let sig = splitSignature(questionId: q.id, animals: topAnimals)
            if seenSignatures.contains(sig) { continue }

            let unknownCount = max(0, topAnimals.count - (yesCount + noCount))
            let entropyVal = entropy([yesCount, noCount, unknownCount])
            let reliability = QuestionReliability.weight(
                questionId: q.id,
                turn: turn,
                unknownRate: unknownRate,
                persona: nil
            )
            let weightedDisagreement = Double(disagreement) * reliability * topTwoDiscriminatorBonus(questionId: q.id)

            if weightedDisagreement > bestDisagreement ||
                (weightedDisagreement == bestDisagreement && coverage > bestCoverage) ||
                (weightedDisagreement == bestDisagreement && coverage == bestCoverage && entropyVal > bestEntropy) {
                bestDisagreement = weightedDisagreement
                bestCoverage = coverage
                bestEntropy = entropyVal
                bestQuestion = q
            }
        }

        return bestQuestion
    }

    private func disagreementScore(questionId: QuestionId, candidates: [Animal]) -> Int {
        var signs: [Int] = []
        signs.reserveCapacity(candidates.count)
        for animal in candidates {
            let w = annStore.weight(for: animal.id, questionId: questionId)
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

    private func topTwoDiscriminatorBonus(questionId: QuestionId) -> Double {
        let strength = topTwoDiscriminatorStrength(questionId: questionId)
        return 1.0 + (topTwoDiscriminatorBoost * strength)
    }

    private func topTwoDiscriminatorStrength(questionId: QuestionId) -> Double {
        guard rankedAnimals.count >= 2 else { return 0 }
        let topOne = rankedAnimals[0].id
        let topTwo = rankedAnimals[1].id
        if questionId == "has_spots", Set([topOne, topTwo]) == Set(["bison", "giraffe"]) {
            return 1.0
        }
        let w1 = annStore.weight(for: topOne, questionId: questionId)
        let w2 = annStore.weight(for: topTwo, questionId: questionId)
        if w1 == 0 && w2 == 0 { return 0 }
        let signDiff = (w1 > 0 && w2 < 0) || (w1 < 0 && w2 > 0)
        let magnitude = min(1.0, Double(abs(w1) + abs(w2)) / 20.0)
        if signDiff {
            return 0.5 + (0.5 * magnitude)
        }
        if w1 == 0 || w2 == 0 {
            return 0.2 * magnitude
        }
        return 0
    }

    private func entropyCandidates() -> [Animal] {
        guard !rankedAnimals.isEmpty else { return remainingAnimals }
        let baseCount = min(topKForQuestionSelection, rankedAnimals.count)
        let base = Array(rankedAnimals.prefix(baseCount))
        guard let cutoffId = base.last?.id else { return base }
        let cutoffScore = scores[cutoffId] ?? 0
        let expanded = rankedAnimals.filter { (scores[$0.id] ?? 0) >= cutoffScore }
        return expanded.count > base.count ? expanded : base
    }

    private func shouldAskSpecial(_ questionId: QuestionId) -> Bool {
        if questionId == "shrimp_thin_antennae" || questionId == "lobster_big_claws" || questionId == "shrimp_small_size" {
            if answers["lives_in_water"] != .yes { return false }
            if answers["is_mammal"] == .yes { return false }
            let topTwo = rankedAnimals.prefix(2).map { $0.id }
            guard Set(topTwo) == Set(["shrimp", "lobster"]) else { return false }
            let topScores = topTwo.compactMap { scores[$0] }
            let othersMax = rankedAnimals.dropFirst(2).compactMap { scores[$0.id] }.max() ?? Int.min
            return topScores.allSatisfy { $0 > othersMax }
        }

        guard let targets = specialQuestions[questionId] else { return true }
        let topThree = rankedAnimals.prefix(3)
        let targetTop = topThree.filter { targets.contains($0.id) }

        if targets.count == 1 {
            guard let targetId = targets.first, let targetScore = scores[targetId] else { return false }
            let topTwo = rankedAnimals.prefix(2).map { $0.id }
            guard topTwo.contains(targetId), let topScore = scores[rankedAnimals[0].id] else { return false }
            let closenessThreshold = 5
            if (topScore - targetScore) > closenessThreshold { return false }
            let othersMax = rankedAnimals.dropFirst(2).compactMap { scores[$0.id] }.max() ?? Int.min
            return targetScore > othersMax
        }

        guard targetTop.count >= 2 else { return false }
        let targetScores = targetTop.compactMap { scores[$0.id] }
        guard let minTarget = targetScores.min(), let maxTarget = targetScores.max() else { return false }
        let closenessThreshold = 5
        if (maxTarget - minTarget) > closenessThreshold { return false }
        let maxNonTarget = rankedAnimals.filter { !targets.contains($0.id) }.compactMap { scores[$0.id] }.max() ?? Int.min
        return minTarget > maxNonTarget
    }

    private func importance(for questionId: QuestionId) -> Int {
        questionImportance[questionId] ?? 1
    }

    func helpAnswers(for questionId: QuestionId) -> [(animal: Animal, answer: String)] {
        let items: [(Animal, String)] = allAnimals.map { animal in
            let w = annStore.weight(for: animal.id, questionId: questionId)
            let label: String
            if w > 0 { label = "Yes" }
            else if w < 0 { label = "No" }
            else { label = "Unknown" }
            return (animal, label)
        }
        func rank(_ label: String) -> Int {
            switch label {
            case "Yes": return 0
            case "No": return 1
            default: return 2
            }
        }
        return items.sorted { a, b in
            let ra = rank(a.1)
            let rb = rank(b.1)
            if ra == rb { return a.0.name < b.0.name }
            return ra < rb
        }
    }

    private func shouldSkipQuestion(_ questionId: QuestionId) -> Bool {
        // If the user already said "No" to carnivore or herbivore, skip the omnivore follow-up.
        if questionId == "is_omnivore" {
            if answers["is_carnivore"] == .no || answers["is_herbivore"] == .no {
                return true
            }
        }
        // If a high-level animal class is already confirmed, skip asking the others.
        let classes: Set<QuestionId> = ["is_amphibian", "is_reptile", "is_mammal", "is_bird"]
        if classes.contains(questionId) {
            // If any other class question was answered yes, this one is redundant.
            for key in classes where key != questionId {
                if answers[key] == .yes { return true }
            }
        }
        return false
    }

    private func entropy(_ counts: [Int]) -> Double {
        let total = counts.reduce(0, +)
        guard total > 0 else { return 0 }
        return counts.reduce(0.0) { acc, count in
            guard count > 0 else { return acc }
            let p = Double(count) / Double(total)
            return acc - p * log2(p)
        }
    }

    private func splitSignature(questionId: QuestionId, animals: [Animal]) -> String {
        var yes: [String] = []
        var no: [String] = []
        for animal in animals {
            let w = annStore.weight(for: animal.id, questionId: questionId)
            if w > 0 { yes.append(animal.id) }
            else if w < 0 { no.append(animal.id) }
        }
        yes.sort()
        no.sort()
        return "Y:\(yes.joined(separator: ","));N:\(no.joined(separator: ","))"
    }

    private func learnFromGame(correctAnimalId: AnimalId) {
        for (qId, answer) in answers {
            guard let key = answerWeightKey(for: answer),
                  let delta = annStore.config.answerWeights[key],
                  delta != 0 else { continue }

            if answer == .maybe || answer == .notSure { continue }
            annStore.addToWeight(delta * importance(for: qId), for: correctAnimalId, questionId: qId)
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
