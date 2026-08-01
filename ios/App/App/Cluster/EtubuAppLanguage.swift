import Foundation

/// Web `I18n.SUPPORTED` ile aynı dil listesi — UserDefaults’ta kalıcı.
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

    /// Rota / radar / şarj / hava uyarıları — dil bağımsız (OSM/OCM/Open-Meteo global; EGM radar TR).
    var criticalAlertsEnabled: Bool { true }

    private static let storageKey = "etubu.app.language"

    private static var inMemory: EtubuAppLanguage = {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let lang = EtubuAppLanguage(rawValue: raw) {
            return lang
        }
        let nav = Locale.current.language.languageCode?.identifier.lowercased() ?? "tr"
        return EtubuAppLanguage(rawValue: nav) ?? .tr
    }()

    static var current: EtubuAppLanguage {
        get { inMemory }
        set {
            inMemory = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: .etubuLanguageDidChange, object: newValue.rawValue)
        }
    }
}

extension Notification.Name {
    static let etubuLanguageDidChange = Notification.Name("etubuLanguageDidChange")
}
