import SwiftUI

/// Shared model representing a single confetti particle for view animations.
struct ConfettiParticle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let size: CGFloat
    let delay: Double
    let hue: Double
}
