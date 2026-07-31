import Foundation

/// Jul-29 AudioEngine.VOICES catalog for native cluster settings.
struct EtubuSoundVoice: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let labelKey: String
    let group: String
    let groupLabelKey: String

    static let all: [EtubuSoundVoice] = [
        .init(key: "silent-mode", labelKey: "voiceSilentMode", group: "ev", groupLabelKey: "voiceGroupEv"),
        .init(key: "calm-ev", labelKey: "voiceCalm", group: "ev", groupLabelKey: "voiceGroupEv"),
        .init(key: "sport-ev", labelKey: "voiceSport", group: "ev", groupLabelKey: "voiceGroupEv"),
        .init(key: "ion-whisper", labelKey: "voiceIonWhisper", group: "ev", groupLabelKey: "voiceGroupEv"),

        .init(key: "exhaust-v8", labelKey: "voiceExhaustV8", group: "exhaust", groupLabelKey: "voiceGroupExhaust"),
        .init(key: "exhaust-turbo", labelKey: "voiceExhaustTurbo", group: "exhaust", groupLabelKey: "voiceGroupExhaust"),
        .init(key: "exhaust-diesel", labelKey: "voiceExhaustDiesel", group: "exhaust", groupLabelKey: "voiceGroupExhaust"),
        .init(key: "asphalt-roar", labelKey: "voiceAsphaltRoar", group: "exhaust", groupLabelKey: "voiceGroupExhaust"),
        .init(key: "thunder-bass", labelKey: "voiceThunder", group: "exhaust", groupLabelKey: "voiceGroupExhaust"),
        .init(key: "cruiser-vtwin", labelKey: "voiceCruiserVtwin", group: "exhaust", groupLabelKey: "voiceGroupExhaust"),

        .init(key: "formula-scream", labelKey: "voiceFormulaScream", group: "race", groupLabelKey: "voiceGroupRace"),
        .init(key: "sportbike-rr", labelKey: "voiceSportbikeRr", group: "race", groupLabelKey: "voiceGroupRace"),
        .init(key: "boost-launch", labelKey: "voiceBoostLaunch", group: "race", groupLabelKey: "voiceGroupRace"),
        .init(key: "volt-shift", labelKey: "voiceVoltShift", group: "race", groupLabelKey: "voiceGroupRace"),

        .init(key: "jet-hum", labelKey: "voiceJet", group: "fx", groupLabelKey: "voiceGroupFx"),
        .init(key: "pulse-drive", labelKey: "voicePulse", group: "fx", groupLabelKey: "voiceGroupFx"),

        .init(key: "load-throttle", labelKey: "voiceLoadThrottle", group: "sim", groupLabelKey: "voiceGroupSim"),
        .init(key: "shift-cage", labelKey: "voiceShiftCage", group: "sim", groupLabelKey: "voiceGroupSim"),

        .init(key: "piston-sigma", labelKey: "voicePistonSigma", group: "proc", groupLabelKey: "voiceGroupProc"),
        .init(key: "intake-eq", labelKey: "voiceIntakeEq", group: "proc", groupLabelKey: "voiceGroupProc"),

        .init(key: "ramp-forge", labelKey: "voiceRampForge", group: "grain", groupLabelKey: "voiceGroupGrain"),
        .init(key: "grain-stage", labelKey: "voiceGrainStage", group: "grain", groupLabelKey: "voiceGroupGrain"),
    ]

    static var groups: [(group: String, labelKey: String, voices: [EtubuSoundVoice])] {
        let order = ["ev", "exhaust", "race", "fx", "sim", "proc", "grain"]
        return order.compactMap { g in
            let voices = all.filter { $0.group == g }
            guard let first = voices.first else { return nil }
            return (g, first.groupLabelKey, voices)
        }
    }

    var localizedLabel: String { EtubuClusterL10n.t(labelKey) }
    var localizedGroup: String { EtubuClusterL10n.t(groupLabelKey) }
}
