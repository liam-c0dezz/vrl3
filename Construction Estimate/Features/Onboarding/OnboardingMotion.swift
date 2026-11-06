//
//  OnboardingMotion.swift
//  Construction Estimate
//
//  Shared gradients and motion for the onboarding. Same navy, blue and ink
//  as before; flat fills become soft gradients and screens arrive with
//  calm, staggered motion. Everything holds still with Reduce Motion.
//

import SwiftUI

// MARK: - Gradients

enum OnboardingInk {
    /// Ink buttons: a touch lighter at the top so they read as rounded.
    static let button = LinearGradient(
        colors: [Color(red: 0.21, green: 0.22, blue: 0.27), AppGray.ink],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Chosen questionnaire answer: same ink, a cooler top.
    static let selectedOption = LinearGradient(
        colors: [Color(red: 0.16, green: 0.19, blue: 0.27), AppGray.ink],
        startPoint: .top,
        endPoint: .bottom
    )

    /// White sheets that hold the copy: white easing into a pale blue-grey.
    static let panel = LinearGradient(
        colors: [.white, Color(hex: 0xF1F5FB)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// White buttons and cards on the blue background.
    static let lightButton = LinearGradient(
        colors: [.white, Color(hex: 0xEDF3FB)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Thin highlight along the top edge of ink buttons.
    static let edgeHighlight = LinearGradient(
        colors: [.white.opacity(0.20), .white.opacity(0.02)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Progress fill on the blue background and on white pages.
    static let progressOnDark = LinearGradient(
        colors: [.white.opacity(0.7), .white],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let progressOnLight = LinearGradient(
        colors: [AppBrand.accent, AppBrand.light],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Halo around the welcome seal.
    static let halo = AngularGradient(
        colors: [.white.opacity(0.0), .white.opacity(0.55), .white.opacity(0.0), .white.opacity(0.25), .white.opacity(0.0)],
        center: .center
    )
}

// MARK: - Background

/// The brand's navy-to-blue gradient as a slow mesh: the middle band and
/// center drift over 25–40 s, so the light moves without ever looking busy.
struct OnboardingBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = [
        Color(hex: 0x0B2E5A), Color(hex: 0x0E3667), Color(hex: 0x0B2E5A),
        Color(hex: 0x1A4D92), Color(hex: 0x2262B5), Color(hex: 0x1D5297),
        Color(hex: 0x347FE5), Color(hex: 0x3A86EA), Color(hex: 0x2F77DD),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.points(at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate),
                colors: Self.colors
            )
        }
        .accessibilityHidden(true)
    }

    static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        func wave(_ period: Double, _ phase: Double, _ amount: Double) -> Float {
            Float(sin(time * 2 * .pi / period + phase) * amount)
        }
        return [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.5 + wave(31, 0.4, 0.06)),
            SIMD2(0.5 + wave(37, 1.1, 0.10), 0.5 + wave(29, 2.3, 0.08)),
            SIMD2(1, 0.5 + wave(25, 3.0, 0.06)),
            SIMD2(0, 1), SIMD2(0.5 + wave(41, 0.8, 0.08), 1), SIMD2(1, 1),
        ]
    }
}

// MARK: - Arrival

/// Content fades up out of a light blur when its page becomes active, and
/// quietly resets after the page has slid away so it plays again next time.
private struct OnboardingReveal: ViewModifier {
    let isActive: Bool
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    func body(content: Content) -> some View {
        let shown = isShown || reduceMotion
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 6)
            .offset(y: shown ? 0 : 14)
            .task(id: isActive) {
                if isActive {
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { isShown = true }
                } else {
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    isShown = false
                }
            }
    }
}

extension View {
    func onboardingReveal(_ isActive: Bool, delay: Double = 0) -> some View {
        modifier(OnboardingReveal(isActive: isActive, delay: delay))
    }

    /// A slow vertical bob, for a single focal element.
    func onboardingFloat(amount: CGFloat = 5, duration: Double = 2.6) -> some View {
        modifier(OnboardingFloat(amount: amount, duration: duration))
    }
}

private struct OnboardingFloat: ViewModifier {
    let amount: CGFloat
    let duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.phaseAnimator([CGFloat(0), -amount]) { view, offset in
                view.offset(y: offset)
            } animation: { _ in
                .easeInOut(duration: duration)
            }
        }
    }
}

// MARK: - Buttons

/// Ink capsule with a gradient body, a top-edge highlight, a springy press
/// and a soft light that passes over it every few seconds once enabled.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 51.25

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                Capsule()
                    .fill(OnboardingInk.button)
                    .opacity(isEnabled ? 1 : 0.35)
            }
            .overlay {
                Capsule().strokeBorder(OnboardingInk.edgeHighlight, lineWidth: 1)
            }
            .overlay {
                ButtonSheen(isEnabled: isEnabled)
                    .clipShape(Capsule())
            }
            .shadow(color: AppGray.ink.opacity(isEnabled ? 0.18 : 0), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.3), value: isEnabled)
    }
}

/// Gentle press feedback for cards and answers.
struct OnboardingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

private struct ButtonSheen: View {
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let band = geometry.size.width * 0.35
            LinearGradient(
                colors: [.clear, .white.opacity(0.18), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: band)
            .offset(x: -band + progress * (geometry.size.width + band))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: isEnabled) {
            progress = 0
            guard isEnabled, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 1.2)) { progress = 1 }
                try? await Task.sleep(for: .seconds(5.5))
                progress = 0
            }
        }
    }
}

/// The "→" in buttons leans forward every couple of seconds.
struct OnboardingArrow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let arrow = Image(systemName: "arrow.right")
            .font(.system(size: 14, weight: .semibold))
        if reduceMotion {
            arrow
        } else {
            arrow.phaseAnimator([CGFloat(0), 4]) { view, offset in
                view.offset(x: offset)
            } animation: { offset in
                offset == 4
                    ? .easeOut(duration: 0.28).delay(2.2)
                    : .spring(response: 0.45, dampingFraction: 0.5)
            }
        }
    }
}

// MARK: - Details

/// A light that travels along a progress capsule.
struct OnboardingProgressShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                GeometryReader { geometry in
                    let period = 2.6
                    let phase = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: period) / period
                    let band = max(24, geometry.size.width * 0.3)
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.65), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: band)
                    .offset(x: -band + CGFloat(phase) * (geometry.size.width + band))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// A slowly turning ring of light around the welcome seal.
struct OnboardingHalo: View {
    var lineWidth: CGFloat = 1.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let degrees = reduceMotion ? 0 : (context.date.timeIntervalSinceReferenceDate * 24)
                .truncatingRemainder(dividingBy: 360)
            Circle()
                .strokeBorder(OnboardingInk.halo, lineWidth: lineWidth)
                .rotationEffect(.degrees(degrees))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
