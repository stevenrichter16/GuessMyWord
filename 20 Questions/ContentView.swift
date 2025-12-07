import SwiftUI

struct ContentView: View {
    private let llm: LLMScaffolding
    @State private var phase: GamePhase = .idle
@State private var transcript: [QAEntry] = []
@State private var currentQuestion: String = "Thinking of a question…"
@State private var hint: String = ""
@State private var guess: LLMGuessResponse?
@State private var isBusy = false
@State private var hasStarted = false
@State private var errorMessage: String?
@State private var simReport: SimulationReport?
@State private var simRunning = false
#if DEBUG
@State private var transcriptExpanded = false
@State private var expandedCandidates: Set<UUID> = []
@State private var noisySimReport: SimulationReport?
@State private var noisySimRunning = false
#endif

    private let maxTurns = 20
    private let allowedCategories = LLMScaffolding.defaultCategories
    private let canonicalItems = LLMScaffolding.defaultCanonicalItems

    init(llm: LLMScaffolding = LLMScaffolding()) {
        self.llm = llm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    questionCard
                    answerControls
                    hintInput
                    guessCard
                    transcriptView
                    restartButton
                    if llm.isUsingFallback {
                        fallbackNotice
                    }
                    #if DEBUG
                    debugSimulator
                    #endif
                }
                .padding()
            }
            .navigationTitle("Guess My Animal")
            .task {
                guard !hasStarted else { return }
                hasStarted = true
                await startGame()
            }
        }
        .alert("Output issue", isPresented: Binding<Bool>(
            get: { errorMessage != nil },
            set: { _ in errorMessage = nil }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Think of an animal from our list (\(canonicalItems.count) total):")
                .font(.headline)
            Text("Common mammals, birds, reptiles, amphibians, fish, insects and more.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("The AI will ask up to \(maxTurns) yes/no/maybe questions, then make one guess based on the animal attributes.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Turn \(currentTurn) of \(maxTurns)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            Text(currentQuestion)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var answerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your answer:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                ForEach(Answer.allCases) { answer in
                    Button {
                        onAnswer(answer)
                    } label: {
                        Text(answer.displayLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(answer.tint)
                    .disabled(isBusy || phase != .asking)
                }
            }
        }
    }

    private var hintInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional hint (short phrase):")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                TextField("e.g., It lives in water", text: $hint)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {
                    Task { await refreshQuestion(withHint: true) }
                }
                .disabled(isBusy || phase != .asking || hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("The hint is sent to the model with the next prompt to help it refine questions.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var guessCard: some View {
        Group {
            if let guess {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The AI guesses:")
                        .font(.headline)
                    HStack {
                        Text(guess.guess.capitalized)
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text("Confidence \(Int(guess.confidence * 100))%")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Text(guess.rationale)
                        .font(.body)
                    HStack(spacing: 12) {
                        Button("Correct") {
                            phase = .finished
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy)
                        Button("Incorrect") {
                            phase = .finished
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
            }
        }
    }

    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.headline)
            if transcript.isEmpty {
                Text("No questions yet. The AI will start as soon as you hit Start or restart.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(transcript) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text("#\(entry.turn)")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 32, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.question)
                                .font(.subheadline.weight(.semibold))
                            Text("You: \(entry.answer.displayLabel)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var restartButton: some View {
        Button {
            Task { await startGame() }
        } label: {
            Text(phase == .finished ? "Play again" : "Restart")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding(.vertical)
        .disabled(isBusy)
    }

    private var fallbackNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Running on fallback model. Load the Foundation model for smarter questions/guesses.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    #if DEBUG
    private var debugSimulator: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Developer Tools")
                        .font(.headline)
                    Text("Run one offline simulation to spot-check accuracy.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    Task { await runSimulation() }
                } label: {
                    if simRunning {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text("Run 1 Simulation")
                            .font(.footnote.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(simRunning)
            }

            if let simReport {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accuracy: \(simReport.correct)/\(simReport.totalRuns) (\(Int(simReport.accuracy * 100))%)")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    if let run = simReport.lastRun {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("Target", systemImage: "flag.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Text(run.target)
                                    .font(.subheadline.weight(.semibold))
                            }
                            HStack {
                                Label("Guess", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Text(run.guess)
                                    .font(.subheadline.weight(.semibold))
                                Text(run.wasCorrect ? "Correct" : "Incorrect")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(run.wasCorrect ? .green : .red)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background((run.wasCorrect ? Color.green.opacity(0.15) : Color.red.opacity(0.15)))
                                    .cornerRadius(8)
                            }

                            Divider()
                            DisclosureGroup(isExpanded: $transcriptExpanded) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(run.steps, id: \.entry.id) { step in
                                        VStack(alignment: .leading, spacing: 6) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("#\(step.entry.turn) \(step.entry.question)")
                                                    .font(.subheadline.weight(.semibold))
                                                Text("Answer: \(step.entry.answer.displayLabel)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            if !step.candidates.isEmpty {
                                                Button {
                                                    if expandedCandidates.contains(step.entry.id) {
                                                        expandedCandidates.remove(step.entry.id)
                                                    } else {
                                                        expandedCandidates.insert(step.entry.id)
                                                    }
                                                } label: {
                                                    Text(expandedCandidates.contains(step.entry.id) ? "Hide Candidates" : "Show Candidates (\(step.candidates.count))")
                                                        .font(.caption.weight(.semibold))
                                                }
                                                .buttonStyle(.bordered)
                                                if expandedCandidates.contains(step.entry.id) {
                                                    Text(step.candidates.joined(separator: ", "))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                        .padding(.top, 2)
                                                }
                                            }
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(.systemBackground))
                                        .cornerRadius(8)
                                        .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
                                    }
                                }
                            } label: {
                                Text("Transcript")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(12)
                    }
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Noise Test")
                        .font(.headline)
                    Text("5 simulations with 2 contradictory answers each.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    Task { await runNoisySimulation() }
                } label: {
                    if noisySimRunning {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Text("Run 5 Noisy Sims")
                            .font(.footnote.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(noisySimRunning)
            }

            if let noisySimReport {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accuracy: \(noisySimReport.correct)/\(noisySimReport.totalRuns) (\(Int(noisySimReport.accuracy * 100))%)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    ForEach(Array(noisySimReport.runs.enumerated()), id: \.offset) { index, run in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Run \(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(run.wasCorrect ? "Correct" : "Incorrect")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(run.wasCorrect ? .green : .red)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background((run.wasCorrect ? Color.green.opacity(0.15) : Color.red.opacity(0.15)))
                                    .cornerRadius(8)
                            }
                            HStack {
                                Label("Target", systemImage: "flag.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Text(run.target)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Label("Guess", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Text(run.guess)
                                    .font(.subheadline.weight(.semibold))
                            }
                            if !run.flippedTurns.isEmpty {
                                Text("Contradicted turns: \(run.flippedTurns.map(String.init).joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            DisclosureGroup("Transcript", isExpanded: $transcriptExpanded) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(run.steps, id: \.entry.id) { step in
                                        let isFlipped = run.flippedTurns.contains(step.entry.turn)
                                        let isAligned = !run.wasCorrect && alignedWithGuess(step: step, guess: run.guess)
                                        VStack(alignment: .leading, spacing: 6) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("#\(step.entry.turn) \(step.entry.question)")
                                                    .font(.subheadline.weight(.semibold))
                                                Text("Answer: \(step.entry.answer.displayLabel)")
                                                    .font(.caption.weight(isFlipped ? .bold : .regular))
                                                    .foregroundColor(isFlipped ? .red : (isAligned ? .green : .secondary))
                                            }
                                            if !step.candidates.isEmpty {
                                                Button {
                                                    if expandedCandidates.contains(step.entry.id) {
                                                        expandedCandidates.remove(step.entry.id)
                                                    } else {
                                                        expandedCandidates.insert(step.entry.id)
                                                    }
                                                } label: {
                                                    Text(expandedCandidates.contains(step.entry.id) ? "Hide Candidates" : "Show Candidates (\(step.candidates.count))")
                                                        .font(.caption.weight(.semibold))
                                                }
                                                .buttonStyle(.bordered)
                                                if expandedCandidates.contains(step.entry.id) {
                                                    Text(step.candidates.joined(separator: ", "))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                        .padding(.top, 2)
                                                }
                                            }
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(.systemBackground))
                                        .cornerRadius(8)
                                        .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
                                    }
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    #endif

    private var currentTurn: Int {
        max(transcript.count + (phase == .guessing ? 1 : 0), 1)
    }

    @MainActor
    private func startGame() async {
        phase = .asking
        transcript = []
        guess = nil
        hint = ""
        currentQuestion = "Thinking of a question…"
        await refreshQuestion(withHint: false)
    }

    private func onAnswer(_ answer: Answer) {
        guard !isBusy, phase == .asking else { return }
        let turn = transcript.count + 1
        let entry = QAEntry(turn: turn, question: currentQuestion, answer: answer)
        LLMLog.log("A: \(answer.displayLabel) (Q: \(currentQuestion))")
        transcript.append(entry)
        if turn >= maxTurns {
            Task { await requestGuess() }
        } else {
            Task { await refreshQuestion(withHint: false) }
        }
    }

    private func refreshQuestion(withHint: Bool) async {
        await MainActor.run {
            isBusy = true
            phase = .asking
        }
        let context = PromptContext(
            turn: transcript.count + 1,
            maxTurns: maxTurns,
            transcript: transcript,
            allowedCategories: allowedCategories,
            canonicalItems: canonicalItems,
            hint: withHint ? hint.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        )

        // Build prompt for visibility; real LLM call will use it.
        _ = llm.buildAskPrompt(context: context)

        let response = await llm.nextQuestion(context: context)

        await MainActor.run {
            currentQuestion = response.question
            isBusy = false
        }
    }

    private func requestGuess() async {
        await MainActor.run {
            isBusy = true
            phase = .guessing
        }

        let context = PromptContext(
            turn: transcript.count + 1,
            maxTurns: maxTurns,
            transcript: transcript,
            allowedCategories: allowedCategories,
            canonicalItems: canonicalItems,
            hint: hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : hint
        )

        // Build prompt for visibility; real LLM call will use it.
        _ = llm.buildGuessPrompt(context: context)

        let response = await llm.makeGuess(context: context)

        await MainActor.run {
            guess = response
            phase = .guessing
            isBusy = false
        }
    }

    #if DEBUG
    private func runSimulation() async {
        await MainActor.run { simRunning = true }
        let simulator = GameSimulator(llm: LLMScaffolding(), maxTurns: maxTurns)
        let report = await simulator.runSimulations(1)
        await MainActor.run {
            simReport = report
            simRunning = false
        }
    }

    private func runNoisySimulation() async {
        await MainActor.run { noisySimRunning = true }
        let simulator = GameSimulator(llm: LLMScaffolding(), maxTurns: maxTurns)
        let report = await simulator.runSimulationsWithContradictions(5, contradictions: 2)
        await MainActor.run {
            noisySimReport = report
            noisySimRunning = false
        }
    }

    private func alignedWithGuess(step: SimulationStep, guess: String) -> Bool {
        guard let dataset = LLMScaffolding.animalDataset else { return false }
        let engine = AnimalQuestionEngine(dataset: dataset)
        guard let key = engine.featureKey(for: step.entry.question) else { return false }
        guard let facts = dataset.rows.first(where: { $0.key.lowercased() == guess.lowercased() })?.value,
              let value = facts[key] else { return false }
        switch step.entry.answer {
        case .yes: return value == 1
        case .no: return value == 0
        default: return false
        }
    }
    #endif
}
