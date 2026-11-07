//
//  LiquidGlass.swift
//  Construction Estimate
//
//  The app's Liquid Glass look: iOS 26 glass surfaces in the brand blues,
//  and a flowing particle field (a port of the fluid particles background)
//  for the backdrops the glass sits on.
//

import SwiftUI

// MARK: - Glass surfaces

extension View {
    /// A Liquid Glass card: real iOS 26 glass with a faint brand tint and a
    /// bright top edge. `interactive` makes it flex and glow under a finger.
    func liquidGlassCard(
        cornerRadius: CGFloat = 24,
        tint: Color = .white.opacity(0.35),
        interactive: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.75), .white.opacity(0.08), .white.opacity(0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            }
            .shadow(color: AppBrand.dark.opacity(0.10), radius: 22, y: 12)
    }

    /// A glass capsule for buttons and pills.
    func liquidGlassCapsule(tint: Color = .white.opacity(0.3), interactive: Bool = true) -> some View {
        glassEffect(.regular.tint(tint).interactive(interactive), in: Capsule())
    }
}

/// Press feedback for glass buttons: a deep, springy squash that settles
/// with a small overshoot.
struct LiquidGlassPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.spring(response: 0.32, dampingFraction: 0.52), value: configuration.isPressed)
    }
}

// MARK: - Backdrops

/// Light backdrop for the main portal: pale brand blues that drift, with
/// soft blue particles flowing over them for the glass to bend.
struct LiquidGlassBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = [
        Color(hex: 0xDCE8F8), Color(hex: 0xF2F6FC), Color(hex: 0xCFE0F7),
        Color(hex: 0xEAF1FB), Color(hex: 0xBFD5F3), Color(hex: 0xE6EEF9),
        Color(hex: 0xF7F9FC), Color(hex: 0xEEF3FA), Color(hex: 0xF9FAFC),
    ]

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                MeshGradient(width: 3, height: 3, points: OnboardingBackdrop.points(at: time), colors: Self.colors)
            }
            FlowParticlesView(color: AppBrand.light, opacity: 0.32, density: 0.55)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Flow particles

/// Particles that drift along a slowly changing flow field and leave short
/// streaks: the "fluid particles" background, in any brand color.
struct FlowParticlesView: View {
    var color: Color = .white
    var opacity: Double = 0.5
    /// Relative particle count; 1 is about one particle per 900 pt².
    var density: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var field = FlowParticleField()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            Canvas { graphics, size in
                field.step(size: size, time: context.date.timeIntervalSinceReferenceDate, density: density, still: reduceMotion)
                for particle in field.particles {
                    let fade = sin(min(1, particle.life / particle.maxLife) * .pi)
                    var path = Path()
                    path.move(to: particle.previous)
                    path.addLine(to: particle.position)
                    graphics.stroke(
                        path,
                        with: .color(color.opacity(opacity * fade)),
                        style: StrokeStyle(lineWidth: particle.size, lineCap: .round)
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Particle state lives in a reference type so the canvas can advance it
/// each frame without re-rendering the view tree.
final class FlowParticleField {
    struct Particle {
        var position: CGPoint
        var previous: CGPoint
        var size: CGFloat
        var life: Double
        var maxLife: Double
    }

    private(set) var particles: [Particle] = []
    private var lastSize: CGSize = .zero

    func step(size: CGSize, time: TimeInterval, density: Double, still: Bool) {
        guard size.width > 1, size.height > 1 else { return }
        if size != lastSize || particles.isEmpty {
            lastSize = size
            let count = Int(min(420, max(80, size.width * size.height / 900 * density)))
            particles = (0..<count).map { _ in Self.spawn(in: size, randomLife: true) }
            if still {
                // A settled frame: give each particle a short tail along the field.
                for index in particles.indices { advance(&particles[index], size: size, time: 0, speed: 6) }
            }
        }
        guard !still else { return }
        let t = time * 0.12
        for index in particles.indices {
            advance(&particles[index], size: size, time: t, speed: 1.6)
            particles[index].life += 1
            if particles[index].life > particles[index].maxLife {
                particles[index] = Self.spawn(in: size, randomLife: false)
            }
        }
    }

    private func advance(_ particle: inout Particle, size: CGSize, time: Double, speed: CGFloat) {
        let x = particle.position.x, y = particle.position.y
        // Layered sines stand in for Perlin noise: smooth, swirling, cheap.
        let angle = (sin(x * 0.0042 + time) + cos(y * 0.0051 - time * 0.8) + sin((x + y) * 0.0023 + time * 0.5)) * .pi * 0.9
        var next = CGPoint(x: x + cos(angle) * speed, y: y + sin(angle) * speed)
        // The streak's tail trails a few frames behind along the flow.
        var tail = CGPoint(x: next.x - cos(angle) * 9, y: next.y - sin(angle) * 9)
        if next.x < 0 || next.x > size.width || next.y < 0 || next.y > size.height {
            next = CGPoint(x: (next.x + size.width).truncatingRemainder(dividingBy: size.width),
                           y: (next.y + size.height).truncatingRemainder(dividingBy: size.height))
            tail = next
        }
        particle.previous = tail
        particle.position = next
    }

    private static func spawn(in size: CGSize, randomLife: Bool) -> Particle {
        let point = CGPoint(x: .random(in: 0...size.width), y: .random(in: 0...size.height))
        let maxLife = Double.random(in: 110...170)
        return Particle(
            position: point,
            previous: point,
            size: .random(in: 0.6...1.8),
            life: randomLife ? .random(in: 0...maxLife) : 0,
            maxLife: maxLife
        )
    }
}
