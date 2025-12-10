import SwiftUI

/// A fun alternative UI for 20 Questions featuring Larry the Llama mascot
/// who asks questions through a dialogue bubble instead of plain cards.
struct LlamaMascotContentView: View {
    @StateObject private var viewModel = ANNGameViewModel()!
    @Environment(\.colorScheme) private var colorScheme
    @State private var confettiParticles: [ConfettiParticle] = []
    @State private var llamaAnimating = false
    @State private var bubbleScale: CGFloat = 0.8

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

                        debugStrip
                        restartButton
                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
            .navigationTitle("20 Questions: Animals")
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
                .offset(y: -20) // Overlap with bubble slightly
        }
    }

    private var dialogueBubble: some View {
        VStack(spacing: 8) {
            if let question = viewModel.currentQuestion, !viewModel.isFinished {
                // Question mode
                Text("Question \(viewModel.currentTurn)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(question.text)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
        .padding(.vertical, 56)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Think of an animal")
                    .font(.largeTitle.bold())
                Spacer()
                Text("🦙")
                    .font(.largeTitle)
            }
            Text("Larry the Llama will try to guess it!")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressBar: some View {
        let fraction = max(0, min(1, Double(viewModel.currentTurn - 1) / Double(viewModel.maxTurnCount)))
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
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                    .frame(height: 10)
                Capsule()
                    .fill(active)
                    .frame(width: max(24, fraction * UIScreen.main.bounds.width * 0.6), height: 10)
            }
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
            }

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
                Text("Start Over")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
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
