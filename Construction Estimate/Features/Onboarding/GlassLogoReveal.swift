//
//  GlassLogoReveal.swift
//  Construction Estimate
//
//  Opening moment of the onboarding: a droplet of Liquid Glass lands on the
//  brand-blue backdrop, spreads into an app-icon tile, holds the EasyBid
//  house big against its rim (where the glass bends it), lets a band of light
//  cross, then lets go and leaves the mark. Same timeline as the web
//  "glass icon reveal", built on iOS 26 glass instead of a WebGL shader.
//

import SwiftUI

/// The EasyBid house: a thick outline with a rounded outside and a crisp
/// inner peak, drawn as a stroked centre line (matches the app icon).
struct EasyBidMark: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        path.move(to: point(0.09, 0.91))
        path.addLine(to: point(0.09, 0.39))
        path.addLine(to: point(0.5, 0.10))
        path.addLine(to: point(0.91, 0.39))
        path.addLine(to: point(0.91, 0.91))
        path.closeSubpath()
        return path
    }

    /// Stroke width for a mark drawn at `size`.
    static func lineWidth(for size: CGFloat) -> CGFloat { size * 0.18 }
}

struct GlassLogoReveal: View {
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var plays = 0
    @State private var finished = false

    private struct Frame {
        var tile: CGFloat = 0.2        // tile size, share of its final size
        var round: CGFloat = 1         // 1 = circle droplet, 0 = app-icon tile
        var logo: CGFloat = 2.6        // logo magnification under the glass
        var glass: Double = 0          // glass opacity
        var split: CGFloat = 1         // colour split at the rim
        var ripple: CGFloat = 0.6      // landing ripple radius, tile sizes
        var rippleOpacity: Double = 0
        var sheen: CGFloat = -1.4      // light band position across the tile
        var lift: CGFloat = 1          // tile swell as the glass lets go
        var word: Double = 0           // "EasyBid" wordmark
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width * 0.58, 250)

            ZStack {
                OnboardingBackdrop()
                FlowParticlesView(color: .white, opacity: 0.35, density: 0.8)

                KeyframeAnimator(initialValue: reduceMotion ? Self.settled : Frame(), trigger: plays) { frame in
                    content(frame, side: side)
                } keyframes: { _ in
                    KeyframeTrack(\.tile) {
                        SpringKeyframe(1, duration: 0.7, spring: .init(response: 0.42, dampingRatio: 0.72))
                        LinearKeyframe(1.04, duration: 1.7)
                        SpringKeyframe(1.0, duration: 0.6, spring: .smooth)
                    }
                    KeyframeTrack(\.round) {
                        LinearKeyframe(1, duration: 0.42)
                        SpringKeyframe(0, duration: 0.6, spring: .init(response: 0.4, dampingRatio: 1))
                    }
                    KeyframeTrack(\.logo) {
                        SpringKeyframe(2.1, duration: 0.6, spring: .init(response: 0.7, dampingRatio: 1))
                        CubicKeyframe(1.0, duration: 1.75)
                        SpringKeyframe(0.86, duration: 0.8, spring: .init(response: 0.55, dampingRatio: 0.62))
                    }
                    KeyframeTrack(\.glass) {
                        LinearKeyframe(1, duration: 0.12)
                        LinearKeyframe(1, duration: 2.3)
                        CubicKeyframe(0, duration: 0.5)
                    }
                    KeyframeTrack(\.split) {
                        LinearKeyframe(1, duration: 0.9)
                        CubicKeyframe(0.35, duration: 1.5)
                        CubicKeyframe(0, duration: 0.4)
                    }
                    KeyframeTrack(\.ripple) {
                        LinearKeyframe(0.6, duration: 0.4)
                        CubicKeyframe(1.9, duration: 0.9)
                    }
                    KeyframeTrack(\.rippleOpacity) {
                        LinearKeyframe(0, duration: 0.38)
                        LinearKeyframe(0.55, duration: 0.06)
                        CubicKeyframe(0, duration: 0.85)
                    }
                    KeyframeTrack(\.sheen) {
                        LinearKeyframe(-1.4, duration: 0.9)
                        CubicKeyframe(1.4, duration: 1.4)
                    }
                    KeyframeTrack(\.lift) {
                        LinearKeyframe(1, duration: 2.45)
                        SpringKeyframe(1.14, duration: 0.5, spring: .init(response: 0.65, dampingRatio: 1))
                    }
                    KeyframeTrack(\.word) {
                        LinearKeyframe(0, duration: 2.6)
                        SpringKeyframe(1, duration: 0.7, spring: .smooth)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("EasyBid"))
        .accessibilityAddTraits(.isImage)
        .task {
            if !reduceMotion { plays += 1 }
            try? await Task.sleep(for: .seconds(reduceMotion ? 1.0 : 3.7))
            finish()
        }
    }

    private static let settled = Frame(
        tile: 1, round: 0, logo: 0.86, glass: 0, split: 0,
        ripple: 1.9, rippleOpacity: 0, sheen: 1.4, lift: 1.14, word: 1
    )

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }

    private func mark(_ color: Color, side: CGFloat) -> some View {
        EasyBidMark()
            .stroke(color, style: StrokeStyle(lineWidth: EasyBidMark.lineWidth(for: side), lineJoin: .round))
            .frame(width: side, height: side)
    }

    @ViewBuilder
    private func content(_ frame: Frame, side: CGFloat) -> some View {
        let tileSide = side * frame.tile * frame.lift
        // Superellipse-ish tile: corner radius eases from a circle to an icon.
        let corner = tileSide * (0.5 * frame.round + 0.23 * (1 - frame.round))
        let tileShape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let markSide = side * 0.5 * frame.logo
        let split = 6 * frame.split * frame.glass

        VStack(spacing: 26) {
            ZStack {
                // Landing ripple.
                tileShape
                    .strokeBorder(.white.opacity(frame.rippleOpacity), lineWidth: 1.5)
                    .frame(width: side * frame.ripple, height: side * frame.ripple)

                // The mark, with a red / blue split that only shows near the
                // rim while the glass bends it.
                ZStack {
                    mark(Color(red: 1, green: 0.45, blue: 0.5), side: markSide)
                        .offset(x: -split, y: split * 0.4)
                        .blendMode(.screen)
                        .opacity(frame.glass * 0.8)
                    mark(Color(red: 0.4, green: 0.75, blue: 1), side: markSide)
                        .offset(x: split, y: -split * 0.4)
                        .blendMode(.screen)
                        .opacity(frame.glass * 0.8)
                    mark(.white, side: markSide)
                }
                .compositingGroup()

                // The glass tile itself: real Liquid Glass lensing the mark.
                Color.clear
                    .frame(width: tileSide, height: tileSide)
                    .glassEffect(.clear.tint(.white.opacity(0.06)), in: tileShape)
                    .overlay {
                        // A band of light crossing the face.
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.32), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: tileSide * 0.45)
                        .rotationEffect(.degrees(28))
                        .offset(x: tileSide * 0.5 * frame.sheen)
                        .clipShape(tileShape)
                        .blendMode(.plusLighter)
                    }
                    .overlay {
                        tileShape.strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.1), .white.opacity(0.4)], startPoint: .topTrailing, endPoint: .bottomLeading),
                            lineWidth: 1.2
                        )
                    }
                    .shadow(color: AppBrand.dark.opacity(0.35), radius: 24, y: 14)
                    .opacity(frame.glass)
            }
            .frame(width: side * 1.9, height: side * 1.9)

            Text(L("EasyBid"))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .opacity(frame.word)
                .offset(y: 14 * (1 - frame.word))
                .blur(radius: 6 * (1 - frame.word))
        }
    }
}

#Preview {
    GlassLogoReveal()
}
