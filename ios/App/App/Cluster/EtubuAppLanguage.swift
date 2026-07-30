import Foundation

/// Web `I18n.SUPPORTED` ile aynı dil listesi.
enum EtubuAppLanguage: String, CaseIterable, Identifiable {
    case tr, en, de, fr, es, ja, ru

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tr: return "Türkçe"
        case .en: return "English"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        case .ja: return "日本語"
        case .ru: return "Русский"
        }
    }

    /// Kritik nokta / rota koruma uyarıları yalnızca Türkçe’de.
    var criticalAlertsEnabled: Bool { self == .tr }

    private static var inMemory: EtubuAppLanguage = {
        let nav = Locale.current.language.languageCode?.identifier.lowercased() ?? "tr"
        return EtubuAppLanguage(rawValue: nav) ?? .tr
    }()

    static var current: EtubuAppLanguage {
        get { inMemory }
        set { inMemory = newValue }
    }
}
