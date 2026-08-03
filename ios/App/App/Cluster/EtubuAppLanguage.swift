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

    /// Rota / radar / şarj / hava — dil bağımsız (OSM global; EGM radar yalnızca TR).
    var criticalAlertsEnabled: Bool { true }

    /// Uyarı TTS klipleri yalnızca Türkçe UI’da.
    var warnTtsEnabled: Bool { self == .tr }

    private static let storageKey = "etubu.app.language"
    private static let manualKey = "etubu.app.language.manual"

    /// Kullanıcı ayarlardan dil seçtiyse GPS otomatik dil değiştirmesin.
    static var isManualOverride: Bool {
        get { UserDefaults.standard.bool(forKey: manualKey) }
        set { UserDefaults.standard.set(newValue, forKey: manualKey) }
    }

    private static var inMemory: EtubuAppLanguage = {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-etubuForceLangTr") || args.contains("etubuForceLangTr")
            || UserDefaults.standard.bool(forKey: "etubuForceLangTr") {
            return .tr
        }
        if args.contains("-etubuForceLangEn") || args.contains("etubuForceLangEn")
            || UserDefaults.standard.bool(forKey: "etubuForceLangEn") {
            UserDefaults.standard.set(true, forKey: manualKey)
            return .en
        }
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let lang = EtubuAppLanguage(rawValue: raw) {
            return lang
        }
        // İlk açılış: kayıt yok — bölge biliniyorsa ona göre, yoksa cihaz dili / TR
        if EtubuRegion.hasKnownRegion {
            return EtubuRegion.lastKnownInTurkey ? .tr : .en
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

    /// Ayarlar picker — manuel kilit.
    static func setManual(_ lang: EtubuAppLanguage) {
        isManualOverride = true
        current = lang
    }

    /// GPS bölgesine göre otomatik TR/EN (manuel override yoksa).
    static func applyAutoFromRegion(inTurkey: Bool) {
        if isManualOverride { return }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-etubuForceLangTr") || args.contains("etubuForceLangTr")
            || UserDefaults.standard.bool(forKey: "etubuForceLangTr") {
            return
        }
        let want: EtubuAppLanguage = inTurkey ? .tr : .en
        guard current != want else { return }
        current = want
        DispatchQueue.main.async {
            EtubuClusterAudioBridge.setLanguage(want.rawValue)
        }
    }
}

extension Notification.Name {
    static let etubuLanguageDidChange = Notification.Name("etubuLanguageDidChange")
}
