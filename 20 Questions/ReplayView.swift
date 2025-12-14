import SwiftUI
import UIKit

struct ReplayStep: Identifiable {
    let id = UUID()
    let question: String
    let answer: Answer
    let candidates: [String]
}

@MainActor
final class ReplayViewModel: ObservableObject {
    @Published var steps: [ReplayStep] = []
    @Published var currentIndex: Int = 0
    @Published var isPlaying: Bool = true
    @Published var speed: ReplaySpeed = .normal {
        didSet { startTimer() }
    }

    private var timer: Timer?
    private var interval: TimeInterval {
        switch speed {
        case .slow: return 4.0
        case .normal: return 3.0
        case .fast: return 2.0
        case .faster: return 1.5
        case .fastest: return 1.0
        }
    }

    init(steps: [ReplayStep]) {
        self.steps = steps
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    func startTimer() {
        timer?.invalidate()
        guard isPlaying, steps.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advance()
        }
    }

    func advance() {
        guard !steps.isEmpty else { return }
        if currentIndex + 1 < steps.count {
            withAnimation(.easeInOut(duration: 0.4)) {
                currentIndex += 1
            }
        } else {
            isPlaying = false
            timer?.invalidate()
        }
    }

    func togglePlay() {
        if isPlaying {
            isPlaying = false
            timer?.invalidate()
        } else {
            // If at the end, restart from the beginning when user replays.
            if currentIndex >= steps.count - 1 {
                currentIndex = 0
            }
            isPlaying = true
            startTimer()
        }
    }

    func setCurrentIndex(_ index: Int) {
        guard index >= 0 && index < steps.count else { return }
        currentIndex = index
        isPlaying = false
        timer?.invalidate()
    }

    func load(steps newSteps: [ReplayStep]) {
        timer?.invalidate()
        steps = newSteps
        currentIndex = 0
        isPlaying = true
        startTimer()
    }
}

enum ReplaySpeed: String, CaseIterable, Identifiable {
    case slow = "0.5x"
    case normal = "1x"
    case fast = "1.5x"
    case faster = "2x"
    case fastest = "3x"

    var id: String { rawValue }
}

struct ReplayView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: ReplayViewModel
    @State private var isTesting = false
    private let autoRunTest: Bool
    @State private var didAutoRun = false
    @State private var pulse = false
    @State private var answerPulse = false
    @State private var answerMessage: String?
    private let annStore = ANNDataStore(resourceName: "animals_ann")
    @State private var lastCandidates: [String] = []
    @State private var centerRipple = false
    @State private var showStory = false
    @State private var showVerticalBoard = false

    init(steps: [ReplayStep], autoRunTest: Bool = false) {
        _viewModel = StateObject(wrappedValue: ReplayViewModel(steps: steps))
        self.autoRunTest = autoRunTest
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()
                content
            }
            .navigationTitle("Replay")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if autoRunTest && !didAutoRun {
                    didAutoRun = true
                    runTestReplay()
                }
                lastCandidates = viewModel.steps.first?.candidates ?? []
                startPulse()
                triggerAnswerPulse()
            }
            .onChange(of: viewModel.currentIndex) { _ in
                let current = viewModel.steps[viewModel.currentIndex].candidates
                let removed = Set(lastCandidates).subtracting(current)
                if !removed.isEmpty {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        centerRipple.toggle()
                    }
                }
                lastCandidates = current
                startPulse()
                triggerAnswerPulse()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.steps.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "play.slash.fill")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No replay available.")
                    .font(.headline)
                Button {
                    runTestReplay()
                } label: {
                    HStack(spacing: 6) {
                        if isTesting { ProgressView().scaleEffect(0.8) }
                        Image(systemName: "wand.and.stars")
                        Text(isTesting ? "Simulating…" : "Test")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .disabled(isTesting)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            let step = viewModel.steps[viewModel.currentIndex]
            VStack(spacing: 20) {
                if let guess = aiGuessName {
                    guessBadge(guess: guess, in: step.candidates)
                        .padding(.horizontal)
                }
                HStack {
                    Button {
                        runTestReplay()
                    } label: {
                        HStack(spacing: 6) {
                            if isTesting { ProgressView().scaleEffect(0.8) }
                            Image(systemName: "wand.and.stars")
                            Text(isTesting ? "Simulating…" : "Test")
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.primary.opacity(0.12)))
                    }
                    .disabled(isTesting)
                    Spacer()
                }
                .padding(.horizontal)

                VStack(spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(step.question)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal)
                    Text("\(step.answer.rawValue)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(step.answer.rawValue == "Yes" ? Capsule().fill(Color.green.opacity(0.12)) : Capsule().fill(Color.red.opacity(0.12)))
                        .foregroundColor(step.answer.rawValue == "Yes" ? .green : .red)
                        
                    HStack(spacing: 12) {
                        answerButton("Yes", isSelected: step.answer == .yes)
                        answerButton("No", isSelected: step.answer == .no)
                        answerButton("Maybe", isSelected: step.answer == .maybe || step.answer == .notSure)
                    }
                    .padding(.horizontal)
                }

                GeometryReader { geo in
                    Group {
                        if showVerticalBoard {
                            verticalBoard(step: step, size: geo.size)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            circularBoard(step: step, size: geo.size)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                if value.translation.width > 40 {
                                    withAnimation(.easeInOut(duration: 0.25)) { showVerticalBoard = true }
                                } else if value.translation.width < -40 {
                                    withAnimation(.easeInOut(duration: 0.25)) { showVerticalBoard = false }
                                }
                            }
                    )
                }
                .frame(height: 340)

                if viewModel.steps.count > 1 {
                    slider
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showStory.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Story")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(showStory ? 180 : 0))
                        }
                        .padding(.horizontal)
                    }
                    if showStory {
                        if viewModel.steps.isEmpty {
                            Text("No story available yet.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        } else {
                            ScrollView {
                                storyTimeline
                                    .padding(.bottom, 8)
                            }
                            .frame(maxHeight: 160)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: showStory)

                HStack(spacing: 16) {
                    Text("Step \(viewModel.currentIndex + 1) of \(viewModel.steps.count)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("Speed", selection: $viewModel.speed) {
                        ForEach(ReplaySpeed.allCases) { speed in
                            Text(speed.rawValue).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    Button {
                        viewModel.togglePlay()
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    }
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }

    private func answerButton(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.purple : Color.primary.opacity(0.08))
            )
            .scaleEffect(isSelected ? (answerPulse ? 1.25 : 1.05) : 1.0)
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(Color.purple.opacity(0.5), lineWidth: 2)
                        .scaleEffect(pulse ? 1.5 : 0.9)
                        .opacity(pulse ? 0 : 0.5)
                        .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: false), value: pulse)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
    }

    private func circularBoard(step: ReplayStep, size: CGSize) -> some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [.red, .orange, .yellow]), center: .center),
                    lineWidth: 12
                )
                .frame(width: 160, height: 160)
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12))
                )
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .scaleEffect(centerRipple ? 1.2 : 0.85)
                        .blur(radius: 6)
                        .opacity(centerRipple ? 0.35 : 0.0)
                        .animation(.easeInOut(duration: 0.6), value: centerRipple)
                )
                .position(x: size.width / 2, y: size.height / 2)
            ForEach(Array(step.candidates.enumerated()), id: \.element) { idx, name in
                let persistence = persistenceCount(for: name, upTo: viewModel.currentIndex)
                let isGuess = viewModel.steps.last?.candidates.first?.lowercased() == name.lowercased()
                avatarView(name: name, rank: idx, total: step.candidates.count, question: step.question, persistence: persistence, isGuess: isGuess)
                    .frame(width: 70, height: 70)
                    .position(position(for: idx, total: step.candidates.count, in: size))
                    .transition(.scale.combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.6), value: step.candidates)
            }
        }
    }

    private func verticalBoard(step: ReplayStep, size: CGSize) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(step.candidates.enumerated()), id: \.element) { idx, name in
                    let persistence = persistenceCount(for: name, upTo: viewModel.currentIndex)
                    let isGuess = viewModel.steps.last?.candidates.first?.lowercased() == name.lowercased()
                    HStack(spacing: 10) {
                        Text("\(idx + 1).")
                            .font(.caption.weight(.bold))
                            .frame(width: 26, alignment: .trailing)
                            .foregroundColor(.secondary)
                        avatarView(name: name, rank: idx, total: step.candidates.count, question: step.question, persistence: persistence, isGuess: isGuess)
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.subheadline.weight(.semibold))
                            if isGuess {
                                Text("AI guess")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.blue.opacity(0.12)))
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func avatarView(name: String, rank: Int, total: Int, question: String, persistence: Int, isGuess: Bool) -> some View {
        let asset = FunFactAssetResolver.resolve(name)
        let tint = colorForRank(rank, total: total)
        let isStable = persistence >= 3
        return Group {
            if let asset, let image = UIImage(named: asset) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(isGuess ? Color.blue.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: isGuess ? 3 : 1)
                    )
                    .background(Circle().fill(tint.opacity(0.18)))
                    .shadow(color: isStable ? Color.purple.opacity(0.4) : Color.black.opacity(0.1), radius: isStable ? 8 : 4, x: 0, y: 2)
            } else {
                ZStack {
                    Circle().fill(tint.opacity(0.3))
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                        .padding(6)
                }
            }
        }
        .onTapGesture {
            showAnswer(for: name, questionText: question)
        }
        .overlay(alignment: .bottom) {
            if isStable {
                Text("Stable")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.purple.opacity(0.15)))
                    .foregroundColor(.purple)
                    .offset(y: 10)
            }
        }
    }

    private func position(for index: Int, total: Int, in size: CGSize) -> CGPoint {
        guard total > 0 else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let radius = min(size.width, size.height) / 2.5
        let angle = (2 * Double.pi / Double(max(total, 1))) * Double(index)
        let x = size.width / 2 + CGFloat(cos(angle)) * radius
        let y = size.height / 2 + CGFloat(sin(angle)) * radius
        return CGPoint(x: x, y: y)
    }

    private func colorForRank(_ rank: Int, total: Int) -> Color {
        guard total > 1 else { return .red }
        let t = max(0, min(1, Double(rank) / Double(total - 1)))
        let r: Double = 1.0
        let g: Double = 1.0 * t
        let b: Double = 0.0
        return Color(red: r, green: g, blue: b)
    }

    private func startPulse() {
        pulse.toggle()
    }

    private func triggerAnswerPulse() {
        answerPulse.toggle()
    }

    private var storyTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(viewModel.steps.enumerated()), id: \.offset) { idx, _ in
                HStack(alignment: .top, spacing: 8) {
                    Text("#\(idx + 1)")
                        .font(.caption.weight(.bold))
                        .padding(6)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                    Text(caption(for: idx))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }

    private var slider: some View {
        let binding = Binding<Double>(
            get: { Double(viewModel.currentIndex) },
            set: { newValue in
                viewModel.setCurrentIndex(Int(newValue.rounded()))
            }
        )
        return VStack(alignment: .leading, spacing: 6) {
            Slider(value: binding, in: 0...Double(max(viewModel.steps.count - 1, 0)), step: 1)
            HStack {
                Text("Step \(viewModel.currentIndex + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Total \(viewModel.steps.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private func runTestReplay() {
        guard !isTesting else { return }
        isTesting = true
        Task {
            let simulator = GameSimulator(maxTurns: 20)
            let report = await simulator.runSimulations(1)
            if let run = report.runs.first {
                let replaySteps = run.steps.map { step in
                    ReplayStep(question: step.entry.question, answer: step.entry.answer, candidates: step.candidates)
                }
                if !replaySteps.isEmpty {
                    await MainActor.run {
                        viewModel.load(steps: replaySteps)
                    }
                }
            }
            await MainActor.run {
                isTesting = false
            }
        }
    }

    private var aiGuessName: String? {
        viewModel.steps.last?.candidates.first
    }

    private func caption(for index: Int) -> String {
        let step = viewModel.steps[index]
        let answer = step.answer.rawValue
        let question = step.question
        let previous = index > 0 ? viewModel.steps[index - 1].candidates.map { $0.lowercased() } : []
        let current = step.candidates.map { $0.lowercased() }
        let added = step.candidates.filter { !previous.contains($0.lowercased()) }
        let removed = (index > 0 ? viewModel.steps[index - 1].candidates : []).filter { !current.contains($0.lowercased()) }

        var parts: [String] = []
        if !added.isEmpty {
            parts.append("boosted \(list(added))")
        }
        if !removed.isEmpty {
            parts.append("demoted \(list(removed))")
        }
        let change = parts.isEmpty ? "kept candidates steady" : parts.joined(separator: "; ")
        return "Answering '\(answer)' to \(question) \(change)."
    }

    private func list(_ items: [String]) -> String {
        if items.count == 1 { return items[0] }
        let allButLast = items.dropLast()
        if let last = items.last {
            return allButLast.joined(separator: ", ") + " and " + last
        }
        return ""
    }

    private func guessBadge(guess: String, in currentCandidates: [String]) -> some View {
        let asset = FunFactAssetResolver.resolve(guess)
        let isPresent = currentCandidates.contains(where: { $0.lowercased() == guess.lowercased() })
        return HStack(spacing: 8) {
            if let asset, let image = UIImage(named: asset) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.blue.opacity(0.7), lineWidth: 2))
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(guess.prefix(1)))
                            .font(.caption.weight(.bold))
                            .foregroundColor(.blue)
                    )
            }
            Text("Guess: \(guess)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(isPresent ? 0.12 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.25), lineWidth: 1)
        )
        .opacity(isPresent ? 1 : 0.7)
    }

    private func showAnswer(for animalName: String, questionText: String) {
        guard let store = annStore else { return }
        // Match question by text (case-insensitive).
        let lowered = questionText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let questionId = store.config.questions.first(where: { $0.text.lowercased() == lowered })?.id else {
            answerMessage = "\(animalName): Unknown"
            scheduleAnswerClear()
            return
        }
        // Find animal id by name (case-insensitive).
        guard let animal = store.config.animals.first(where: { $0.name.lowercased() == animalName.lowercased() }) else {
            answerMessage = "\(animalName): Unknown"
            scheduleAnswerClear()
            return
        }
        let weight = store.weight(for: animal.id, questionId: questionId)
        let label: String
        if weight > 0 { label = "Yes" }
        else if weight < 0 { label = "No" }
        else { label = "Unknown" }
        answerMessage = "\(animal.name): \(label)"
        scheduleAnswerClear()
    }

    private func scheduleAnswerClear() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                answerMessage = nil
            }
        }
    }

    private func persistenceCount(for name: String, upTo index: Int) -> Int {
        guard index >= 0 && index < viewModel.steps.count else { return 0 }
        var count = 0
        var i = index
        while i >= 0 {
            let step = viewModel.steps[i]
            if step.candidates.contains(where: { $0.lowercased() == name.lowercased() }) {
                count += 1
            } else {
                break
            }
            i -= 1
        }
        return count
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
                    Color(red: 0.98, green: 0.96, blue: 1.0),
                    Color(red: 0.96, green: 0.98, blue: 1.0),
                    Color(red: 0.94, green: 0.96, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
