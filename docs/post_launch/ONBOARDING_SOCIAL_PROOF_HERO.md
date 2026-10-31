# Post-launch onboarding social-proof hero

This file preserves the launch hero content intentionally removed before the
first App Store submission. It is documentation only and is not part of the
Xcode target.

The corresponding image assets remain in `Media.xcassets`:

- `welcome 4.9 transparent`
- `welcome 4.9 rating`

## Restore the rating beneath the sign-in description

Inside `AppleAuthOnboardingPage.body`, restore:

```swift
let ratingWidth = 165 * designScale
```

Then insert this directly after the sign-in description:

```swift
Image("welcome 4.9 transparent")
    .resizable()
    .scaledToFill()
    .frame(width: ratingWidth, height: ratingWidth * 0.54)
    .clipped()
    .padding(.top, 34 * designScale)
    .frame(maxWidth: .infinity, alignment: .leading)
    .layoutPriority(1)
    .accessibilityLabel("Rated 4.9 stars")
```

## Restore the testimonial carousel

Insert this between the two flexible spacers above the authentication controls:

```swift
WelcomeTestimonialCarousel(scale: designScale)
    .frame(width: geometry.size.width, height: 188 * designScale)
    .clipped()
    .allowsHitTesting(false)

Spacer(minLength: 12 * designScale)
```

Restore these private components to `OnboardingView.swift`:

```swift
private struct WelcomeTestimonialCarousel: View {
    let scale: CGFloat

    private let firstRow = [
        WelcomeTestimonial(
            initials: "AJ",
            quote: "Won the kitchen remodel with a clean bid sent that afternoon.",
            author: "Alex J. · General Contractor"
        ),
        WelcomeTestimonial(
            initials: "MR",
            quote: "Built a full home-addition estimate before leaving the site.",
            author: "Mike R. · Remodeler"
        ),
        WelcomeTestimonial(
            initials: "CD",
            quote: "My estimates finally look as professional as the homes we build.",
            author: "Chris D. · Home Builder"
        )
    ]

    private let secondRow = [
        WelcomeTestimonial(
            initials: "TS",
            quote: "Clients understand every allowance and upgrade without a long call.",
            author: "Taylor S. · Custom Builder"
        ),
        WelcomeTestimonial(
            initials: "JP",
            quote: "EasyBid cut my residential estimating time in half.",
            author: "Jordan P. · Residential GC"
        ),
        WelcomeTestimonial(
            initials: "RM",
            quote: "Change orders are faster, clearer, and easier to approve.",
            author: "Ryan M. · Renovation Contractor"
        )
    ]

    var body: some View {
        VStack(spacing: 16 * scale) {
            WelcomeTestimonialRow(
                testimonials: firstRow,
                direction: -1,
                speed: 40,
                scale: scale
            )

            WelcomeTestimonialRow(
                testimonials: secondRow,
                direction: 1,
                speed: 45.33,
                scale: scale
            )
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

private struct WelcomeTestimonial: Identifiable {
    let id = UUID()
    let initials: String
    let quote: String
    let author: String
}

private struct WelcomeTestimonialRow: View {
    let testimonials: [WelcomeTestimonial]
    let direction: CGFloat
    let speed: TimeInterval
    let scale: CGFloat

    private var cardWidth: CGFloat { 234.3 * scale }
    private var cardHeight: CGFloat { 85.8 * scale }
    private var spacing: CGFloat { 16 * scale }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
            let rowWidth = CGFloat(testimonials.count) * (cardWidth + spacing)
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: speed) / speed
            let travel = CGFloat(phase) * rowWidth

            HStack(spacing: spacing) {
                ForEach(0..<(testimonials.count * 3), id: \.self) { index in
                    WelcomeTestimonialCard(
                        testimonial: testimonials[index % testimonials.count],
                        scale: scale
                    )
                    .frame(width: cardWidth, height: cardHeight)
                }
            }
            .offset(x: direction < 0 ? -travel : travel - rowWidth)
            .frame(maxWidth: .infinity)
        }
        .frame(height: cardHeight)
    }
}

private struct WelcomeTestimonialCard: View {
    let testimonial: WelcomeTestimonial
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 10 * scale) {
            Circle()
                .fill(Color(hex: 0x0B3157).opacity(0.08))
                .frame(width: 44 * scale, height: 44 * scale)
                .overlay {
                    Text(testimonial.initials)
                        .font(.system(size: 14.3 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: 0x0B3157))
                }

            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(testimonial.quote)
                    .font(.system(size: 12.65 * scale, weight: .medium, design: .rounded))
                    .lineLimit(2)

                Text(testimonial.author)
                    .font(.system(size: 10.45 * scale, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(hex: 0x0B3157).opacity(0.68))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14.3 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(Color(hex: 0x0B3157))
        .background {
            RoundedRectangle(cornerRadius: 15.4 * scale, style: .continuous)
                .fill(.white)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15.4 * scale, style: .continuous)
                .strokeBorder(Color(hex: 0x0B3157).opacity(0.08), lineWidth: 1 * scale)
        }
    }
}
```
