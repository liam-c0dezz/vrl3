//
//  LiquidGlass.swift
//  Construction Estimate
//
//  The app's Liquid Glass look: iOS 26 glass surfaces in the brand blues,
//  and a brand gradient that follows a finger or pointer
//  behind the glass.
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

// MARK: - Backgrounds

/// The brand gradient that answers a finger or pointer: the colours lean
/// toward the touch and a soft glow follows it, its hue sliding a little
/// across the brand blues with position. Still when nothing touches it.
struct InteractiveGradient: View {
    enum Palette { case brand, light }

    var palette: Palette = .brand
    /// Touch or pointer location in global coordinates; nil when nothing touches.
    var point: CGPoint? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focus = UnitPoint(x: 0.5, y: 0.45)
    @State private var strength: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            ZStack {
                MeshGradient(width: 3, height: 3, points: meshPoints, colors: colors)
                RadialGradient(
                    colors: [glowColor.opacity(strength), glowColor.opacity(strength * 0.35), .clear],
                    center: focus,
                    startRadius: 0,
                    endRadius: max(frame.width, frame.height) * 0.55
                )
                .blendMode(palette == .brand ? .plusLighter : .normal)
            }
            .onChange(of: point) { _, newPoint in follow(newPoint, in: frame) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Same brand colours as before: navy to blue, or the pale blues.
    private var colors: [Color] {
        switch palette {
        case .brand:
            [Color(hex: 0x0B2E5A), Color(hex: 0x0E3667), Color(hex: 0x0B2E5A),
             Color(hex: 0x1A4D92), Color(hex: 0x2262B5), Color(hex: 0x1D5297),
             Color(hex: 0x347FE5), Color(hex: 0x3A86EA), Color(hex: 0x2F77DD)]
        case .light:
            [Color(hex: 0xDCE8F8), Color(hex: 0xF2F6FC), Color(hex: 0xCFE0F7),
             Color(hex: 0xEAF1FB), Color(hex: 0xBFD5F3), Color(hex: 0xE6EEF9),
             Color(hex: 0xF7F9FC), Color(hex: 0xEEF3FA), Color(hex: 0xF9FAFC)]
        }
    }

    /// Hue slides from the brand blue toward a cooler cyan-blue across the screen.
    private var glowColor: Color {
        let hue = 0.575 + 0.05 * Double(focus.x) - 0.015 * Double(focus.y)
        return palette == .brand
            ? Color(hue: hue, saturation: 0.72, brightness: 0.95).opacity(0.55)
            : Color(hue: hue, saturation: 0.45, brightness: 1).opacity(0.75)
    }

    /// The middle of the mesh leans toward the touch.
    private var meshPoints: [SIMD2<Float>] {
        let pull = Float(0.28 * strength)
        let cx = Float(0.5) + (Float(focus.x) - 0.5) * pull
        let cy = Float(0.5) + (Float(focus.y) - 0.5) * pull
        return [
            SIMD2(0, 0), SIMD2(0.5 + (cx - 0.5) * 0.4, 0), SIMD2(1, 0),
            SIMD2(0, 0.5 + (cy - 0.5) * 0.5), SIMD2(cx, cy), SIMD2(1, 0.5 + (cy - 0.5) * 0.5),
            SIMD2(0, 1), SIMD2(0.5 + (cx - 0.5) * 0.4, 1), SIMD2(1, 1),
        ]
    }

    private func follow(_ newPoint: CGPoint?, in frame: CGRect) {
        guard !reduceMotion else { return }
        if let newPoint, frame.width > 0, frame.height > 0 {
            let target = UnitPoint(
                x: min(max((newPoint.x - frame.minX) / frame.width, 0), 1),
                y: min(max((newPoint.y - frame.minY) / frame.height, 0), 1)
            )
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                focus = target
                strength = 1
            }
        } else {
            // Let go: the glow fades and the colours drift back to rest.
            withAnimation(.spring(response: 1.4, dampingFraction: 0.9)) {
                strength = 0
                focus = UnitPoint(x: 0.5, y: 0.45)
            }
        }
    }
}

extension View {
    /// Reports where a finger or pointer is over this view (global
    /// coordinates) without taking touches away from its buttons.
    func trackingGradientTouch(_ point: Binding<CGPoint?>) -> some View {
        self
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { point.wrappedValue = $0.location }
                    .onEnded { _ in point.wrappedValue = nil }
            )
            .onContinuousHover(coordinateSpace: .global) { phase in
                switch phase {
                case let .active(location): point.wrappedValue = location
                case .ended: point.wrappedValue = nil
                }
            }
    }
}

/// The main portal's background: the pale brand blues, perfectly still.
struct PortalBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(hex: 0xDCE8F8), Color(hex: 0xF2F6FC), Color(hex: 0xEEF3FA), Color(hex: 0xF7F9FC)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .accessibilityHidden(true)
    }
}
