//
//  AppLanguage.swift
//  Construction Estimate
//
//  Lightweight, instant in-app language switching (English ⇄ Spanish).
//
//  Views read the active language from the environment and translate their
//  English source strings at render time:
//
//      @Environment(\.appLanguage) private var lang
//      Text(lang("Continue"))
//
//  English is the source language, so any string without a Spanish entry
//  falls back to English instead of showing a missing key.
//

import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"

    /// `UserDefaults` key used with `@AppStorage` to persist the choice.
    static let storageKey = "app.language"

    /// Matches the device language on first launch; English otherwise.
    static var deviceDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("es") ? .spanish : .english
    }

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .english: "EN"
        case .spanish: "ES"
        }
    }

    /// The language's own name, as a speaker of it would read it.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        }
    }

    var toggled: AppLanguage {
        self == .english ? .spanish : .english
    }

    var locale: Locale { Locale(identifier: rawValue) }

    /// Translates an English source string into this language.
    func callAsFunction(_ english: String) -> String {
        guard self == .spanish else { return english }
        return AppTranslations.spanish[english] ?? english
    }

    /// Translates an English `String(format:)` template, then fills it in.
    func format(_ englishFormat: String, _ arguments: CVarArg...) -> String {
        String(format: self(englishFormat), locale: locale, arguments: arguments)
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .english
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

/// English source string → Spanish translation.
private enum AppTranslations {
    static let spanish: [String: String] = [
        // Language toggle
        "Language": "Idioma",
        "Switch language": "Cambiar idioma",

        // Navigation & shared actions
        "Continue": "Continuar",
        "Next": "Siguiente",
        "Get started": "Comenzar",
        "Get Started": "Comenzar",
        "Previous onboarding page": "Página anterior",
        "Next onboarding page": "Página siguiente",
        "Finish onboarding": "Terminar la introducción",
        "Page %ld of %ld": "Página %ld de %ld",
        "Progress": "Progreso",
        "%ld percent": "%ld por ciento",
        "Paywall unavailable": "Suscripción no disponible",

        // Welcome / sign in
        "Welcome to EasyBid": "Bienvenido a EasyBid",
        "Sign in to save your estimates, clients, and\ninvoices securely across devices.":
            "Inicia sesión para guardar tus cotizaciones, clientes y\nfacturas de forma segura en todos tus dispositivos.",
        "Rated 4.9 stars": "Calificación de 4.9 estrellas",
        "Continue with Apple": "Continuar con Apple",
        "Continue with Email": "Continuar con correo",
        "Already have an account? ": "¿Ya tienes una cuenta? ",
        "Log in": "Inicia sesión",
        "By signing up, you agree to the ": "Al registrarte, aceptas la ",
        "Privacy Policy": "Política de privacidad",
        " and ": " y los ",
        "Terms of Use": "Términos de uso",
        "Apple could not complete sign in. Please try again.":
            "Apple no pudo completar el inicio de sesión. Inténtalo de nuevo.",

        // Testimonials
        "Won the kitchen remodel with a clean bid sent that afternoon.":
            "Gané la remodelación de la cocina con una oferta clara enviada esa misma tarde.",
        "Built a full home-addition estimate before leaving the site.":
            "Hice la cotización completa de una ampliación antes de salir de la obra.",
        "My estimates finally look as professional as the homes we build.":
            "Por fin mis cotizaciones se ven tan profesionales como las casas que construimos.",
        "Clients understand every allowance and upgrade without a long call.":
            "Los clientes entienden cada partida y mejora sin una llamada larga.",
        "EasyBid cut my residential estimating time in half.":
            "EasyBid redujo a la mitad mi tiempo de cotización residencial.",
        "Change orders are faster, clearer, and easier to approve.":
            "Las órdenes de cambio son más rápidas, claras y fáciles de aprobar.",
        "Alex J. · General Contractor": "Alex J. · Contratista general",
        "Mike R. · Remodeler": "Mike R. · Remodelador",
        "Chris D. · Home Builder": "Chris D. · Constructor de viviendas",
        "Taylor S. · Custom Builder": "Taylor S. · Constructor a medida",
        "Jordan P. · Residential GC": "Jordan P. · Contratista residencial",
        "Ryan M. · Renovation Contractor": "Ryan M. · Contratista de renovaciones",

        // Feature pages
        "Start winning more jobs today with faster estimates, local pricing, and professional invoices.":
            "Empieza a ganar más trabajos hoy con cotizaciones más rápidas, precios locales y facturas profesionales.",
        "Get an instant estimate\nfrom a photo of the job": "Obtén una cotización al instante\ncon una foto del trabajo",
        "Take a photo, add a voice note or a few words, and we’ll make a precise estimate in under 60 seconds.":
            "Toma una foto, agrega una nota de voz o unas palabras y haremos una cotización precisa en menos de 60 segundos.",
        "Complete cost breakdowns\nfor every job": "Desglose completo de costos\npara cada trabajo",
        "Review labor, materials, and project costs before you send the estimate.":
            "Revisa la mano de obra, los materiales y los costos del proyecto antes de enviar la cotización.",
        "Send invoices fast\nbefore leaving the job": "Envía facturas rápido\nantes de salir de la obra",
        "Create a professional invoice and send it before you leave the job.":
            "Crea una factura profesional y envíala antes de salir de la obra.",
        "QUOTE  •  WIN  •  GROW": "COTIZA  •  GANA  •  CRECE",

        // Photo analysis animation
        "Total labor": "Mano de obra",
        "Replace countertop": "Cambiar encimera",
        "Remove floor tile": "Quitar losetas",

        // Estimate card animation
        "Materials": "Materiales",
        "Labor": "Mano de obra",
        "Contingency 10%": "Imprevistos 10%",
        "Bathroom Remodel\n(1 job)": "Remodelación de baño\n(1 trabajo)",
        "Draft": "Borrador",
        "Recommended Quote": "Cotización recomendada",
        "What's not included": "Lo que no está incluido",
        "Permits unless explicitly listed\nHidden water or mold damage":
            "Permisos, salvo que se indiquen\nDaños ocultos por agua o moho",

        // Materials card animation
        "Tankless Water Heater Installation\n(1 job)": "Instalación de calentador sin tanque\n(1 trabajo)",
        "Tankless Water Heater Isolation Valve Kit 3/4\"": "Kit de válvulas para calentador sin tanque 3/4\"",
        "3/4\" Inline Scale Filter": "Filtro antisarro en línea 3/4\"",
        "Fluidmaster 3/4\" Water Heater Connector (18 in.)": "Conector Fluidmaster 3/4\" para calentador (18 in.)",
        "3/4\" Copper Pipe Type L (per ft)": "Tubo de cobre 3/4\" tipo L (por pie)",
        "Add": "Agregar",
        "8 items": "8 artículos",
        "each": "c/u",
        "Edit Line": "Editar línea",

        // Invoice card animation
        "Demolition and haul-away": "Demolición y retiro de escombros",
        "Porcelain floor tile": "Piso de porcelanato",
        "Vanity and countertop": "Mueble de baño y encimera",
        "Shower waterproofing": "Impermeabilización de ducha",
        "Shower wall tile": "Azulejo de pared de ducha",
        "Finish carpentry and paint": "Carpintería de acabado y pintura",
        "June 29, 2025": "29 de junio de 2025",
        "Bill To": "Facturar a",
        "Service Address": "Dirección del servicio",
        "Description": "Descripción",
        "Qty": "Cant.",
        "Amount": "Importe",

        // ZIP code & local activity
        "What's your ZIP code?": "¿Cuál es tu código postal?",
        "We'll use it to find accurate material pricing and local costs near you.":
            "Lo usaremos para encontrar precios de materiales exactos y costos locales cerca de ti.",
        "Join contractors using EasyBid in %@": "Únete a los contratistas que usan EasyBid en %@",
        "Start sending faster, more competitive estimates with local pricing.":
            "Empieza a enviar cotizaciones más rápidas y competitivas con precios locales.",
        "With EasyBid": "Con EasyBid",
        "Time & Money Saved": "Tiempo y dinero ahorrados",
        "Traditional Estimating": "Cotización tradicional",
        "Start": "Inicio",
        "3 Months": "3 meses",
        "6 Months": "6 meses",

        // Questionnaire
        "What best describes": "¿Qué describe mejor",
        "your work?": "tu trabajo?",
        "General Contractor": "Contratista general",
        "Handyman": "Técnico de reparaciones",
        "Specialty Trade": "Oficio especializado",
        "Homeowner / Landlord": "Propietario / Arrendador",
        "What brought you": "¿Qué te trajo",
        "here today?": "aquí hoy?",
        "Create estimates faster": "Crear cotizaciones más rápido",
        "Get accurate pricing": "Obtener precios precisos",
        "Send professional invoices": "Enviar facturas profesionales",
        "Grow my business": "Hacer crecer mi negocio",
        "How many estimates": "¿Cuántas cotizaciones",
        "per month?": "haces al mes?",
        "None yet — just exploring": "Ninguna aún — solo estoy explorando",
        "What slows you": "¿Qué te frena",
        "down the most?": "más?",
        "Estimates take too long": "Las cotizaciones toman demasiado tiempo",
        "Pricing is often off": "Los precios suelen salir mal",
        "Bids look unprofessional": "Mis ofertas no se ven profesionales",
        "Losing jobs to competitors": "Pierdo trabajos ante la competencia",

        // Estimator build
        "Building your custom estimator": "Creando tu cotizador personalizado",
        "Setting up your workspace": "Configurando tu espacio de trabajo",
        "Customizing your estimator": "Personalizando tu cotizador",
        "Ready!": "¡Listo!"
    ]
}
