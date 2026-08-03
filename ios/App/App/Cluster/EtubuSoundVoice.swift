import Foundation

/// Tema başına bir sürüş sesi (RevHeadz prensibi: fiziksel yük; katalog şişirme yok).
struct EtubuSoundVoice: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let labelKey: String
    let group: String
    let groupLabelKey: String

    /// Sessiz + her `ClusterTheme` için bir paket.
    static let all: [EtubuSoundVoice] = {
        var list: [EtubuSoundVoice] = [
            .init(key: "silent-mode", labelKey: "voiceSilentMode", group: "theme", groupLabelKey: "voiceGroupTheme"),
        ]
        for theme in ClusterTheme.allCases {
            list.append(.init(
                key: theme.driveVoiceKey,
                labelKey: "themeName.\(theme.rawValue)",
                group: "theme",
                groupLabelKey: "voiceGroupTheme"
            ))
        }
        return list
    }()

    static var groups: [(group: String, labelKey: String, voices: [EtubuSoundVoice])] {
        [(group: "theme", labelKey: "voiceGroupTheme", voices: all)]
    }

    /// Tema değişince kullanılacak ses anahtarı (sessiz değilse).
    static func voiceKey(for theme: ClusterTheme, soundOn: Bool) -> String {
        soundOn ? theme.driveVoiceKey : "silent-mode"
    }

    var localizedLabel: String {
        if key == "silent-mode" { return EtubuClusterL10n.t(labelKey) }
        if let theme = ClusterTheme(rawValue: key) {
            // Honesty: theme label + shared timbre pack (not 14 unique WAV banks).
            let pack = EtubuClusterL10n.t("pack.\(theme.driveBasePack)")
            return "\(theme.title) · \(pack)"
        }
        return EtubuClusterL10n.t(labelKey)
    }

    var localizedGroup: String { EtubuClusterL10n.t(groupLabelKey) }
}
