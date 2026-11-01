//
//  LanguageToggle.swift
//  Construction Estimate
//
//  Compact EN / ES pill switch. The highlighted knob springs between the two
//  labels with a matched-geometry slide; tapping anywhere flips the language.
//

import SwiftUI

struct LanguageToggle: View {
    @Binding var language: AppLanguage
    /// Use the dark-on-light palette (questionnaire pages) instead of the
    /// light-on-gradient palette.
    var usesLightBackground = false
    var scale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var knobNamespace

    var body: some View {
        Button {
            withAnimation(
                reduceMotion
                    ? .easeInOut(duration: 0.15)
                    : .spring(response: 0.38, dampingFraction: 0.72)
            ) {
                language = language.toggled
            }
        } label: {
            HStack(spacing: 0) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.shortLabel)
                        .font(.system(size: 12.5 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(labelColor(isSelected: option == language))
                        .frame(width: 34 * scale, height: 26 * scale)
                        .background {
                            if option == language {
                                Capsule()
                                    .fill(knobColor)
                                    .shadow(color: .black.opacity(0.18), radius: 3 * scale, y: 1.5 * scale)
                                    .matchedGeometryEffect(id: "knob", in: knobNamespace)
                            }
                        }
                }
            }
            .padding(3 * scale)
            .background(Capsule().fill(trackColor))
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(LanguageTogglePressStyle())
        .sensoryFeedback(.selection, trigger: language)
        .animation(.easeInOut(duration: 0.25), value: usesLightBackground)
        .accessibilityLabel(language("Language"))
        .accessibilityValue(language.nativeName)
        .accessibilityHint(language("Switch language"))
    }

    private var trackColor: Color {
        usesLightBackground ? Color(hex: 0xE1E7EE) : AppBrand.dark.opacity(0.82)
    }

    private var knobColor: Color {
        usesLightBackground ? AppBrand.light : .white
    }

    private var borderColor: Color {
        usesLightBackground ? .black.opacity(0.06) : .white.opacity(0.22)
    }

    private func labelColor(isSelected: Bool) -> Color {
        switch (usesLightBackground, isSelected) {
        case (true, true): .white
        case (true, false): AppBrand.dark.opacity(0.55)
        case (false, true): AppBrand.dark
        case (false, false): .white.opacity(0.78)
        }
    }
}

private struct LanguageTogglePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    @Previewable @State var language: AppLanguage = .english

    VStack(spacing: 24) {
        LanguageToggle(language: $language)
            .padding()
            .background(AppBrand.verticalGradient)
        LanguageToggle(language: $language, usesLightBackground: true)
            .padding()
        Text(language("Welcome to EasyBid"))
    }
}
