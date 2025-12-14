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
    private var answers: [QuestionId: Answer] = [:]
    private var askedQuestions: Set<QuestionId> = []

    private let maxQuestions = 20
    private let topKForQuestionSelection = 8
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
            learnFromGame(correctAnimalId: guessed.id)
            statusMessage = "Updated weights for \(guessed.name)."
            lastGuessWasWrong = false
        } else {
            statusMessage = "No weight changes applied."
            lastGuessWasWrong = true
        }
        isFinished = true
    }

    func topCandidatesIfWrong() -> [String]? {
        guard let guessName = currentGuess?.name else { return nil }
        let filtered = topCandidateNames.filter { $0 != guessName }
        let slice = filtered.prefix(5)
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
        var scores: [AnimalId: Int] = [:]
        for animal in allAnimals {
            scores[animal.id] = 0
        }

        for (qId, answer) in answers {
            guard let key = answerWeightKey(for: answer),
                  let answerWeight = annStore.config.answerWeights[key],
                  answerWeight != 0 else {
                // Handle weak evidence for unknown: use small magnitude in the direction of the cell sign.
                applyUnknownNudge(for: qId, to: &scores, answer: answer)
                continue
            }

            let deltaMagnitude = abs(answerWeight) * importance(for: qId)

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
        let topAnimals = remainingAnimals
        let n = topAnimals.count
        guard n > 1 else { return nil }

        // Build signature of already asked questions to avoid near-duplicate splits.
        var seenSignatures: Set<String> = []
        for qId in askedQuestions {
            let sig = splitSignature(questionId: qId, animals: topAnimals)
            if !sig.isEmpty { seenSignatures.insert(sig) }
        }

        var bestQuestion: Question?
        var bestEntropy: Double = -Double.infinity
        var bestCoverage: Double = -Double.infinity

        for q in allQuestions {
            if askedQuestions.contains(q.id) { continue }
            if shouldSkipQuestion(q.id) { continue }

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

            if entropyVal > bestEntropy || (entropyVal == bestEntropy && coverage > bestCoverage) {
                bestEntropy = entropyVal
                bestCoverage = coverage
                bestQuestion = q
            }
        }

        return bestQuestion
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

struct ContentView: View {
    @StateObject private var viewModel: ANNGameViewModel
    @Environment(\.colorScheme) private var colorScheme
    // Design tokens for consistent rounding/shadow.
    private let cardCorner: CGFloat = 18
    private let buttonCorner: CGFloat = 16
    private let shadowRadius: CGFloat = 12
    private let shadowYOffset: CGFloat = 6
    @State private var isMenuOpen = false
    @State private var simReport: SimulationReport?
    @State private var simRunning = false
    @State private var noisySimReport: SimulationReport?
    @State private var noisySimRunning = false
    @State private var expandedRunIDs: Set<String> = []
    @State private var confettiParticles: [ConfettiParticle] = []

    init(viewModel: ANNGameViewModel? = ANNGameViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ANNGameViewModel()!)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()
                    .overlay(parallaxLayer)

                ScrollView {
                    VStack(spacing: 20) {
                        header
                        progressBar

                        Group {
                            if let question = viewModel.currentQuestion, !viewModel.isFinished {
                                questionCard(question)
                                    .id(question.id)
                                    .transition(questionTransition)
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
                        debugSimulator
                        if shouldShowRestartButton {
                            restartButton
                        }
                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
            .navigationTitle("20 Questions: Animals")
            .overlay(alignment: .topTrailing) { optionsButton }
            .overlay { sideMenuOverlay }
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

    private var optionsButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isMenuOpen.toggle() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .rotationEffect(.degrees(isMenuOpen ? 90 : 0))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.9))
                        .shadow(color: shadowColor.opacity(0.6), radius: 6, x: 0, y: 3)
                )
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .padding(.trailing, 16)
        .padding(.top, 8)
        .accessibilityLabel("More options")
    }

    private var sideMenuOverlay: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                if isMenuOpen {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { isMenuOpen = false }
                        }
                }
                SideMenuView(
                    isOpen: $isMenuOpen,
                    width: max(proxy.size.width * 0.3, 220),
                    cardFill: cardFill,
                    shadowColor: shadowColor,
                    onDeveloper: {
                        withAnimation(.easeInOut(duration: 0.2)) { isMenuOpen = false }
                    },
                    onFeedback: {
                        withAnimation(.easeInOut(duration: 0.2)) { isMenuOpen = false }
                    }
                )
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .allowsHitTesting(isMenuOpen)
    }

    private var progressBar: some View {
        let currentStep = min(viewModel.currentTurn, viewModel.maxTurnCount)
        let fraction = max(0, min(1, Double(currentStep) / Double(viewModel.maxTurnCount)))
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
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(track)
                        .frame(height: 15)
                    Capsule()
                        .fill(active)
                        .frame(width: max(24, fraction * proxy.size.width), height: 15)
                }
            }
            .frame(height: 10)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: cardCorner)
                .fill(cardFill)
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
        )
    }

    private func questionCard(_ question: Question) -> some View {
        VStack(spacing: 10) {
            Text("Question \(viewModel.currentTurn)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(question.text)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(.top, 16)
        .padding(.bottom, 24) // add a bit more bottom padding to balance the pointer height
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(
            DialogueBubbleShape(pointerHeight: 12, cornerRadius: cardCorner)
                .fill(cardFill)
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
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

            if !viewModel.isFinished {
                HStack(spacing: 12) {
                    AnswerButton(title: "Correct", color: .green, scheme: colorScheme) {
                        viewModel.finalizeGame(correct: true)
                        withAnimation { showConfetti() }
                    }
                    AnswerButton(title: "Wrong", color: .orange, scheme: colorScheme) {
                        viewModel.finalizeGame(correct: false)
                    }
                }
            } else {
                Button {
                    viewModel.restart()
                } label: {
                    Text("Play again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if viewModel.isFinished, viewModel.lastGuessWasWrong, let candidates = viewModel.topCandidatesIfWrong(), !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Is it one of these?")
                        .font(.headline)
                    ForEach(candidates, id: \.self) { name in
                        Text("- \(name)")
                            .font(.subheadline)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(cardFill.opacity(0.9))
                        .shadow(color: shadowColor, radius: 6, x: 0, y: 3)
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: cardCorner)
                .fill(cardFill)
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
        )
        .overlay(confettiLayer)
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
            RoundedRectangle(cornerRadius: cardCorner)
                .fill(cardFill)
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
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
            RoundedRectangle(cornerRadius: cardCorner)
                .fill(cardFill.opacity(0.9))
        )
    }

    private var restartButton: some View {
        Button {
            viewModel.restart()
        } label: {
            Text("Restart")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private var shouldShowRestartButton: Bool {
        viewModel.currentGuess == nil && !viewModel.isFinished
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

    private var parallaxLayer: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            ZStack {
                floatingCircle(x: width * 0.2, y: height * 0.3, size: 140, color: .blue.opacity(0.08), speed: 18)
                floatingCircle(x: width * 0.8, y: height * 0.4, size: 180, color: .pink.opacity(0.08), speed: 22)
                floatingCircle(x: width * 0.6, y: height * 0.75, size: 120, color: .orange.opacity(0.08), speed: 16)
            }
        }
        .allowsHitTesting(false)
    }

    private func floatingCircle(x: CGFloat, y: CGFloat, size: CGFloat, color: Color, speed: Double) -> some View {
        let animation = Animation.easeInOut(duration: speed).repeatForever(autoreverses: true)
        return Circle()
            .fill(color)
            .frame(width: size, height: size)
            .position(x: x, y: y)
            .offset(y: size * 0.05)
            .onAppear {
                withAnimation(animation) {}
            }
            .animation(animation, value: UUID())
    }

    private var questionTransition: AnyTransition {
        AnyTransition.modifier(
            active: SlideFadeBlur(progress: 0),
            identity: SlideFadeBlur(progress: 1)
        )
    }

    private var debugSimulator: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Developer Tools")
                .font(.headline)
            HStack(spacing: 12) {
                Button {
                    Task { await runSims(contradictions: 0) }
                } label: {
                    Label("Run 10 sims", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(simRunning || noisySimRunning)

                Button {
                    Task { await runSims(contradictions: 2) }
                } label: {
                    Label("Run noisy sims", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.bordered)
                .disabled(simRunning || noisySimRunning)
            }
            if simRunning || noisySimRunning {
                HStack {
                    ProgressView()
                    Text("Simulating...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            if let sim = simReport {
                Text("Clean sims: \(sim.correct)/\(sim.totalRuns) correct (\(Int(sim.accuracy * 100))%).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                runList(sim, label: "Recent clean runs", keyPrefix: "clean")
            }
            if let sim = noisySimReport {
                Text("Noisy sims: \(sim.correct)/\(sim.totalRuns) correct (\(Int(sim.accuracy * 100))%).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                runList(sim, label: "Recent noisy runs", keyPrefix: "noisy")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardFill.opacity(0.9))
                .shadow(color: shadowColor, radius: 6, x: 0, y: 4)
        )
    }

    private func runSims(contradictions: Int) async {
        if contradictions > 0 { noisySimRunning = true } else { simRunning = true }
        let simulator = GameSimulator(maxTurns: 20)
        let report: SimulationReport
        if contradictions > 0 {
            report = await simulator.runSimulationsWithContradictions(10, contradictions: contradictions)
            noisySimReport = report
        } else {
            report = await simulator.runSimulations(10)
            simReport = report
        }
        simRunning = false
        noisySimRunning = false
    }

    @ViewBuilder
    private func runList(_ report: SimulationReport, label: String, keyPrefix: String) -> some View {
        let runs = Array(report.runs.prefix(10).enumerated())
        if runs.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                ForEach(runs, id: \.offset) { idx, run in
                    let runId = "\(keyPrefix)-\(idx)"
                    let isExpanded = expandedRunIDs.contains(runId)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("#\(idx + 1) \(run.target) -> \(run.guess) \(run.wasCorrect ? "[correct]" : "[wrong]")")
                                .font(.caption)
                            Spacer()
                            Button {
                                if isExpanded { expandedRunIDs.remove(runId) } else { expandedRunIDs.insert(runId) }
                            } label: {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.headline)
                                    .padding(8)
                                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                        if isExpanded {
                            ForEach(run.transcript) { entry in
                                HStack(alignment: .top) {
                                    Text("Q\(entry.turn)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.question)
                                            .font(.caption)
                                        Text("Answer: \(entry.answer.displayLabel)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(cardFill.opacity(0.8)))
                }
            }
        }
    }
}

private struct AnswerButton: View {
    let title: String
    let color: Color
    let scheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(buttonBackground)
                )
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(scheme == .dark ? 0.6 : 0.4), lineWidth: 1)
        )
        .shadow(color: color.opacity(0.35), radius: 8, x: 0, y: 5)
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

private struct SlideFadeBlur: ViewModifier {
    let progress: CGFloat
    func body(content: Content) -> some View {
        content
            .opacity(Double(progress))
            .offset(y: (1 - progress) * 16)
            .blur(radius: (1 - progress) * 6)
    }
}

// MARK: - Side Menu

private struct SideMenuView: View {
    @Binding var isOpen: Bool
    let width: CGFloat
    let cardFill: Color
    let shadowColor: Color
    let onDeveloper: () -> Void
    let onFeedback: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Menu")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isOpen = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .padding(8)
                }
                .accessibilityLabel("Close menu")
            }
            .padding(.bottom, 4)

            Divider()

            Button(action: onDeveloper) {
                Label("Developer Mode", systemImage: "hammer.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)

            Button(action: onFeedback) {
                Label("Feedback", systemImage: "envelope.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)

            Spacer()
        }
        .padding(16)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(cardFill)
                .shadow(color: shadowColor.opacity(0.3), radius: 12, x: -6, y: 0)
        )
        .offset(x: isOpen ? 0 : width)
        .animation(.easeInOut(duration: 0.25), value: isOpen)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Side menu")
    }
}

extension ContentView {
    private func showConfetti() {
        let newParticles: [ConfettiParticle] = (0..<8).map { _ in
            ConfettiParticle(
                x: CGFloat.random(in: -40...40),
                size: CGFloat.random(in: 6...12),
                delay: Double.random(in: 0...0.2),
                hue: Double.random(in: 0...1)
            )
        }
        confettiParticles = newParticles
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            confettiParticles = []
        }
    }

    private var confettiLayer: some View {
        ZStack {
            ForEach(confettiParticles) { particle in
                Circle()
                    .fill(Color(hue: particle.hue, saturation: 0.7, brightness: 1.0).opacity(0.8))
                    .frame(width: particle.size, height: particle.size)
                    .offset(x: particle.x)
                    .modifier(ConfettiRise(delay: particle.delay))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ConfettiRise: ViewModifier {
    let delay: Double
    @State private var animate = false

    func body(content: Content) -> some View {
        content
            .opacity(animate ? 0 : 1)
            .offset(y: animate ? -120 : 0)
            .scaleEffect(animate ? 1.2 : 1.0)
            .animation(.easeOut(duration: 0.9).delay(delay), value: animate)
            .onAppear { animate = true }
    }
}

/// Speech bubble with a pointer centered at the bottom.
private struct DialogueBubbleShape: Shape {
    var pointerHeight: CGFloat = 12
    var cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pointerWidth: CGFloat = 26
        let mainRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height - pointerHeight
        )

        path.addRoundedRect(in: mainRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        let pointer = Path { p in
            let centerX = rect.midX
            let topY = mainRect.maxY
            let bottomY = rect.maxY
            p.move(to: CGPoint(x: centerX - pointerWidth / 2, y: topY))
            p.addLine(to: CGPoint(x: centerX, y: bottomY))
            p.addLine(to: CGPoint(x: centerX + pointerWidth / 2, y: topY))
            p.closeSubpath()
        }

        path.addPath(pointer)
        return path
    }
}

#Preview("Main Game - Light") {
    ContentView()
        .preferredColorScheme(.light)
}

#Preview("Main Game - Dark") {
    ContentView()
        .preferredColorScheme(.dark)
}
