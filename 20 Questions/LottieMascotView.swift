import SwiftUI
import Lottie

/// Thin wrapper to render a looping Lottie animation in SwiftUI.
struct LottieMascotView: UIViewRepresentable {
    let animationName: String
    var play: Bool = true
    var loopMode: LottieLoopMode = .loop
    var animationScale: CGFloat = 1.0

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true

        let animationView = context.coordinator.animationView
        animationView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(animationView)

        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: container.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        configure(animationView)
        if play {
            animationView.play()
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let animationView = context.coordinator.animationView
        configure(animationView)
        if play {
            if !animationView.isAnimationPlaying {
                animationView.play()
            }
        } else {
            animationView.pause()
        }
    }

    private func configure(_ view: LottieAnimationView) {
        view.animation = LottieAnimation.named(animationName, bundle: .main)
        view.contentMode = .scaleAspectFit
        view.loopMode = loopMode
        view.backgroundBehavior = .pauseAndRestore
        view.transform = CGAffineTransform(scaleX: animationScale, y: animationScale)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        let animationView = LottieAnimationView()
    }
}
