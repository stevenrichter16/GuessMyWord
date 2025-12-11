import SwiftUI

/// A fun alternative UI for 20 Questions featuring Larry the Llama mascot
/// who asks questions through a dialogue bubble instead of plain cards.
struct LlamaMascotContentView: View {
    @StateObject private var viewModel = ANNGameViewModel()!
    @Environment(\.colorScheme) private var colorScheme
    @State private var confettiParticles: [ConfettiParticle] = []
    @State private var llamaAnimating = false
    @State private var bubbleScale: CGFloat = 0.8
    @State private var isMenuOpen = false
    @State private var showDeveloperTools = false
    @State private var helpQuestionId: QuestionId?
    @State private var helpQuestionText: String?
    @State private var isHelpSheetPresented = false
    @State private var expandedHelpSections: Set<String> = []
    @State private var simReport: SimulationReport?
    @State private var simRunning = false
    @State private var noisySimReport: SimulationReport?
    @State private var noisySimRunning = false
    @State private var expandedRunIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        header
                        progressBar

                        // Main mascot area
                        mascotWithDialogue
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.currentQuestion?.id)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.currentGuess?.id)

                        // Answer buttons below the mascot
                        if viewModel.currentQuestion != nil && !viewModel.isFinished {
                            answerButtons
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if viewModel.currentGuess != nil {
                            guessButtons
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        //debugStrip
                        if showDeveloperTools {
                            debugSimulator
                        }
                        if shouldShowRestartButton {
                            restartButton
                        }
                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
            //.navigationTitle("20 Questions: Animals")
            .overlay(alignment: .topTrailing) { optionsButton }
            .overlay { sideMenuOverlay }
            .sheet(isPresented: $isHelpSheetPresented) {
                helpSheetContent
                    .interactiveDismissDisabled(false) // allow swipe-to-close
                    .onDisappear {
                        helpQuestionId = nil
                        helpQuestionText = nil
                    }
            }
        }
    }

    // MARK: - Mascot with Dialogue Bubble

    private var mascotWithDialogue: some View {
        VStack(spacing: 0) {
            // Dialogue bubble
            dialogueBubble
                .scaleEffect(bubbleScale)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        bubbleScale = 1.0
                    }
                }
                .onChange(of: viewModel.currentQuestion?.id) { _, _ in
                    animateBubble()
                }
                .onChange(of: viewModel.currentGuess?.id) { _, _ in
                    animateBubble()
                }

            // Llama mascot
            llamaMascot
                .offset(y: 0) // Overlap with bubble slightly
        }
    }

    private var dialogueBubble: some View {
        VStack(spacing: 2) {
            if let question = viewModel.currentQuestion, !viewModel.isFinished {
                // Question mode
                Text("Question \(viewModel.currentTurn)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(question.text)
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    helpQuestionId = question.id
                    helpQuestionText = question.text
                    isHelpSheetPresented = true
                } label: {
                    Text("Need Help?")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.blue)
                }
            } else if let guess = viewModel.currentGuess {
                // Guess mode
                if viewModel.isFinished && viewModel.lastGuessWasWrong {
                    Text("Hmm, I was wrong!")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                    Text("Was it one of these?")
                        .font(.title3.weight(.semibold))
                    if let candidates = viewModel.topCandidatesIfWrong() {
                        Text(candidates.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else if viewModel.isFinished{
                    Text("Yay! I knew it!")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.green)
                    if let status = viewModel.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("I think I know!")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.purple)
                    Text("Is it a \(guess.name)?")
                        .font(.title2.weight(.bold))
                }
            } else {
                Text("I'm stumped!")
                    .font(.title3.weight(.semibold))
                Text("I ran out of ideas...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        // Balance top/bottom space by compensating for the bubble pointer (16pt tall).
        .padding(.top, 28)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity)
        .background(
            BubbleShape()
                .fill(bubbleFill)
                .shadow(color: shadowColor, radius: 8, x: 0, y: 4)
        )
        .overlay(confettiLayer)
    }

    private var llamaMascot: some View {
        ZStack {
            LottieMascotView(animationName: "waving futupaca alpaca", animationScale: 0.8)
                .frame(width: 80, height: 80)
                .onAppear {
                    startIdleAnimation()
                }
        }
    }

    private func animateBubble() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            bubbleScale = 0.9
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                bubbleScale = 1.0
            }
        }
        // Also trigger llama animation
        llamaAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            llamaAnimating = false
        }
    }

    private func startIdleAnimation() {
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                llamaAnimating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                llamaAnimating = false
            }
        }
    }

    // MARK: - Header & Progress

    private var header: some View {
        VStack(alignment: .center, spacing: 4) {
     
            Text("Think of an animal")
                .font(.largeTitle.bold())
                    
            
            Text("Larry the Llama will try to guess it!")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var progressBar: some View {
        let currentStep = min(viewModel.currentTurn, viewModel.maxTurnCount)
        let fraction = max(0, min(1, Double(currentStep) / Double(viewModel.maxTurnCount)))
        let track = Color.primary.opacity(colorScheme == .dark ? 0.25 : 0.08)
        let active = LinearGradient(
            colors: [.orange, .pink, .purple],
            startPoint: .leading,
            endPoint: .trailing
        )
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
                        .frame(height: 10)
                    Capsule()
                        .fill(active)
                        .frame(width: max(24, fraction * proxy.size.width), height: 10)
                }
            }
            .frame(height: 10)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardFill)
                .shadow(color: shadowColor, radius: 10, x: 0, y: 6)
        )
    }

    // MARK: - Buttons

    private var answerButtons: some View {
        HStack(spacing: 12) {
            LlamaAnswerButton(title: "Yes", color: .green, scheme: colorScheme) {
                viewModel.answerCurrentQuestion(.yes)
            }
            LlamaAnswerButton(title: "No", color: .red, scheme: colorScheme) {
                viewModel.answerCurrentQuestion(.no)
            }
            LlamaAnswerButton(title: "Maybe", color: .blue, scheme: colorScheme) {
                viewModel.answerCurrentQuestion(.notSure)
            }
        }
        .padding(.horizontal, 4)
    }

    private var guessButtons: some View {
        VStack(spacing: 12) {
            if !viewModel.isFinished {
                HStack(spacing: 12) {
                    LlamaAnswerButton(title: "Yes!", color: .green, scheme: colorScheme) {
                        viewModel.finalizeGame(correct: true)
                        withAnimation { showConfetti() }
                    }
                    LlamaAnswerButton(title: "Nope", color: .orange, scheme: colorScheme) {
                        viewModel.finalizeGame(correct: false)
                    }
                }
            } else {
                Button {
                    viewModel.restart()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Play Again")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Supporting Views

    private var debugStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Larry's thinking about...")
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

    private var restartButton: some View {
        Button {
            viewModel.restart()
        } label: {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                Text("Restart")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var shouldShowRestartButton: Bool {
        viewModel.currentGuess == nil && !viewModel.isFinished
    }

    // MARK: - Options Button + Side Menu

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
        Group {
            if isMenuOpen {
                GeometryReader { proxy in
                    ZStack(alignment: .trailing) {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) { isMenuOpen = false }
                            }
                        SideMenuView(
                            isOpen: $isMenuOpen,
                            width: max(proxy.size.width * 0.3, 220),
                            cardFill: cardFill,
                            shadowColor: shadowColor,
                            developerMode: $showDeveloperTools,
                            onFeedback: {
                                withAnimation(.easeInOut(duration: 0.2)) { isMenuOpen = false }
                            }
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
        }
    }

    private struct SideMenuView: View {
        @Binding var isOpen: Bool
        let width: CGFloat
        let cardFill: Color
        let shadowColor: Color
        @Binding var developerMode: Bool
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

                Toggle(isOn: $developerMode) {
                    Label("Developer Mode", systemImage: "hammer.fill")
                }
                .toggleStyle(SwitchToggleStyle(tint: .purple))
                .padding(.vertical, 4)

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

    // MARK: - Help Sheet

    private var helpSheetContent: some View {
        let entries: [(animal: Animal, answer: String)] = {
            if let qId = helpQuestionId {
                return viewModel.helpAnswers(for: qId)
            }
            return []
        }()
        let grouped = Dictionary(grouping: entries) { item in
            item.animal.name.first.map { String($0).uppercased() } ?? "#"
        }
        let sortedKeys = grouped.keys.sorted()

        return VStack(spacing: 16) {
            if let text = helpQuestionText {
                Text(text)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            } else {
                Text("Question help")
                    .font(.headline)
            }

            if entries.isEmpty {
                Text("No data available for this question.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(sortedKeys, id: \.self) { key in
                            let isExpanded = expandedHelpSections.contains(key)
                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if isExpanded { expandedHelpSections.remove(key) }
                                        else { expandedHelpSections.insert(key) }
                                    }
                                } label: {
                                    HStack {
                                        Text(key)
                                            .font(.headline)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(cardFill.opacity(0.95))
                                                    .shadow(color: shadowColor.opacity(0.15), radius: 4, x: 0, y: 2)
                                            )
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.secondary)
                                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                            .animation(.easeInOut(duration: 0.2), value: isExpanded)
                                    }
                                    .padding(.vertical, 4)
                                }
                                if isExpanded, let items = grouped[key] {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(items.sorted { $0.animal.name < $1.animal.name }, id: \.animal.id) { item in
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                Text(item.animal.name)
                                                    .font(.subheadline)
                                                Spacer()
                                                let tint = helpAnswerColor(item.answer)
                                                Text(item.answer)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(tint)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                                    .background(
                                                        Capsule()
                                                            .fill(tint.opacity(0.15))
                                                    )
                                                    .overlay(
                                                        Capsule()
                                                            .stroke(tint.opacity(0.35), lineWidth: 1)
                                                    )
                                            }
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(cardFill.opacity(0.9))
                                            )
                                        }
                                    }
                                    .padding(.leading, 4)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Button("Close") { isHelpSheetPresented = false }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(cardFill)
                .shadow(color: shadowColor, radius: 10, x: 0, y: 6)
        )
        .padding()
    }
 
    // MARK: - Developer Tools

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
        let runs = Array(report.runs.prefix(10))
        Group {
            if runs.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(runs.indices), id: \.self) { idx in
                        let run = runs[idx]
                        let runId = "\(keyPrefix)-\(idx)"
                        let expanded = expandedRunIDs.contains(runId)
                        DebugRunRow(
                            idx: idx,
                            runId: runId,
                            run: run,
                            isExpanded: expanded,
                            cardFill: cardFill,
                            toggle: {
                                if expanded { expandedRunIDs.remove(runId) }
                                else { expandedRunIDs.insert(runId) }
                            }
                        )
                    }
                }
            }
        }
    }

    private struct DebugRunRow: View {
        let idx: Int
        let runId: String
        let run: SimulationRun
        let isExpanded: Bool
        let cardFill: Color
        let toggle: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Run \(idx + 1): \(run.wasCorrect ? "✅" : "❌")")
                    Spacer()
                    Button(isExpanded ? "Hide" : "Show", action: toggle)
                        .font(.caption)
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

    // MARK: - Styling

    private var cardFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white.opacity(0.95)
    }

    private var bubbleFill: Color {
        colorScheme == .dark ? Color(.tertiarySystemBackground) : Color.white
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.12)
    }

    private func helpAnswerColor(_ label: String) -> Color {
        switch label.lowercased() {
        case "yes": return .green
        case "no": return .red
        default: return .orange
        }
    }

    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.08, blue: 0.15),
                    Color(red: 0.15, green: 0.1, blue: 0.2),
                    Color(red: 0.2, green: 0.12, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.orange.opacity(0.15),
                    Color.pink.opacity(0.1),
                    Color.purple.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Confetti

    private func showConfetti() {
        let newParticles: [ConfettiParticle] = (0..<12).map { _ in
            ConfettiParticle(
                x: CGFloat.random(in: -60...60),
                size: CGFloat.random(in: 8...14),
                delay: Double.random(in: 0...0.3),
                hue: Double.random(in: 0...1)
            )
        }
        confettiParticles = newParticles
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
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
                    .modifier(LlamaConfettiRise(delay: particle.delay))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Bubble Shape (Speech bubble with pointer)

struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cornerRadius: CGFloat = 20
        let pointerSize: CGFloat = 16
        let pointerWidth: CGFloat = 24

        // Main rounded rectangle (leaving space for pointer at bottom)
        let mainRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height - pointerSize
        )

        path.addRoundedRect(in: mainRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        // Pointer triangle at bottom center
        let pointerPath = Path { p in
            let centerX = rect.midX
            let topY = mainRect.maxY - 1
            let bottomY = rect.maxY

            p.move(to: CGPoint(x: centerX - pointerWidth/2, y: topY))
            p.addLine(to: CGPoint(x: centerX, y: bottomY))
            p.addLine(to: CGPoint(x: centerX + pointerWidth/2, y: topY))
            p.closeSubpath()
        }

        path.addPath(pointerPath)

        return path
    }
}

// MARK: - Llama View (Cute mascot)

struct LlamaView: View {
    let isAnimating: Bool
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            // Body
            Ellipse()
                .fill(llamaBodyColor)
                .frame(width: 80, height: 60)
                .offset(y: 40)

            // Neck
            RoundedRectangle(cornerRadius: 15)
                .fill(llamaBodyColor)
                .frame(width: 35, height: 50)
                .offset(y: 10)

            // Head
            Ellipse()
                .fill(llamaBodyColor)
                .frame(width: 55, height: 45)
                .offset(y: -20)
                .rotationEffect(.degrees(isAnimating ? 5 : -5))
                .animation(.easeInOut(duration: 0.2), value: isAnimating)

            // Ears
            Group {
                // Left ear
                Ellipse()
                    .fill(llamaBodyColor)
                    .frame(width: 12, height: 25)
                    .rotationEffect(.degrees(-20))
                    .offset(x: -20, y: -45)

                // Right ear
                Ellipse()
                    .fill(llamaBodyColor)
                    .frame(width: 12, height: 25)
                    .rotationEffect(.degrees(20))
                    .offset(x: 20, y: -45)
            }
            .rotationEffect(.degrees(isAnimating ? 3 : -3))
            .animation(.easeInOut(duration: 0.15), value: isAnimating)

            // Inner ears
            Group {
                Ellipse()
                    .fill(Color.pink.opacity(0.4))
                    .frame(width: 6, height: 15)
                    .rotationEffect(.degrees(-20))
                    .offset(x: -20, y: -43)

                Ellipse()
                    .fill(Color.pink.opacity(0.4))
                    .frame(width: 6, height: 15)
                    .rotationEffect(.degrees(20))
                    .offset(x: 20, y: -43)
            }

            // Eyes
            Group {
                // Left eye
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(Color.black)
                        .frame(width: 10, height: 10)
                        .offset(x: isAnimating ? 2 : 0)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                        .offset(x: 2, y: -2)
                }
                .offset(x: -12, y: -22)

                // Right eye
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(Color.black)
                        .frame(width: 10, height: 10)
                        .offset(x: isAnimating ? 2 : 0)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                        .offset(x: 2, y: -2)
                }
                .offset(x: 12, y: -22)
            }
            .animation(.easeInOut(duration: 0.1), value: isAnimating)

            // Snout
            Ellipse()
                .fill(llamaSnoutColor)
                .frame(width: 30, height: 20)
                .offset(y: -5)

            // Nose
            Ellipse()
                .fill(Color.pink.opacity(0.6))
                .frame(width: 10, height: 7)
                .offset(y: -8)

            // Mouth (cute smile)
            Path { path in
                path.move(to: CGPoint(x: -8, y: 0))
                path.addQuadCurve(
                    to: CGPoint(x: 8, y: 0),
                    control: CGPoint(x: 0, y: 6)
                )
            }
            .stroke(Color.black.opacity(0.6), lineWidth: 2)
            .offset(y: 2)

            // Cheek blush
            Group {
                Circle()
                    .fill(Color.pink.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .offset(x: -22, y: -10)

                Circle()
                    .fill(Color.pink.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .offset(x: 22, y: -10)
            }

            // Fluffy tuft on head
            ForEach(0..<3) { i in
                Ellipse()
                    .fill(llamaBodyColor)
                    .frame(width: 10, height: 15)
                    .offset(x: CGFloat(i - 1) * 8, y: -50)
                    .rotationEffect(.degrees(Double(i - 1) * 15))
            }
        }
    }

    private var llamaBodyColor: Color {
        colorScheme == .dark
            ? Color(red: 0.95, green: 0.9, blue: 0.85)
            : Color(red: 1.0, green: 0.98, blue: 0.95)
    }

    private var llamaSnoutColor: Color {
        colorScheme == .dark
            ? Color(red: 0.9, green: 0.85, blue: 0.8)
            : Color(red: 0.98, green: 0.95, blue: 0.9)
    }
}

// MARK: - Llama Answer Button

private struct LlamaAnswerButton: View {
    let title: String
    let color: Color
    let scheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(buttonBackground)
                )
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(scheme == .dark ? 0.5 : 0.3), lineWidth: 2)
        )
        .shadow(color: color.opacity(0.3), radius: 6, x: 0, y: 4)
    }

    private var buttonBackground: LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [color.opacity(0.4), color.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [color.opacity(0.2), color.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Confetti Animation

private struct LlamaConfettiRise: ViewModifier {
    let delay: Double
    @State private var animate = false

    func body(content: Content) -> some View {
        content
            .opacity(animate ? 0 : 1)
            .offset(y: animate ? -150 : 0)
            .scaleEffect(animate ? 1.3 : 1.0)
            .rotationEffect(.degrees(animate ? 360 : 0))
            .animation(.easeOut(duration: 1.0).delay(delay), value: animate)
            .onAppear { animate = true }
    }
}

// MARK: - Preview

#Preview("Llama Mascot - Light") {
    LlamaMascotContentView()
        .preferredColorScheme(.light)
}

#Preview("Llama Mascot - Dark") {
    LlamaMascotContentView()
        .preferredColorScheme(.dark)
}
