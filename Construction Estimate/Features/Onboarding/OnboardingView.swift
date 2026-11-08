//
//  OnboardingView.swift
//  Construction Estimate
//
//  Image-free onboarding. Shared gradients and motion live in
//  OnboardingMotion.swift.
//

import SwiftUI
import UIKit
import Supabase
import Auth
import AuthenticationServices
import CryptoKit

struct OnboardingView: View {
    static let accountPageIndex = 0
    static let firstFeaturePageIndex = 1
    static let zipCodePageIndex = 4
    static let localActivityPageIndex = 5
    static let questionnaireStartPageIndex = 6
    static let estimatorBuildPageIndex = 10

    var onFinish: () -> Void = {}
    var onBack: (() -> Void)?

    @Environment(AuthStore.self) private var authStore

    @State private var selectedPage: Int
    @State private var savedZipCode = ""
    @State private var questionnaireAnswers: [Int: String] = [:]
    @State private var paywallErrorMessage = ""
    @State private var isShowingPaywallError = false
    @State private var isShowingLogoReveal: Bool
    @State private var touchPoint: CGPoint?

    private let pages = Array(OnboardingPage.all.dropFirst())
    private var pageCount: Int { pages.count + OnboardingQuestion.all.count + 4 }
    /// The "Building your custom estimator" loading page keeps a plain gradient.
    private var isEstimatorBuildPage: Bool {
        selectedPage == pages.count + OnboardingQuestion.all.count + 3
    }

    private var isQuestionnairePage: Bool {
        (Self.questionnaireStartPageIndex..<Self.estimatorBuildPageIndex)
            .contains(selectedPage)
    }

    init(
        initialPage: Int = 0,
        onBack: (() -> Void)? = nil,
        onFinish: @escaping () -> Void = {}
    ) {
        self.onBack = onBack
        self.onFinish = onFinish
        _isShowingLogoReveal = State(initialValue: initialPage == 0)
        _selectedPage = State(
            initialValue: min(
                max(initialPage, 0),
                OnboardingPage.all.count + OnboardingQuestion.all.count + 2
            )
        )
    }

    var body: some View {
        ZStack {
            // Brand gradient that follows a finger or pointer.
            InteractiveGradient(palette: .brand, point: isEstimatorBuildPage ? nil : touchPoint)
                .ignoresSafeArea()

            if isQuestionnairePage {
                InteractiveGradient(palette: .light, point: touchPoint)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            TabView(selection: $selectedPage) {
                AppleAuthOnboardingPage {
                    advance(from: 0)
                }
                .tag(0)

                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    OnboardingPageView(
                        page: page,
                        isActive: index + 1 == selectedPage
                    ) {
                        advance(from: index + 1)
                    }
                    .tag(index + 1)
                }

                ZipCodeOnboardingPage(
                    isActive: selectedPage == pages.count + 1
                ) { zipCode in
                    savedZipCode = zipCode
                    advance(from: pages.count + 1)
                }
                .tag(pages.count + 1)

                LocalActivityOnboardingPage(
                    zipCode: savedZipCode,
                    isActive: selectedPage == pages.count + 2,
                    onComplete: {
                        advance(from: pages.count + 2)
                    }
                )
                .tag(pages.count + 2)

                ForEach(Array(OnboardingQuestion.all.enumerated()), id: \.offset) { index, question in
                    OnboardingQuestionPage(
                        question: question,
                        selection: Binding(
                            get: { questionnaireAnswers[index] },
                            set: { questionnaireAnswers[index] = $0 }
                        ),
                        isActive: selectedPage == pages.count + 3 + index,
                        onContinue: {
                            advance(from: pages.count + 3 + index)
                        }
                    )
                    .tag(pages.count + 3 + index)
                }

                EstimatorBuildOnboardingPage(
                    isActive: selectedPage == pages.count + OnboardingQuestion.all.count + 3,
                    onContinue: {
                        SuperwallService.presentOnboardingPaywall(
                            onComplete: onFinish,
                            onFailure: { message in
                                paywallErrorMessage = message
                                isShowingPaywallError = true
                            }
                        )
                    }
                )
                .tag(pages.count + OnboardingQuestion.all.count + 3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(true)
            .ignoresSafeArea(.container, edges: .bottom)
            .highPriorityGesture(
                DragGesture(minimumDistance: 12),
                including: .gesture
            )

            OnboardingTopNavigation(
                currentPage: selectedPage,
                pageCount: pageCount,
                usesLightBackground: isQuestionnairePage,
                onBack: retreat
            )

            // Opening moment: the EasyBid mark revealed through Liquid Glass.
            if isShowingLogoReveal {
                GlassLogoReveal {
                    withAnimation(.easeInOut(duration: 0.7)) { isShowingLogoReveal = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.12)))
                .zIndex(10)
            }
        }
        .trackingGradientTouch($touchPoint)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: selectedPage)
        .alert(L("Paywall unavailable"), isPresented: $isShowingPaywallError) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(L(paywallErrorMessage))
        }
    }

    private func advance(from page: Int) {
        // The first page is an authentication gate. A callback, programmatic
        // selection change, or page gesture cannot enter onboarding features
        // until Supabase has issued a real session.
        guard page != Self.accountPageIndex || authStore.session != nil else {
            return
        }

        guard page < pageCount - 1 else {
            onFinish()
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            selectedPage = page + 1
        }
    }

    private func retreat() {
        guard selectedPage > 0 else {
            onBack?()
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            selectedPage -= 1
        }
    }
}

private struct AppleAuthOnboardingPage: View {
    private enum EmailAuthenticationMode: String, Identifiable {
        case signUp
        case signIn

        var id: String { rawValue }
    }

    let onAuthenticated: () -> Void

    @Environment(AuthStore.self) private var authStore

    @State private var appleNonce: String?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var emailAuthenticationMode: EmailAuthenticationMode?

    var body: some View {
        GeometryReader { geometry in
            let designScale = min(max(geometry.size.width / 402, 0.88), 1.10)
            let ratingWidth = 165 * designScale
            let bottomPadding = max(
                35 * designScale,
                geometry.safeAreaInsets.bottom + (24 * designScale)
            )

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text(L("Welcome to EasyBid"))
                        .font(.system(size: 31 * designScale, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onboardingReveal(true, delay: 0.1)

                    Text(L("Sign in to save your estimates, clients, and\ninvoices securely across devices."))
                        .font(
                            .system(
                                size: 17.6 * designScale,
                                weight: .medium,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3 * designScale)
                        .padding(.top, 15 * designScale)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onboardingReveal(true, delay: 0.22)

                    Image("welcome 4.9 transparent")
                        .resizable()
                        .scaledToFill()
                        .frame(width: ratingWidth, height: ratingWidth * 0.54)
                        .clipped()
                        .padding(.top, 34 * designScale)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                        .accessibilityLabel(L("Rated 4.9 stars"))
                        .onboardingReveal(true, delay: 0.34)
                }
                .padding(.horizontal, 34 * designScale)
                .padding(
                    .top,
                    max(
                        91 * designScale,
                        geometry.safeAreaInsets.top + (61 * designScale)
                    )
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Spacer(minLength: 12 * designScale)

                WelcomeTestimonialCarousel(scale: designScale)
                    .frame(width: geometry.size.width, height: 188 * designScale)
                    .clipped()
                    .allowsHitTesting(false)
                    .onboardingReveal(true, delay: 0.46)

                Spacer(minLength: 12 * designScale)

                VStack(spacing: 12 * designScale) {

                    if let errorMessage {
                        Text(L(errorMessage))
                            .font(
                                .system(
                                    size: 13 * designScale,
                                    weight: .regular,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.76))
                            .multilineTextAlignment(.center)
                    }

                    SignInWithAppleButton(.continue) { request in
                        let nonce = UUID().uuidString
                        appleNonce = nonce
                        errorMessage = nil
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = sha256(nonce)
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50 * designScale)
                    .clipShape(Capsule())
                    .disabled(isSubmitting)
                    .opacity(isSubmitting ? 0.72 : 1)
                    .overlay {
                        Capsule()
                            .fill(OnboardingInk.lightButton)
                            .overlay {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    HStack(spacing: 8 * designScale) {
                                        Image(systemName: "apple.logo")
                                            .font(
                                                .system(
                                                    size: 18.4 * designScale,
                                                    weight: .semibold
                                                )
                                            )
                                            .offset(y: -1.5 * designScale)
                                        Text(L("Continue with Apple"))
                                    }
                                    .font(
                                        .system(
                                            size: 16 * designScale,
                                            weight: .semibold,
                                            design: .rounded
                                        )
                                    )
                                    .foregroundStyle(.black)
                                }
                            }
                            .allowsHitTesting(false)
                    }

                    Button {
                        emailAuthenticationMode = .signUp
                    } label: {
                        Text(L("Continue with Email"))
                            .font(
                                .system(
                                    size: 16 * designScale,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50 * designScale)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        .clear.tint(AppBrand.dark.opacity(0.82)),
                        in: Capsule()
                    )
                    .disabled(isSubmitting)

                    Button {
                        emailAuthenticationMode = .signIn
                    } label: {
                        HStack(spacing: 0) {
                            Text(L("Already have an account? "))
                                .fontWeight(.regular)
                            Text(L("Log in"))
                                .fontWeight(.semibold)
                        }
                    }
                    .font(.system(size: 16 * designScale, design: .rounded))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)

                    Text(legalAgreementText)
                        .font(.system(size: 10 * designScale, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .tint(.white)
                        .multilineTextAlignment(.center)
                    .padding(.top, 3 * designScale)
                }
                .padding(.horizontal, 32 * designScale)
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: .infinity)
                .onboardingReveal(true, delay: 0.58)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(item: $emailAuthenticationMode) { mode in
            AuthenticationView(
                startsInSignInMode: mode == .signIn,
                onAuthenticated: onAuthenticated
            )
            .id(mode.id)
        }
    }

    private var legalAgreementText: AttributedString {
        var agreement = AttributedString(L("By signing up, you agree to the "))

        var privacyPolicy = AttributedString(L("Privacy Policy"))
        privacyPolicy.inlinePresentationIntent = .stronglyEmphasized
        privacyPolicy.link = PrivacyResources.policyURL
        agreement.append(privacyPolicy)

        agreement.append(AttributedString(L(" and ")))

        var termsOfUse = AttributedString(L("Terms of Use"))
        termsOfUse.inlinePresentationIntent = .stronglyEmphasized
        termsOfUse.link = PrivacyResources.termsURL
        agreement.append(termsOfUse)
        agreement.append(AttributedString("."))

        return agreement
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = SafeErrorMessages.authentication(error, operation: .oauth)
            }

        case let .success(authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = appleNonce
            else {
                errorMessage = "Apple could not complete sign in. Please try again."
                return
            }

            isSubmitting = true
            errorMessage = nil

            Task {
                defer { isSubmitting = false }
                do {
                    let session = try await supabase.auth.signInWithIdToken(
                        credentials: OpenIDConnectCredentials(
                            provider: .apple,
                            idToken: idToken,
                            nonce: nonce
                        )
                    )
                    // The auth-state stream is asynchronous. Accept the session
                    // before navigating so the onboarding gate cannot reject a
                    // successful Apple sign-in while it waits for `.signedIn`.
                    authStore.acceptAuthenticatedSession(session)

                    if let fullName = credential.fullName?.formatted(), !fullName.isEmpty {
                        _ = try? await supabase.auth.update(
                            user: UserAttributes(data: ["full_name": .string(fullName)])
                        )
                    }

                    onAuthenticated()
                } catch {
                    errorMessage = SafeErrorMessages.authentication(error, operation: .oauth)
                }
            }
        }
    }

    private func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

}

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
                .fill(AppBrand.dark.opacity(0.08))
                .frame(width: 44 * scale, height: 44 * scale)
                .overlay {
                    Text(testimonial.initials)
                        .font(.system(size: 14.3 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(AppBrand.dark)
                }

            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(L(testimonial.quote))
                    .font(.system(size: 12.65 * scale, weight: .medium, design: .rounded))
                    .lineLimit(2)

                Text(L(testimonial.author))
                    .font(.system(size: 10.45 * scale, weight: .regular, design: .rounded))
                    .foregroundStyle(AppBrand.dark.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14.3 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(AppBrand.dark)
        .background {
            RoundedRectangle(cornerRadius: 15.4 * scale, style: .continuous)
                .fill(OnboardingInk.lightButton)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15.4 * scale, style: .continuous)
                .strokeBorder(AppBrand.dark.opacity(0.08), lineWidth: 1 * scale)
        }
    }
}

private struct PhoneAuthOnboardingPage: View {
    private enum Step {
        case phone
        case code
    }

    let onAuthenticated: () -> Void

    @State private var step: Step = .phone
    @State private var phoneDigits = ""
    @State private var verificationCode = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case phone
        case code
    }

    private var normalizedDigits: String {
        String(phoneDigits.filter(\.isNumber).prefix(10))
    }

    private var e164PhoneNumber: String {
        "+1\(normalizedDigits)"
    }

    private var formattedPhoneNumber: String {
        let digits = normalizedDigits
        guard !digits.isEmpty else { return "" }

        if digits.count <= 3 {
            return "(\(digits)"
        }

        let areaCode = digits.prefix(3)
        let remaining = digits.dropFirst(3)
        if remaining.count <= 3 {
            return "(\(areaCode)) \(remaining)"
        }

        return "(\(areaCode)) \(remaining.prefix(3))-\(remaining.dropFirst(3))"
    }

    private var canSubmit: Bool {
        switch step {
        case .phone:
            normalizedDigits.count == 10 && !isSubmitting
        case .code:
            verificationCode.count == 6 && !isSubmitting
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let panelHeight = geometry.size.height * 0.54
            let panelBottomPadding = max(54, geometry.safeAreaInsets.bottom + 40)

            ZStack(alignment: .bottom) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedField = nil
                    }

                phoneArtwork
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, max(132, geometry.safeAreaInsets.top + 98))
                    .allowsHitTesting(false)

                UnevenRoundedRectangle(
                    topLeadingRadius: 30,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 30
                )
                .fill(
                    OnboardingInk.panel
                )
                .shadow(color: .black.opacity(0.10), radius: 18, y: -4)
                .frame(height: panelHeight + geometry.safeAreaInsets.bottom)
                .offset(y: geometry.safeAreaInsets.bottom)
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    VStack(spacing: 13) {
                        Text(step == .phone ? "What's your phone number?" : "Enter your verification code")
                            .font(.system(size: 23.74, weight: .medium, design: .rounded))
                            .foregroundStyle(AppGray.ink)
                            .multilineTextAlignment(.center)

                        Text(step == .phone
                             ? "We'll text you a secure code to create your account or sign you back in."
                             : "We sent a six-digit code to +1 \(formattedPhoneNumber).")
                            .font(.system(size: 16.37, weight: .regular, design: .rounded))
                            .foregroundStyle(AppGray.itemText.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity)

                    Group {
                        if step == .phone {
                            phoneField
                        } else {
                            codeField
                        }
                    }
                    .padding(.top, 25)

                    if let errorMessage {
                        Text(L(errorMessage))
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                    }

                    if step == .code {
                        HStack(spacing: 18) {
                            Button(L("Change number")) {
                                errorMessage = nil
                                verificationCode = ""
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    step = .phone
                                }
                                focusedField = .phone
                            }
                            .onboardingTapHaptic()

                            Button(L("Resend code"), action: resendCode)
                                .disabled(isSubmitting)
                                .onboardingTapHaptic()
                        }
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppBrand.light)
                        .padding(.top, 14)
                    }

                    Text(L("Standard message and data rates may apply."))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(AppGray.secondary)
                        .padding(.top, 12)

                    Spacer(minLength: 18)

                    Button(action: submit) {
                        Group {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                HStack(spacing: 8) {
                                    Text(step == .phone ? "Send code" : "Verify and continue")
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                        }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 51.25)
                        .background(canSubmit ? AppGray.ink : AppGray.ink.opacity(0.35))
                        .clipShape(Capsule())
                        .shadow(color: AppGray.ink.opacity(canSubmit ? 0.18 : 0), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .onboardingTapHaptic()
                }
                .padding(.horizontal, 36)
                .padding(.top, 52)
                .padding(.bottom, panelBottomPadding)
                .frame(height: panelHeight, alignment: .top)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("Done")) {
                    focusedField = nil
                }
                .onboardingTapHaptic()
            }
        }
        .onDisappear {
            focusedField = nil
        }
    }

    private var phoneArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white)
                .shadow(color: AppBrand.dark.opacity(0.22), radius: 24, y: 12)

            Circle()
                .fill(AppBrand.verticalGradient)
                .frame(width: 94, height: 94)
                .overlay {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(.white)
                }
        }
        .frame(width: 286, height: 206)
    }

    private var phoneField: some View {
        HStack(spacing: 12) {
            Text("+1")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(AppGray.ink)

            Rectangle()
                .fill(AppGray.border)
                .frame(width: 1, height: 28)

            TextField("5551234567", text: $phoneDigits)
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .keyboardType(.numberPad)
            .textContentType(.telephoneNumber)
            .focused($focusedField, equals: .phone)
            .onChange(of: phoneDigits) { _, newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(10))
                if digits != phoneDigits {
                    phoneDigits = digits
                }
            }
        }
        .padding(.horizontal, 17)
        .frame(height: 58)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(AppGray.border, lineWidth: 1)
        }
    }

    private var codeField: some View {
        TextField("000000", text: $verificationCode)
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($focusedField, equals: .code)
            .onChange(of: verificationCode) { _, newValue in
                verificationCode = String(newValue.filter(\.isNumber).prefix(6))
            }
            .frame(height: 58)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(AppGray.border, lineWidth: 1)
            }
    }

    private func submit() {
        guard canSubmit else { return }
        switch step {
        case .phone:
            sendCode()
        case .code:
            verifyCode()
        }
    }

    private func sendCode() {
        isSubmitting = true
        errorMessage = nil

        Task {
            defer { isSubmitting = false }
            do {
                try await supabase.auth.signInWithOTP(phone: e164PhoneNumber)
                withAnimation(.easeInOut(duration: 0.25)) {
                    step = .code
                }
                focusedField = .code
            } catch {
                errorMessage = phoneAuthErrorMessage(for: error)
            }
        }
    }

    private func verifyCode() {
        isSubmitting = true
        errorMessage = nil

        Task {
            defer { isSubmitting = false }
            do {
                try await supabase.auth.verifyOTP(
                    phone: e164PhoneNumber,
                    token: verificationCode,
                    type: .sms
                )
                onAuthenticated()
            } catch {
                errorMessage = phoneAuthErrorMessage(for: error)
            }
        }
    }

    private func resendCode() {
        isSubmitting = true
        errorMessage = nil

        Task {
            defer { isSubmitting = false }
            do {
                try await supabase.auth.signInWithOTP(phone: e164PhoneNumber)
            } catch {
                errorMessage = phoneAuthErrorMessage(for: error)
            }
        }
    }

    private func phoneAuthErrorMessage(for error: Error) -> String {
        let message = String(describing: error)
        if message.localizedCaseInsensitiveContains("unsupported phone provider") {
            return "Phone sign-in has not been enabled for this app yet."
        }
        return SafeErrorMessages.authentication(error, operation: .oauth)
    }
}

private struct ZipCodeOnboardingPage: View {
    let isActive: Bool
    let onComplete: (String) -> Void

    @State private var zipCode = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isZipFieldFocused: Bool

    private var normalizedZipCode: String {
        String(zipCode.filter(\.isNumber).prefix(5))
    }

    private var canContinue: Bool {
        normalizedZipCode.count == 5 && !isSaving
    }

    var body: some View {
        GeometryReader { geometry in
            let panelHeight = min(
                geometry.size.height * 0.84,
                geometry.size.height - max(92, geometry.safeAreaInsets.top + 58)
            )
            let panelBottomPadding = max(54, geometry.safeAreaInsets.bottom + 40)

            ZStack(alignment: .bottom) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 30,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 30
                )
                .fill(
                    OnboardingInk.panel
                )
                .shadow(color: .black.opacity(0.10), radius: 18, y: -4)
                .frame(height: panelHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    VStack(spacing: 16) {
                        Text(L("What's your ZIP code?"))
                            .font(.system(size: 23.74, weight: .medium, design: .rounded))
                            .foregroundStyle(AppGray.ink)
                            .multilineTextAlignment(.center)
                            .onboardingReveal(isActive, delay: 0.05)

                        Text(L("We'll use it to find accurate material pricing and local costs near you."))
                            .font(.system(size: 16.37, weight: .regular, design: .rounded))
                            .foregroundStyle(AppGray.itemText.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .onboardingReveal(isActive, delay: 0.15)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 0) {
                        TextField("00000", text: $zipCode)
                            .font(.system(size: 19, weight: .medium, design: .rounded))
                            .foregroundStyle(AppGray.ink)
                            .tint(AppGray.ink)
                            .tracking(2.5)
                            .keyboardType(.numberPad)
                            .textContentType(.postalCode)
                            .multilineTextAlignment(.center)
                            .focused($isZipFieldFocused)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                // The border takes on the brand blues while the field is in use.
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        isZipFieldFocused || normalizedZipCode.count == 5
                                            ? AnyShapeStyle(OnboardingInk.progressOnLight)
                                            : AnyShapeStyle(AppGray.border),
                                        lineWidth: isZipFieldFocused ? 1.5 : 1
                                    )
                            }
                            .overlay(alignment: .trailing) {
                                if normalizedZipCode.count == 5 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(AppBrand.light)
                                        .padding(.trailing, 14)
                                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                                }
                            }
                            .shadow(color: AppBrand.light.opacity(isZipFieldFocused ? 0.12 : 0), radius: 10, y: 4)
                            .scaleEffect(isZipFieldFocused ? 1.015 : 1)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isZipFieldFocused)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: normalizedZipCode.count == 5)
                            .padding(.horizontal, 12)
                            .onboardingReveal(isActive, delay: 0.24)

                        if let errorMessage {
                            Text(L(errorMessage))
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxHeight: .infinity)

                    Button(action: saveZipCode) {
                        Group {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                HStack(spacing: 8) {
                                    Text(L("Continue"))
                                    OnboardingArrow()
                                }
                            }
                        }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(!canContinue)
                    .onboardingTapHaptic()
                    .onboardingReveal(isActive, delay: 0.3)
                }
                .padding(.horizontal, 36)
                .padding(.top, 56)
                .padding(.bottom, panelBottomPadding)
                .frame(height: panelHeight, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onChange(of: zipCode) { _, newValue in
            let filteredValue = String(newValue.filter(\.isNumber).prefix(5))
            if filteredValue != newValue {
                zipCode = filteredValue
            }
        }
        .task(id: isActive) {
            if isActive {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                isZipFieldFocused = true
            } else {
                isZipFieldFocused = false
            }
        }
    }

    private func saveZipCode() {
        guard canContinue else { return }
        isZipFieldFocused = false
        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }
            do {
                try await supabase.auth.update(
                    user: UserAttributes(data: ["zip_code": .string(normalizedZipCode)])
                )
                onComplete(normalizedZipCode)
            } catch {
                errorMessage = SafeErrorMessages.data(error, action: "ZIP code update")
            }
        }
    }
}

private struct LocalActivityOnboardingPage: View {
    let zipCode: String
    let isActive: Bool
    let onComplete: () -> Void

    private var displayedZipCode: String {
        zipCode.isEmpty ? "87122" : zipCode
    }

    var body: some View {
        GeometryReader { geometry in
            let visualWidth = min(geometry.size.width - 36, 380)
            let visualHeight = min(max(geometry.size.height * 0.405, 290), 340)
            let visualTop = max(82, geometry.safeAreaInsets.top + 54)
            let panelHeight = geometry.size.height * 0.445
            let panelTopPadding = max(48, min(68, geometry.size.height * 0.075))
            let panelBottomPadding = max(54, geometry.safeAreaInsets.bottom + 40)

            ZStack(alignment: .bottom) {
                LocalActivityGraphicVisual(isActive: isActive)
                    .frame(width: visualWidth, height: visualHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, visualTop)
                    .zIndex(0)

                UnevenRoundedRectangle(
                    topLeadingRadius: 34,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 34
                )
                .fill(
                    OnboardingInk.panel
                )
                .frame(height: panelHeight + geometry.safeAreaInsets.bottom)
                .offset(y: geometry.safeAreaInsets.bottom)
                .zIndex(1)

                VStack(spacing: 0) {
                    VStack(spacing: 14) {
                        Text(L("Join contractors using EasyBid in %@", displayedZipCode))
                            .font(.system(size: 23.74, weight: .medium, design: .rounded))
                            .foregroundStyle(AppGray.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .onboardingReveal(isActive, delay: 0.08)

                        Text(L("Start sending faster, more competitive estimates with local pricing."))
                            .font(.system(size: 16.37, weight: .regular, design: .rounded))
                            .foregroundStyle(AppGray.itemText.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .onboardingReveal(isActive, delay: 0.2)
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 24)

                    Button(action: onComplete) {
                        HStack(spacing: 8) {
                            Text(L("Continue"))
                            OnboardingArrow()
                        }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .onboardingTapHaptic()
                    .onboardingReveal(isActive, delay: 0.32)
                }
                .padding(.horizontal, 42)
                .padding(.top, panelTopPadding)
                .padding(.bottom, panelBottomPadding)
                .frame(height: panelHeight, alignment: .top)
                .zIndex(3)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

private struct LocalActivityGraphicVisual: View {
    let isActive: Bool

    @State private var graphProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { graphGeometry in
                let upperStartY: CGFloat = 0.88
                let upperEndY: CGFloat = 0.23
                let lowerStartY: CGFloat = 0.88
                let lowerEndY: CGFloat = 0.76
                let curveEndX = graphGeometry.size.width * 0.96
                let upperMidpoint = comparisonGraphPoint(
                    progress: 0.5,
                    width: graphGeometry.size.width,
                    height: graphGeometry.size.height,
                    startY: upperStartY,
                    endY: upperEndY
                )

                ZStack {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(
                                        color: AppBrand.dark.opacity(0.43),
                                        location: 0
                                    ),
                                    .init(
                                        color: AppBrand.dark.opacity(0.17),
                                        location: 0.52
                                    ),
                                    .init(color: .clear, location: 1)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 240
                            )
                        )
                        .frame(width: 460, height: 310)
                        .blur(radius: 18)
                        .position(
                            x: graphGeometry.size.width / 2,
                            y: graphGeometry.size.height * 0.54
                        )

                    ForEach(1..<4, id: \.self) { row in
                        Path { path in
                            let y = graphGeometry.size.height * CGFloat(row) / 4
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: graphGeometry.size.width, y: y))
                        }
                        .stroke(
                            .white.opacity(0.05),
                            style: StrokeStyle(lineWidth: 1.2, dash: [22, 28])
                        )
                    }

                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    stops: [
                                        .init(
                                            color: AppBrand.dark.opacity(0.60),
                                            location: 0
                                        ),
                                        .init(
                                            color: AppBrand.dark.opacity(0.28),
                                            location: 0.46
                                        ),
                                        .init(color: .clear, location: 1)
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 160
                                )
                            )
                            .frame(width: 320, height: 312)
                            .scaleEffect(x: 1.28, y: 0.52)
                            .position(
                                x: upperMidpoint.x,
                                y: upperMidpoint.y
                            )
                    }
                    .mask(
                        ComparisonGraphArea(
                            startY: upperStartY,
                            endY: upperEndY
                        )
                    )
                    .mask(
                        ComparisonGlowRevealMask(progress: graphProgress)
                    )

                    ZStack {
                        ComparisonGraphLine(startY: upperStartY, endY: upperEndY)
                            .stroke(
                                .white.opacity(0.96),
                                style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                            )

                        ComparisonGraphLine(startY: lowerStartY, endY: lowerEndY)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.10), .white],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                    }
                    .mask(
                        ComparisonCurveRevealMask(progress: graphProgress)
                    )

                    ComparisonCurveDot(
                        progress: graphProgress,
                        startY: upperStartY,
                        endY: upperEndY,
                        diameter: 8,
                        glowOpacity: 0
                    )

                    ComparisonCurveDot(
                        progress: graphProgress,
                        startY: lowerStartY,
                        endY: lowerEndY,
                        diameter: 7,
                        glowOpacity: 0
                    )

                    Text(L("With EasyBid"))
                        .font(.system(size: 13.75, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .frame(width: 120, alignment: .trailing)
                        .position(
                            x: curveEndX - 60,
                            y: graphGeometry.size.height * 0.16
                        )

                    Text(L("Time & Money Saved"))
                        .font(.system(size: 23.74, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.22), radius: 2.5, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 300, alignment: .center)
                        .position(
                            x: graphGeometry.size.width / 2,
                            y: -17
                        )

                    Text(L("Traditional Estimating"))
                        .font(.system(size: 13.75, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 170, alignment: .trailing)
                        .position(
                            x: curveEndX - 85,
                            y: graphGeometry.size.height * 0.67
                        )

                    Text(L("Start"))
                        .font(.system(size: 13.2, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .frame(width: 70, alignment: .leading)
                        .position(
                            x: 35,
                            y: graphGeometry.size.height * 0.94
                        )

                    Text(L("3 Months"))
                        .font(.system(size: 13.2, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .position(
                            x: graphGeometry.size.width * 0.50,
                            y: graphGeometry.size.height * 0.94
                        )

                    Text(L("6 Months"))
                        .font(.system(size: 13.2, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .frame(width: 70, alignment: .trailing)
                        .position(
                            x: curveEndX - 35,
                            y: graphGeometry.size.height * 0.94
                        )
                }
            }
            .frame(width: 330, height: 270)
            .padding(.top, 42)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: isActive) {
            graphProgress = 0
            guard isActive else {
                return
            }

            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            withAnimation(
                .timingCurve(
                    0.32,
                    0.02,
                    0.18,
                    1,
                    duration: 1.75
                )
            ) {
                graphProgress = 1
            }
        }
    }

}

private struct ComparisonCurveRevealMask: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let point = comparisonGraphPoint(
            progress: progress,
            width: rect.width,
            height: rect.height,
            startY: 0,
            endY: 0
        )
        var path = Path()
        path.addRect(
            CGRect(
                x: rect.minX,
                y: rect.minY,
                width: point.x,
                height: rect.height
            )
        )
        return path
    }
}

private struct ComparisonGlowRevealMask: View, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geometry in
            let endpoint = comparisonGraphPoint(
                progress: progress,
                width: geometry.size.width,
                height: geometry.size.height,
                startY: 0,
                endY: 0
            )
            let featherRadius: CGFloat = 14
            let revealWidth = max(0, endpoint.x - featherRadius)

            Rectangle()
                .fill(.white)
                .frame(
                    width: revealWidth,
                    height: geometry.size.height + featherRadius * 2
                )
                .blur(radius: featherRadius)
                .offset(x: -featherRadius, y: -featherRadius)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .clipped()
            .opacity(progress > 0.001 ? 1 : 0)
        }
    }
}

private struct ComparisonCurveDot: View, Animatable {
    var progress: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let diameter: CGFloat
    let glowOpacity: Double

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geometry in
            let point = comparisonGraphPoint(
                progress: progress,
                width: geometry.size.width,
                height: geometry.size.height,
                startY: startY,
                endY: endY
            )

            Circle()
                .fill(.white)
                .frame(width: diameter, height: diameter)
                .shadow(
                    color: .white.opacity(glowOpacity),
                    radius: glowOpacity > 0 ? 5 : 0
                )
                .position(x: point.x, y: point.y)
                .opacity(progress > 0.03 ? 1 : 0)
        }
    }
}

private func comparisonGraphPoint(
    progress: CGFloat,
    width: CGFloat,
    height: CGFloat,
    startY: CGFloat,
    endY: CGFloat
) -> CGPoint {
    let t = min(max(progress, 0), 1)
    let inverse = 1 - t
    let start = CGPoint(x: 0, y: height * startY)
    let controlOne = CGPoint(x: width * 0.35, y: start.y)
    let end = CGPoint(x: width * 0.96, y: height * endY)
    let controlTwo = CGPoint(x: width * 0.58, y: end.y)
    let x = inverse * inverse * inverse * start.x
        + 3 * inverse * inverse * t * controlOne.x
        + 3 * inverse * t * t * controlTwo.x
        + t * t * t * end.x
    let y = inverse * inverse * inverse * start.y
        + 3 * inverse * inverse * t * controlOne.y
        + 3 * inverse * t * t * controlTwo.y
        + t * t * t * end.y

    return CGPoint(x: x, y: y)
}

private struct ComparisonGraphLine: Shape {
    let startY: CGFloat
    let endY: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX, y: rect.height * startY)
        let end = CGPoint(x: rect.width * 0.96, y: rect.height * endY)

        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: rect.width * 0.35, y: start.y),
            control2: CGPoint(x: rect.width * 0.58, y: end.y)
        )
        return path
    }
}

private struct ComparisonGraphArea: Shape {
    let startY: CGFloat
    let endY: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = ComparisonGraphLine(startY: startY, endY: endY).path(in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * endY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct OnboardingQuestion: Identifiable {
    let id: String
    let title: String
    let highlightedTitle: String
    let options: [String]

    static let all: [OnboardingQuestion] = [
        OnboardingQuestion(
            id: "work_type",
            title: "What best describes",
            highlightedTitle: "your work?",
            options: [
                "General Contractor",
                "Handyman",
                "Specialty Trade",
                "Homeowner / Landlord"
            ]
        ),
        OnboardingQuestion(
            id: "primary_goal",
            title: "What brought you",
            highlightedTitle: "here today?",
            options: [
                "Create estimates faster",
                "Get accurate pricing",
                "Send professional invoices",
                "Grow my business"
            ]
        ),
        OnboardingQuestion(
            id: "estimate_volume",
            title: "How many estimates",
            highlightedTitle: "per month?",
            options: [
                "10+",
                "5–9",
                "1–4",
                "None yet — just exploring"
            ]
        ),
        OnboardingQuestion(
            id: "biggest_slowdown",
            title: "What slows you",
            highlightedTitle: "down the most?",
            options: [
                "Estimates take too long",
                "Pricing is often off",
                "Bids look unprofessional",
                "Losing jobs to competitors"
            ]
        )
    ]
}

private struct OnboardingQuestionPage: View {
    let question: OnboardingQuestion
    @Binding var selection: String?
    var isActive: Bool = true
    let onContinue: () -> Void

    private let accent = AppBrand.light
    private let navy = AppBrand.dark

    var body: some View {
        GeometryReader { geometry in
            let designScale = min(max(geometry.size.width / 402, 0.88), 1.10)
            let bottomPadding = max(
                54,
                geometry.safeAreaInsets.bottom + 40
            )

            VStack(spacing: 0) {
                Spacer(
                    minLength: max(
                        148 * designScale,
                        geometry.safeAreaInsets.top + (112 * designScale)
                    )
                )

                VStack(alignment: .center, spacing: 4 * designScale) {
                    Text(L(question.title))
                        .foregroundStyle(navy)

                    Text(L(question.highlightedTitle))
                        .foregroundStyle(accent)
                }
                .font(
                    .system(
                        size: 24.75,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 26 * designScale)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 34 * designScale)
                .offset(y: -25 * designScale)
                .onboardingReveal(isActive, delay: 0.05)

                VStack(spacing: 12 * designScale) {
                    ForEach(Array(question.options.enumerated()), id: \.element) { index, option in
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                                selection = option
                            }
                        } label: {
                            HStack(spacing: 12 * designScale) {
                                Text(L(option))
                                    .font(.system(size: 17 * designScale, weight: selection == option ? .semibold : .medium, design: .rounded))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if selection == option {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13 * designScale, weight: .bold))
                                        .foregroundStyle(AppGray.ink)
                                        .frame(width: 21.25 * designScale, height: 21.25 * designScale)
                                        .background(.white)
                                        .clipShape(Circle())
                                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                                } else {
                                    Circle()
                                        .strokeBorder(AppGray.border.opacity(0.8), lineWidth: 1)
                                        .frame(width: 21.25 * designScale, height: 21.25 * designScale)
                                }
                            }
                            .foregroundStyle(selection == option ? .white : navy)
                            .padding(.horizontal, 20 * designScale)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56.375)
                            .background(
                                selection == option
                                    ? AnyShapeStyle(OnboardingInk.selectedOption)
                                    : AnyShapeStyle(Color.white.opacity(0.35))
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 15 * designScale,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 15 * designScale,
                                    style: .continuous
                                )
                                    .strokeBorder(
                                        selection == option ? .clear : Color.white.opacity(0.85),
                                        lineWidth: 1
                                    )
                            }
                            // Liquid Glass answer cards over the light touch gradient.
                            .glassEffect(
                                .regular.tint(selection == option ? AppGray.ink.opacity(0.4) : .white.opacity(0.25)).interactive(),
                                in: RoundedRectangle(cornerRadius: 15 * designScale, style: .continuous)
                            )
                            .overlay { OnboardingSelectionBurst(isOn: selection == option, cornerRadius: 15 * designScale) }
                            .scaleEffect(selection == option ? 1.02 : 1)
                        }
                        .buttonStyle(OnboardingPressStyle())
                        .onboardingTapHaptic()
                        // Answers cascade in one after another.
                        .onboardingReveal(isActive, delay: 0.14 + Double(index) * 0.06)
                    }
                }
                .padding(.horizontal, 26 * designScale)
                .frame(
                    height: max(
                        (62 * designScale * 4) + (12 * designScale * 3),
                        (56.375 * 4) + (12 * designScale * 3)
                    ),
                    alignment: .top
                )

                Spacer(minLength: 24 * designScale)

                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text(L("Continue"))
                        OnboardingArrow()
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle(height: 56.375))
                .disabled(selection == nil)
                .onboardingTapHaptic()
                .padding(.horizontal, 26 * designScale)
                .onboardingReveal(isActive, delay: 0.45)
            }
            .padding(.bottom, bottomPadding)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

private struct EstimatorBuildOnboardingPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @State private var progress = 0

    private let progressSteps: [(value: Int, delayMilliseconds: Int)] = [
        (3, 250),
        (9, 350),
        (17, 400),
        (29, 450),
        (42, 450),
        (56, 500),
        (68, 500),
        (78, 550),
        (86, 600),
        (91, 650),
        (95, 700),
        (98, 800),
        (100, 800)
    ]

    private var isComplete: Bool {
        progress == 100
    }

    var body: some View {
        GeometryReader { geometry in
            let visualHeight = min(max(geometry.size.height * 0.405, 290), 340)
            let visualTop = max(82, geometry.safeAreaInsets.top + 54)
            let lowerPanelHeight = geometry.size.height * 0.445
            let lowerPanelTopPadding = max(48, min(68, geometry.size.height * 0.075))
            let lowerPanelBottomPadding = max(54, geometry.safeAreaInsets.bottom + 40)

            ZStack(alignment: .bottom) {
                ZStack {
                    if isActive {
                        toolCarousel
                            .frame(width: geometry.size.width, height: visualHeight)
                            .opacity(0.48)
                            .blur(radius: 2.25)
                            .transition(.identity)
                    }

                    EstimatorProgressRing(progress: progress, foreground: .white)
                    .frame(width: 156, height: 156)
                    // A slowly turning ring of light around the progress ring.
                    .background {
                        OnboardingHalo()
                            .frame(width: 178, height: 178)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                    // A springy pop and a burst of sparks when it reaches 100%.
                    .scaleEffect(isComplete ? 1.08 : 1)
                    .animation(.spring(response: 0.45, dampingFraction: 0.45), value: isComplete)
                    .background { OnboardingCelebrationBurst(trigger: isComplete) }
                    .onboardingFloat()
                }
                .frame(width: geometry.size.width, height: visualHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, visualTop)
                .zIndex(0)

                UnevenRoundedRectangle(
                    topLeadingRadius: 34,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 34
                )
                .fill(
                    OnboardingInk.panel
                )
                .frame(height: lowerPanelHeight + geometry.safeAreaInsets.bottom)
                .offset(y: geometry.safeAreaInsets.bottom)
                .zIndex(1)

                VStack(spacing: 0) {
                    Text(L("Building your custom estimator"))
                        .font(.system(size: 23.74, weight: .medium, design: .rounded))
                        .foregroundStyle(AppGray.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .offset(y: -4)
                        .onboardingReveal(isActive, delay: 0.08)

                    Spacer(minLength: 14)

                    EstimatorBuildChecklist(progress: progress)
                        .offset(y: -8)

                    Spacer(minLength: 14)

                    Button(action: onContinue) {
                        HStack(spacing: 8) {
                            Text(L("Get Started"))
                            OnboardingArrow()
                        }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(!isComplete)
                    .onboardingTapHaptic()
                    .onboardingReveal(isActive, delay: 0.3)
                }
                .padding(.horizontal, 42)
                .padding(.top, lowerPanelTopPadding)
                .padding(.bottom, lowerPanelBottomPadding)
                .frame(height: lowerPanelHeight, alignment: .top)
                .zIndex(3)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .task(id: isActive) {
            progress = 0
            guard isActive else { return }

            for step in progressSteps {
                try? await Task.sleep(for: .milliseconds(step.delayMilliseconds))
                guard !Task.isCancelled, isActive else { return }
                withAnimation(
                    .easeInOut(
                        duration: min(Double(step.delayMilliseconds) / 1_000 * 0.8, 0.55)
                    )
                ) {
                    progress = step.value
                }
                if [9, 56, 100].contains(step.value) {
                    OnboardingHaptics.estimatorStatusReached()
                }
            }
        }
    }

    private var toolCarousel: some View {
        VStack(spacing: 14) {
            ToolCarouselRow(
                icons: ["hammer.fill", "screwdriver.fill", "tag.fill", "spigot.fill", "shower.fill"],
                direction: -1,
                speed: 22
            )

            ToolCarouselRow(
                icons: ["shower.fill", "spigot.fill", "tag.fill", "screwdriver.fill", "hammer.fill"],
                direction: 1,
                speed: 25
            )

            ToolCarouselRow(
                icons: ["tag.fill", "hammer.fill", "shower.fill", "screwdriver.fill", "spigot.fill"],
                direction: -1,
                speed: 28
            )
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct ToolCarouselRow: View {
    let icons: [String]
    let direction: CGFloat
    let speed: TimeInterval

    private let tileSize: CGFloat = 100
    private let spacing: CGFloat = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let rowWidth = CGFloat(icons.count) * (tileSize + spacing)
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: speed) / speed
            let travel = CGFloat(phase) * rowWidth

            HStack(spacing: spacing) {
                ForEach(0..<15, id: \.self) { index in
                    ToolCarouselTile(icon: icons[index % icons.count])
                        .frame(width: tileSize, height: tileSize)
                }
            }
            .offset(x: direction < 0 ? -travel : travel - rowWidth)
            .frame(maxWidth: .infinity)
        }
        .frame(height: tileSize)
    }
}

private struct EstimatorBuildChecklist: View {
    let progress: Int

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            checklistRow(
                "Setting up your workspace",
                isReached: progress >= 9
            )

            checklistRow(
                "Customizing your estimator",
                isReached: progress >= 56
            )

            checklistRow(
                "Ready!",
                isReached: progress >= 100
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func checklistRow(_ title: String, isReached: Bool) -> some View {
        Text(L(title))
            .font(.system(size: 18.7, weight: .medium, design: .rounded))
            .foregroundStyle(isReached ? AppGray.ink : AppGray.muted)
            .multilineTextAlignment(.center)
            .overlay(alignment: .leading) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppGray.secondary)
                    .frame(width: 18, height: 18)
                    .offset(x: -26)
                    .opacity(isReached ? 1 : 0)
                    // Each check springs in as its step completes.
                    .scaleEffect(isReached ? 1 : 0.3)
                    .rotationEffect(.degrees(isReached ? 0 : -25))
                    .animation(.spring(response: 0.42, dampingFraction: 0.55), value: isReached)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.25), value: isReached)
    }
}

private struct ToolCarouselTile: View {
    let icon: String

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.white.opacity(0.13))
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
    }
}

private struct OnboardingTopNavigation: View {
    let currentPage: Int
    let pageCount: Int
    let usesLightBackground: Bool
    let onBack: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let designScale = min(max(geometry.size.width / 402, 0.88), 1.10)

            VStack {
                HStack(spacing: 22 * designScale) {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 25 * designScale, weight: .medium))
                            .foregroundStyle(usesLightBackground ? AppBrand.dark : .white)
                            .frame(width: 34 * designScale, height: 34 * designScale)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onboardingTapHaptic()
                    .accessibilityLabel(L("Previous onboarding page"))

                    GeometryReader { progressGeometry in
                        let progress = CGFloat(currentPage + 1) / CGFloat(max(pageCount, 1))

                        Capsule()
                            .fill(
                                usesLightBackground
                                    ? Color(hex: 0xE1E7EE)
                                    : AppBrand.dark.opacity(0.82)
                            )
                            .overlay(alignment: .leading) {
                                // Gradient fill with a soft light travelling along it.
                                Capsule()
                                    .fill(usesLightBackground ? OnboardingInk.progressOnLight : OnboardingInk.progressOnDark)
                                    .overlay { OnboardingProgressShimmer() }
                                    .clipShape(Capsule())
                                    .frame(width: progressGeometry.size.width * progress)
                            }
                            .animation(.easeInOut(duration: 0.55), value: currentPage)
                            .animation(.easeInOut(duration: 0.25), value: usesLightBackground)
                    }
                    .frame(height: 5.75 * designScale)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("Page %ld of %ld", currentPage + 1, pageCount))

                    LanguageToggle(
                        usesLightBackground: usesLightBackground,
                        scale: designScale
                    )
                }
                .padding(.leading, 28 * designScale)
                .padding(.trailing, 20 * designScale)
                .padding(.top, 18 * designScale)

                Spacer()
            }
        }
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool
    let onNext: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let standardArtworkWidth = min(geometry.size.width - 44, 350)
            // The job photo is a smaller, framed card under the top bar.
            let artworkWidth = page.placeholder == .photo
                ? min(geometry.size.width - 64, 338)
                : standardArtworkWidth
            let standardArtworkHeight = min(geometry.size.height * 0.52, 430)
            let lowerPanelHeight = geometry.size.height * 0.445
            let lowerPanelTopPadding = max(48, min(68, geometry.size.height * 0.075))
            let lowerPanelBottomPadding = max(54, geometry.safeAreaInsets.bottom + 40)
            let artworkTop = page.placeholder == .photo
                ? max(106, geometry.safeAreaInsets.top + 74)
                : max(112, geometry.safeAreaInsets.top + 82)
            let lowerPanelTop = geometry.size.height - lowerPanelHeight
            // Sized to the space above the panel (only a sliver tucks under it).
            let artworkHeight = page.placeholder == .photo
                ? max(200, min(380, lowerPanelTop - artworkTop + 24))
                : standardArtworkHeight
            let visibleArtworkHeight = min(
                artworkHeight,
                max(0, lowerPanelTop - artworkTop)
            )
            let artworkOverlap = max(0, artworkTop + artworkHeight - lowerPanelTop)
            let artworkPreFadeHeight = max(40, min(54, artworkHeight * 0.125))

            ZStack(alignment: .bottom) {
                OnboardingArtworkPlaceholder(
                    kind: page.placeholder,
                    isActive: isActive,
                    visibleCardHeight: visibleArtworkHeight
                )
                .frame(width: artworkWidth, height: artworkHeight, alignment: .top)
                .overlay(alignment: .bottom) {
                    if page.placeholder != .photo {
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0), location: 0),
                                    .init(color: .white.opacity(0.42), location: 0.28),
                                    .init(color: .white.opacity(0.88), location: 0.64),
                                    .init(color: .white, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: artworkPreFadeHeight)

                            Color.white
                                .frame(height: artworkOverlap)
                        }
                        .frame(height: artworkPreFadeHeight + artworkOverlap)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .allowsHitTesting(false)
                    }
                }
                .mask(alignment: .top) {
                    if page.placeholder == .photo {
                        Color.white
                    } else {
                        VStack(spacing: 0) {
                            Color.white

                            LinearGradient(
                                stops: [
                                    .init(color: .white, location: 0),
                                    .init(color: .white, location: 0.42),
                                    .init(color: .white.opacity(0.45), location: 0.78),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: artworkOverlap)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, artworkTop)
                .zIndex(page.placeholder == .photo ? 0 : 2)

                UnevenRoundedRectangle(
                    topLeadingRadius: 30,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 30
                )
                .fill(
                    OnboardingInk.panel
                )
                .shadow(color: .black.opacity(0.10), radius: 18, y: -4)
                .frame(height: lowerPanelHeight + geometry.safeAreaInsets.bottom)
                .offset(y: geometry.safeAreaInsets.bottom)
                .zIndex(1)

                VStack(alignment: .leading, spacing: 0) {
                    pageCopy

                    Spacer(minLength: 24)

                    Button(action: onNext) {
                        HStack(spacing: 8) {
                            Text(L(page.isLast ? "Get started" : "Next"))
                            OnboardingArrow()
                        }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .onboardingTapHaptic()
                    .onboardingReveal(isActive, delay: 0.32)
                    .zIndex(2)
                    .accessibilityLabel(L(page.isLast ? "Finish onboarding" : "Next onboarding page"))
                }
                .padding(.horizontal, 42)
                .padding(.top, lowerPanelTopPadding)
                .padding(.bottom, lowerPanelBottomPadding)
                .frame(height: lowerPanelHeight, alignment: .top)
                .zIndex(3)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var pageCopy: some View {
        VStack(alignment: .center, spacing: 14) {
            Text(L(page.title))
                .font(.system(size: 23.74, weight: .medium, design: .rounded))
                .foregroundStyle(AppGray.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .onboardingReveal(isActive, delay: 0.08)

            if let subtitle = page.subtitle {
                Text(L(subtitle))
                    .font(.system(size: 16.37, weight: .regular, design: .rounded))
                    .foregroundStyle(AppGray.itemText.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .onboardingReveal(isActive, delay: 0.2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OnboardingArtworkPlaceholder: View {
    let kind: PlaceholderKind
    let isActive: Bool
    let visibleCardHeight: CGFloat

    var body: some View {
        let cornerRadius: CGFloat = kind == .photo ? 24 : 20

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.white)

            switch kind {
            case .welcome:
                welcomePlaceholder
            case .photo:
                AnimatedOnboardingPhotoAnalysis(
                    isActive: isActive,
                    visibleCardHeight: visibleCardHeight
                )
            case .estimate:
                AnimatedOnboardingEstimateCard(isActive: isActive)
            case .invoice:
                AnimatedOnboardingInvoiceCard(isActive: isActive)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(
            color: AppBrand.dark.opacity(
                kind == .photo ? 0.24 : (kind.usesDetailedCardLayout ? 0.18 : 0.11)
            ),
            radius: kind == .photo ? 22 : 18,
            y: kind == .photo ? 10 : (kind.usesDetailedCardLayout ? 7 : 8)
        )
        // The card rises gently into place: a short fade and lift, no tilt or bounce.
        .scaleEffect(isActive ? 1 : 0.98)
        .offset(y: isActive ? 0 : 22)
        .opacity(isActive ? 1 : 0)
        .animation(.easeOut(duration: 0.55).delay(isActive ? 0.05 : 0), value: isActive)
        .accessibilityHidden(true)
    }

    private var welcomePlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(AppBrand.verticalGradient)

            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(.white.opacity(0.14))
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                    }

                VStack(spacing: 7) {
                    Text(L("EasyBid"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(L("QUOTE  •  WIN  •  GROW"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .padding(12)
    }

    private func documentPlaceholder(rowCount: Int, showsTotals: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            placeholderHeader

            ForEach(0..<rowCount, id: \.self) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule()
                            .fill(OnboardingPalette.placeholderLine)
                            .frame(width: row.isMultiple(of: 2) ? 116 : 142, height: 8)
                        Capsule()
                            .fill(OnboardingPalette.placeholderLine.opacity(0.48))
                            .frame(width: 70, height: 6)
                    }

                    Spacer()

                    if showsTotals {
                        Capsule()
                            .fill(OnboardingPalette.placeholderLine.opacity(0.8))
                            .frame(width: 42, height: 8)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(OnboardingPalette.placeholderLine, lineWidth: 1)
                            .frame(width: 56, height: 24)
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 18)

                if row < rowCount - 1 {
                    Divider().opacity(0.55)
                }
            }

            Spacer(minLength: 4)
        }
    }

    private var invoicePlaceholder: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(OnboardingPalette.placeholderFill)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(OnboardingPalette.placeholderLine).frame(width: 82, height: 8)
                    Capsule().fill(OnboardingPalette.placeholderLine.opacity(0.55)).frame(width: 54, height: 6)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Capsule().fill(OnboardingPalette.placeholderLine.opacity(0.55)).frame(width: 44, height: 6)
                    Capsule().fill(OnboardingPalette.placeholderLine).frame(width: 58, height: 10)
                }
            }

            Divider()

            ForEach(0..<5, id: \.self) { row in
                HStack {
                    Capsule()
                        .fill(OnboardingPalette.placeholderLine.opacity(row == 4 ? 0.4 : 0.82))
                        .frame(width: row.isMultiple(of: 2) ? 128 : 106, height: 7)
                    Spacer()
                    Capsule()
                        .fill(OnboardingPalette.placeholderLine.opacity(0.65))
                        .frame(width: 38, height: 7)
                }
            }

            Spacer()
        }
        .padding(18)
    }

    private var placeholderHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(OnboardingPalette.placeholderLine.opacity(0.48))
                .frame(width: 48, height: 6)
            Capsule()
                .fill(OnboardingPalette.placeholderLine)
                .frame(width: 174, height: 10)
            Capsule()
                .fill(OnboardingPalette.placeholderLine.opacity(0.62))
                .frame(width: 92, height: 7)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingPalette.placeholderFill.opacity(0.35))
    }
}

private struct AnimatedOnboardingPhotoAnalysis: View {
    let isActive: Bool
    let visibleCardHeight: CGFloat

    @State private var revealStep = 0
    @State private var scanStartedAt = Date()

    var body: some View {
        GeometryReader { geometry in
            let visibleHeight = min(max(visibleCardHeight, 0), geometry.size.height)
            let scanOvershoot: CGFloat = 100

            ZStack {
                Image("bathroom pre remodel 1")
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .top
                    )
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.08), location: 0.18),
                        .init(color: .black.opacity(0.24), location: 0.52),
                        .init(color: .black.opacity(0.34), location: 0.76),
                        .init(color: .black.opacity(0.34), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                if isActive, visibleHeight > 0 {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        let halfCycleDuration = 2.0
                        let fullCycleDuration = halfCycleDuration * 2
                        let elapsed = max(
                            0,
                            timeline.date.timeIntervalSince(scanStartedAt)
                        )
                        let cycleTime = elapsed.truncatingRemainder(
                            dividingBy: fullCycleDuration
                        )
                        let scanProgress = cycleTime <= halfCycleDuration
                            ? cycleTime / halfCycleDuration
                            : (fullCycleDuration - cycleTime) / halfCycleDuration

                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.18), location: 0.16),
                                .init(color: .white.opacity(0.42), location: 0.32),
                                .init(color: .white.opacity(0.78), location: 0.43),
                                .init(color: .white, location: 0.50),
                                .init(color: .white.opacity(0.78), location: 0.57),
                                .init(color: .white.opacity(0.42), location: 0.68),
                                .init(color: .white.opacity(0.18), location: 0.84),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 100)
                        .blur(radius: 9)
                        .blendMode(.screen)
                        .position(
                            x: geometry.size.width / 2,
                            y: -scanOvershoot
                                + CGFloat(scanProgress)
                                    * (visibleHeight + (scanOvershoot * 2))
                        )
                    }
                    .frame(
                        width: geometry.size.width,
                        height: visibleHeight,
                        alignment: .top
                    )
                    .clipped()
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                }

                PhotoPriceCallout(
                    title: "Total labor",
                    amount: 6_000,
                    isVisible: revealStep >= 1
                )
                .position(
                    x: geometry.size.width * 0.29,
                    y: geometry.size.height * 0.31
                )

                PhotoPriceCallout(
                    title: "Replace countertop",
                    amount: 900,
                    isVisible: revealStep >= 2
                )
                .position(
                    x: geometry.size.width * 0.74,
                    y: geometry.size.height * 0.54
                )

                PhotoPriceCallout(
                    title: "Remove floor tile",
                    amount: 350,
                    isVisible: revealStep >= 3
                )
                .position(
                    x: geometry.size.width * 0.28,
                    y: geometry.size.height * 0.61
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .task(id: isActive) {
            revealStep = 0
            scanStartedAt = Date()
            guard isActive else { return }

            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, isActive else { return }
            OnboardingHaptics.priceTagReveal()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                revealStep = 1
            }

            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, isActive else { return }
            OnboardingHaptics.priceTagReveal()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                revealStep = 2
            }

            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, isActive else { return }
            OnboardingHaptics.priceTagReveal()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                revealStep = 3
            }
        }
    }
}

private struct PhotoPriceCallout: View {
    let title: String
    let amount: Int
    let isVisible: Bool

    @State private var isTitleVisible = false
    @State private var isAmountVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L(title))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGray.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(isTitleVisible ? 1 : 0)
                .scaleEffect(isTitleVisible ? 1 : 0.96, anchor: .leading)
                .offset(y: isTitleVisible ? 0 : 2)

            Text("$\(amount.formatted())")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(AppGray.ink)
                .opacity(isAmountVisible ? 1 : 0)
                .scaleEffect(isAmountVisible ? 1 : 0.96, anchor: .leading)
                .offset(y: isAmountVisible ? 0 : 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.30), radius: 11, y: 5)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .scaleEffect(isVisible ? 1 : 0.92)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 4)
        .animation(
            .spring(response: 0.46, dampingFraction: 0.70, blendDuration: 0.08),
            value: isVisible
        )
        .task(id: isVisible) {
            isTitleVisible = false
            isAmountVisible = false
            guard isVisible else { return }

            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, isVisible else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                isTitleVisible = true
            }

            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled, isVisible else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                isAmountVisible = true
            }
        }
    }
}

private struct AnimatedOnboardingEstimateCard: View {
    let isActive: Bool

    @State private var revealStep = 0

    private let rows = [
        EstimatePreviewRow(label: "Materials", value: 7_850),
        EstimatePreviewRow(label: "Labor", value: 6_000),
        EstimatePreviewRow(label: "Contingency 10%", value: 1_385)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 12)

            VStack(alignment: .leading, spacing: 19) {
                Text(L("Bathroom Remodel\n(1 job)"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppGray.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    Circle()
                        .stroke(AppGray.secondary, lineWidth: 1)
                        .frame(width: 10, height: 10)
                    Text(L("Draft"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppGray.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(AppGray.border, lineWidth: 1)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 17)
            .opacity(revealStep >= 1 ? 1 : 0)
            .offset(y: revealStep >= 1 ? 0 : 9)

            Rectangle()
                .fill(AppGray.badge.opacity(0.85))
                .frame(height: 0.7)
                .frame(maxWidth: .infinity)
                .opacity(revealStep >= 1 ? 1 : 0)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                estimateRow(row, step: index + 2)
                Rectangle()
                    .fill(AppGray.badge.opacity(0.85))
                    .frame(height: 0.7)
                    .frame(maxWidth: .infinity)
                    .opacity(revealStep >= index + 2 ? 1 : 0)
            }

            HStack {
                Text(L("Recommended Quote"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppGray.itemText)
                Spacer()
                CountingCurrencyText(value: 15_235, isVisible: revealStep >= 5)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppGray.itemText)
            }
            .padding(.horizontal, 24)
            .frame(height: 54)
            .opacity(revealStep >= 5 ? 1 : 0)
            .offset(y: revealStep >= 5 ? 0 : 8)
            .scaleEffect(revealStep >= 5 ? 1 : 0.97)

            Rectangle()
                .fill(AppGray.badge.opacity(0.85))
                .frame(height: 0.7)
                .frame(maxWidth: .infinity)
                .opacity(revealStep >= 5 ? 1 : 0)

            VStack(alignment: .leading, spacing: 5) {
                Text(L("What's not included"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppGray.itemText)
                Text(L("Permits unless explicitly listed\nHidden water or mold damage"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppGray.secondary)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 14)
            .opacity(revealStep >= 6 ? 1 : 0)
            .offset(y: revealStep >= 6 ? 0 : 7)

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .animation(.easeOut(duration: 0.38), value: revealStep)
        .task(id: isActive) {
            guard isActive else {
                revealStep = 0
                return
            }

            revealStep = 0
            try? await Task.sleep(for: .milliseconds(140))

            for step in 1...6 {
                guard !Task.isCancelled else { return }
                revealStep = step
                try? await Task.sleep(for: .milliseconds(step == 1 ? 150 : 105))
            }
        }
    }

    private func estimateRow(_ row: EstimatePreviewRow, step: Int) -> some View {
        HStack {
            Text(L(row.label))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppGray.itemText)
            Spacer()
            CountingCurrencyText(value: row.value, isVisible: revealStep >= step)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppGray.itemText)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(AppGray.borderStrong)
                .padding(.leading, 3)
        }
        .padding(.horizontal, 24)
        .frame(height: 50)
        .opacity(revealStep >= step ? 1 : 0)
        .offset(y: revealStep >= step ? 0 : 8)
    }
}

private struct AnimatedOnboardingMaterialsCard: View {
    let isActive: Bool

    @State private var revealStep = 0

    private let rows = [
        MaterialPreviewRow(
            name: "Tankless Water Heater Isolation Valve Kit 3/4\"",
            price: "$88.88",
            quantity: "1"
        ),
        MaterialPreviewRow(
            name: "3/4\" Inline Scale Filter",
            price: "$16.45",
            quantity: "1"
        ),
        MaterialPreviewRow(
            name: "Fluidmaster 3/4\" Water Heater Connector (18 in.)",
            price: "$16.39",
            quantity: "2"
        ),
        MaterialPreviewRow(
            name: "3/4\" Copper Pipe Type L (per ft)",
            price: "$8.94",
            quantity: "6"
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("Tankless Water Heater Installation\n(1 job)"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppGray.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .semibold))
                        Text(L("Add"))
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(AppGray.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(AppGray.border, lineWidth: 1)
                    }

                    Text(L("8 items"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppGray.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .opacity(revealStep >= 1 ? 1 : 0)
            .offset(y: revealStep >= 1 ? 0 : 9)

            Divider()
                .frame(maxWidth: .infinity)
                .opacity(revealStep >= 1 ? 1 : 0)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                materialRow(row, step: index + 2)

                if index < rows.count - 1 {
                    Divider()
                        .frame(maxWidth: .infinity)
                        .opacity(revealStep >= index + 2 ? 1 : 0)
                }
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .animation(.easeOut(duration: 0.38), value: revealStep)
        .task(id: isActive) {
            guard isActive else {
                revealStep = 0
                return
            }

            revealStep = 0
            try? await Task.sleep(for: .milliseconds(140))

            for step in 1...5 {
                guard !Task.isCancelled else { return }
                revealStep = step
                try? await Task.sleep(for: .milliseconds(step == 1 ? 150 : 115))
            }
        }
    }

    private func materialRow(_ row: MaterialPreviewRow, step: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(L(row.name))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppGray.itemText)
                    .lineLimit(2)

                Spacer(minLength: 4)

                Text(row.price)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppGray.itemText)
            }

            HStack(spacing: 7) {
                HStack(spacing: 0) {
                    Text("−")
                        .frame(width: 21)
                    Divider()
                    Text(row.quantity)
                        .frame(width: 24)
                    Divider()
                    Text("+")
                        .frame(width: 21)
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppGray.secondary)
                .frame(height: 25)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(AppGray.border, lineWidth: 1)
                }

                Text(L("each"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppGray.secondary)

                Spacer()

                Text(L("Edit Line"))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(AppGray.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 25)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(AppGray.border, lineWidth: 1)
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .opacity(revealStep >= step ? 1 : 0)
        .offset(y: revealStep >= step ? 0 : 8)
    }
}

private struct AnimatedOnboardingInvoiceCard: View {
    let isActive: Bool

    @State private var revealStep = 0

    private let rows = [
        InvoicePreviewRow(description: "Demolition and haul-away", quantity: "1", amount: "$1,250"),
        InvoicePreviewRow(description: "Porcelain floor tile", quantity: "120", amount: "$1,800"),
        InvoicePreviewRow(description: "Vanity and countertop", quantity: "1", amount: "$2,450"),
        InvoicePreviewRow(description: "Shower waterproofing", quantity: "1", amount: "$1,350"),
        InvoicePreviewRow(description: "Shower wall tile", quantity: "95", amount: "$2,375"),
        InvoicePreviewRow(description: "Finish carpentry and paint", quantity: "1", amount: "$1,100")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 12)

            invoiceHeader
                .opacity(revealStep >= 1 ? 1 : 0)
                .offset(y: revealStep >= 1 ? 0 : 9)

            Rectangle()
                .fill(AppGray.badge.opacity(0.85))
                .frame(height: 0.7)
                .padding(.horizontal, 24)
                .opacity(revealStep >= 1 ? 1 : 0)

            billingDetails
                .opacity(revealStep >= 2 ? 1 : 0)
                .offset(y: revealStep >= 2 ? 0 : 8)

            invoiceTableHeader
                .opacity(revealStep >= 3 ? 1 : 0)
                .offset(y: revealStep >= 3 ? 0 : 7)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                invoiceRow(row, step: index + 4)

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(AppGray.badge.opacity(0.85))
                        .frame(height: 0.7)
                        .padding(.horizontal, 24)
                        .opacity(revealStep >= index + 4 ? 1 : 0)
                }
            }

            Spacer(minLength: 6)
        }
        .background(Color.white)
        .animation(.easeOut(duration: 0.38), value: revealStep)
        .task(id: isActive) {
            guard isActive else {
                revealStep = 0
                return
            }

            revealStep = 0
            try? await Task.sleep(for: .milliseconds(140))

            for step in 1...9 {
                guard !Task.isCancelled else { return }
                revealStep = step
                try? await Task.sleep(for: .milliseconds(step == 1 ? 150 : 95))
            }
        }
    }

    private var invoiceHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Mesa Ridge Remodeling"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppGray.ink)
                Text(L("Albuquerque, NM"))
                    .foregroundStyle(AppGray.secondary)
                Text("(505) 555-1234")
                    .foregroundStyle(AppGray.secondary)
            }
            .font(.system(size: 13))

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 5) {
                Text("#10024")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppGray.ink)
                Text(L("June 29, 2025"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppGray.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 19)
        .padding(.bottom, 16)
    }

    private var billingDetails: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Bill To"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppGray.itemText)
                Text(L("John Smith"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppGray.itemText)
                Text(L("123 Mesa View Dr."))
                Text(L("Albuquerque, NM 87110"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Service Address"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppGray.itemText)
                Text(L("John Smith"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppGray.itemText)
                Text(L("123 Mesa View Dr."))
                Text(L("Albuquerque, NM 87110"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
        .foregroundStyle(AppGray.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var invoiceTableHeader: some View {
        HStack {
            Text(L("Description"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L("Qty"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 28)
            Text(L("Amount"))
                .frame(width: 60, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppGray.itemText)
        .padding(.horizontal, 24)
        .frame(height: 28)
    }

    private func invoiceRow(_ row: InvoicePreviewRow, step: Int) -> some View {
        HStack(alignment: .top) {
            Text(L(row.description))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
            Text(row.quantity)
                .frame(width: 28)
            Text(row.amount)
                .frame(width: 60, alignment: .trailing)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(AppGray.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .opacity(revealStep >= step ? 1 : 0)
        .offset(y: revealStep >= step ? 0 : 7)
    }
}

private struct EstimatePreviewRow {
    let label: String
    let value: Double
}

private struct CountingCurrencyText: View {
    let value: Double
    let isVisible: Bool

    @State private var displayedValue: Double = 0

    var body: some View {
        HStack(spacing: 0) {
            Text("$")

            ZStack(alignment: .trailing) {
                Text(
                    value,
                    format: .number
                        .grouping(.automatic)
                        .precision(.fractionLength(2))
                )
                .monospacedDigit()
                .hidden()

                Text(
                    displayedValue,
                    format: .number
                        .grouping(.automatic)
                        .precision(.fractionLength(2))
                )
                .contentTransition(.numericText(value: displayedValue))
                .monospacedDigit()
            }
        }
        .task(id: isVisible) {
            guard isVisible else {
                displayedValue = 0
                return
            }

            displayedValue = 0
            try? await Task.sleep(for: .milliseconds(90))

            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.72)) {
                displayedValue = value
            }
        }
    }
}

private struct MaterialPreviewRow {
    let name: String
    let price: String
    let quantity: String
}

private struct InvoicePreviewRow {
    let description: String
    let quantity: String
    let amount: String
}

private struct OnboardingPage {
    let title: String
    let subtitle: String?
    let placeholder: PlaceholderKind
    let isLast: Bool

    static let all: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to EasyBid",
            subtitle: "Start winning more jobs today with faster estimates, local pricing, and professional invoices.",
            placeholder: .welcome,
            isLast: false
        ),
        OnboardingPage(
            title: "Get an instant estimate\nfrom a photo of the job",
            subtitle: "Take a photo, add a voice note or a few words, and we’ll make a precise estimate in under 60 seconds.",
            placeholder: .photo,
            isLast: false
        ),
        OnboardingPage(
            title: "Complete cost breakdowns\nfor every job",
            subtitle: "Review labor, materials, and project costs before you send the estimate.",
            placeholder: .estimate,
            isLast: false
        ),
        OnboardingPage(
            title: "Send invoices fast\nbefore leaving the job",
            subtitle: "Create a professional invoice and send it before you leave the job.",
            placeholder: .invoice,
            isLast: false
        )
    ]
}

private enum PlaceholderKind: Equatable {
    case welcome
    case photo
    case estimate
    case invoice

    var usesDetailedCardLayout: Bool {
        self == .estimate || self == .invoice
    }
}

private enum OnboardingPalette {
    static let placeholderFill = Color(hex: 0xF1F4F7)
    static let placeholderLine = Color(hex: 0xC8D0D8)
}

@MainActor
private enum OnboardingHaptics {
    static func buttonTap() {
        UIImpactFeedbackGenerator(style: .light)
            .impactOccurred(intensity: 0.68)
    }

    static func estimatorStatusReached() {
        UINotificationFeedbackGenerator()
            .notificationOccurred(.success)
    }

    static func priceTagReveal() {
        UIImpactFeedbackGenerator(style: .soft)
            .impactOccurred(intensity: 0.58)
    }
}

private extension View {
    func onboardingTapHaptic() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                OnboardingHaptics.buttonTap()
            }
        )
    }
}

#Preview("Onboarding") {
    OnboardingView()
        .environment(AuthStore())
}

#Preview("Estimate Animation") {
    OnboardingView(initialPage: OnboardingView.firstFeaturePageIndex + 1)
        .environment(AuthStore())
}

#Preview("Welcome Sign In") {
    OnboardingView(initialPage: 0)
        .environment(AuthStore())
}

#Preview("ZIP Code") {
    OnboardingView(initialPage: OnboardingView.zipCodePageIndex)
        .environment(AuthStore())
}


/// Shared by onboarding and live estimate generation.
struct EstimatorProgressRing: View {
    let progress: Int
    let foreground: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(foreground.opacity(0.22), lineWidth: 8.5)
            Circle()
                .trim(from: 0, to: CGFloat(progress) / 100)
                .stroke(foreground, style: StrokeStyle(lineWidth: 8.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: progress)
            Text("\(progress)%")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(foreground)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(progress)))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: progress)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Progress"))
        .accessibilityValue(L("%ld percent", progress))
    }
}
