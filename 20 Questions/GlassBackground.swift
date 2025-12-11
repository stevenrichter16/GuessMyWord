import SwiftUI

/// A reusable glass-like background with blur, tint, stroke, shadow, and optional moving gradient.
struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var cornerRadius: CGFloat = 16
    var tint: Color = Color.white.opacity(0.12)
    var strokeColor: Color = Color.primary.opacity(0.08)
    var shadowColor: Color = Color.black.opacity(0.2)
    var shadowRadius: CGFloat = 8
    var movingGradient: Bool = false
    var parallaxAmount: CGFloat = 6
    var showNoise: Bool = true

    @State private var animate = false

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let parallaxOffset = reduceMotion ? 0 : parallaxAmount
            let driftX = CGFloat(sin(t / 6.0)) * parallaxOffset
            let driftY = CGFloat(cos(t / 7.5)) * parallaxOffset

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(tint.opacity(colorScheme == .dark ? 1.0 : 1.0))
                    )

                if movingGradient && !reduceMotion {
                    let gradient = LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.18 : 0.22),
                            Color.white.opacity(0.04),
                            Color.white.opacity(colorScheme == .dark ? 0.18 : 0.22)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(gradient)
                        .blur(radius: 18)
                        .opacity(0.18)
                        .offset(x: driftX + (animate ? 60 : -60))
                        .animation(
                            .easeInOut(duration: 6.0).repeatForever(autoreverses: true),
                            value: animate
                        )

                    Circle()
                        .fill(gradient)
                        .blur(radius: 28)
                        .frame(width: 120, height: 120)
                        .opacity(0.12)
                        .offset(
                            x: driftX + (animate ? -50 : 50),
                            y: driftY + (animate ? 20 : -20)
                        )
                        .animation(
                            .easeInOut(duration: 7.0).repeatForever(autoreverses: true),
                            value: animate
                        )
                }

                if showNoise && !reduceMotion {
                    NoiseOverlay()
                        .opacity(0.06)
                        .blendMode(.overlay)
                        .offset(x: driftX * 0.6, y: driftY * 0.6)
                        .animation(.easeInOut(duration: 10.0).repeatForever(autoreverses: true), value: animate)
                }

                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(strokeColor, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 4)
            .onAppear { animate = true }
        }
    }
}

private struct NoiseOverlay: View {
    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / 24)
            let rows = Int(size.height / 24)
            for x in 0...cols {
                for y in 0...rows {
                    let rect = CGRect(x: CGFloat(x) * 24, y: CGFloat(y) * 24, width: 12, height: 12)
                    let alpha = Double.random(in: 0...0.5)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha * 0.08)))
                }
            }
        }
    }
}
