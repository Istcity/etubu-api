import Foundation
import AVFoundation
import UIKit
import AudioToolbox

/// Native warn clips + beeps — Cap WebView bağımsız (SwiftUI overlay altında da çalışır).
/// Klipler Türkçe; UI dili ne olursa olsun çalınır (Tesla tarzı duck over BT).
/// Native warn tones — Cap WebView bağımsız. TTS yok; her olay türünün kendi bip’i var.
enum EtubuWarnVoice {
    private static var players: [AVAudioPlayer] = []
    private static var playerBoxes: [PlayerBox] = []
    private static var playToken = 0
    private static var lastKey = ""
    private static var lastAt = Date.distantPast
    private static var toneEngines: [AVAudioEngine] = []

    private static let speechSynth = AVSpeechSynthesizer()

    @discardableResult
    static func speak(
        _ text: String,
        key: String? = nil,
        urgent: Bool = false,
        completion: (() -> Void)? = nil
    ) -> Bool {
        let voiceOn = UserDefaults.standard.object(forKey: "etubu_radar_voice") as? Bool ?? true
        guard voiceOn else {
            completion?()
            return false
        }
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else {
            completion?()
            return false
        }
        let now = Date()
        let k = key ?? phrase
        if k == lastKey && now.timeIntervalSince(lastAt) < (urgent ? 3.0 : 6.0) {
            completion?()
            return false
        }
        lastKey = k
        lastAt = now

        AppDelegate.activateAlertDuckSession()
        let utterance = AVSpeechUtterance(string: phrase)
        let lang = EtubuAppLanguage.current.rawValue
        let voiceLang = lang.hasPrefix("tr") ? "tr-TR" : (lang.hasPrefix("de") ? "de-DE" : (lang.hasPrefix("fr") ? "fr-FR" : (lang.hasPrefix("es") ? "es-ES" : "en-US")))
        utterance.rate = urgent ? 0.53 : 0.49
        let vol = max(0.2, min(1.0, UserDefaults.standard.object(forKey: "etubu.cluster.alertVolume") as? Double ?? 0.95))
        utterance.volume = Float(max(0.75, vol))
        speechSynth.speak(utterance)
        completion?()
        return true
    }

    /// Native beeps (no Cap AudioContext) — works over BT A2DP with duck session.
    static func playBeeps(count: Int, urgent: Bool) {
        playKindCue(kind: urgent ? "corridor" : "radar", urgent: urgent, countOverride: count)
    }

    /// Distinct pattern per hazard kind (Waze/Coyote-style: tone identity, not speech).
    static func playKindCue(kind: String, urgent: Bool, countOverride: Int? = nil) {
        let beepsOn = UserDefaults.standard.object(forKey: "etubu_radar_beeps") as? Bool ?? true
        guard beepsOn else { return }
        AppDelegate.activateAlertDuckSession()
        let vol = max(0.25, min(1.0, UserDefaults.standard.object(forKey: "etubu.cluster.alertVolume") as? Double ?? 0.95))
        let tones = countOverride != nil
            ? Array(repeating: (urgent ? 1180.0 : 880.0, urgent ? 0.09 : 0.11), count: max(1, countOverride!))
            : Self.tonePattern(kind: kind, urgent: urgent)
        playToken &+= 1
        let token = playToken
        var delay = 0.08
        for (i, spec) in tones.enumerated() {
            let d = delay
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                guard token == playToken else { return }
                AppDelegate.activateAlertDuckSession()
                playTone(frequency: spec.0, duration: spec.1, volume: Float(vol * (urgent ? 1.0 : 0.92)))
            }
            delay += spec.1 + (urgent ? 0.09 : 0.12)
            if i == tones.count - 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.25) {
                    guard token == playToken else { return }
                    AppDelegate.deactivateAlertDuckSession()
                }
            }
        }
        if tones.isEmpty {
            AppDelegate.deactivateAlertDuckSession()
        }
    }

    private static func tonePattern(kind: String, urgent: Bool) -> [(Double, TimeInterval)] {
        if urgent, kind == "corridor" {
            return [(1320, 0.08), (1320, 0.08), (1480, 0.14)]
        }
        switch kind {
        case "radar":
            return [(1180, 0.08), (1180, 0.10)]
        case "corridor":
            return [(660, 0.16), (820, 0.12)]
        case "railway":
            return [(520, 0.12), (390, 0.18)]
        case "tunnel", "underpass", "overpass":
            return [(420, 0.22)]
        case "winding", "climb":
            return [(780, 0.10), (640, 0.14)]
        case "road_condition", "animal":
            return [(700, 0.12), (560, 0.12)]
        case "weather":
            return [(500, 0.18)]
        case "charge":
            return [(900, 0.14)]
        case "traffic_light":
            return [(1040, 0.07), (880, 0.07)]
        case "stop", "give_way":
            return [(980, 0.10)]
        case "crossing", "bump":
            return [(940, 0.06)]
        case "control":
            return [(1400, 0.07), (1400, 0.07), (1400, 0.10)]
        default:
            return [(880, 0.11)]
        }
    }

    static func stopAll() {
        playToken &+= 1
        players.forEach {
            $0.delegate = nil
            $0.stop()
        }
        players.removeAll()
        playerBoxes.removeAll()
        toneEngines.forEach { $0.stop() }
        toneEngines.removeAll()
        lastKey = ""
        lastAt = Date.distantPast
        AppDelegate.deactivateAlertDuckSession()
    }

    // MARK: - Playback

    private final class PlayerBox: NSObject, AVAudioPlayerDelegate {
        let player: AVAudioPlayer
        init(player: AVAudioPlayer) {
            self.player = player
            super.init()
            player.delegate = self
        }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            player.delegate = nil
            EtubuWarnVoice.dropBox(self)
        }
        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            player.delegate = nil
            EtubuWarnVoice.dropBox(self)
        }
    }

    private static func dropBox(_ box: PlayerBox) {
        box.player.delegate = nil
        players.removeAll { $0 === box.player }
        playerBoxes.removeAll { $0 === box }
    }

    private static func playTone(frequency: Double, duration: TimeInterval, volume: Float) {
        let sampleRate: Double = 24_000
        let frameCount = Int(duration * sampleRate)
        guard frameCount > 16, let wav = pcmWav(frequency: frequency, frames: frameCount, sampleRate: sampleRate) else {
            AudioServicesPlaySystemSound(1057)
            return
        }
        do {
            let player = try AVAudioPlayer(data: wav)
            player.volume = min(1.0, max(0.1, volume))
            player.prepareToPlay()
            let box = PlayerBox(player: player)
            playerBoxes.append(box)
            players.append(player)
            player.play()
        } catch {
            AudioServicesPlaySystemSound(1057)
        }
    }

    /// Generates rich multi-harmonic acoustic tone with attack/decay envelope and soft saturation.
    /// Cuts through road noise and ducked media over Tesla Bluetooth.
    private static func pcmWav(frequency: Double, frames: Int, sampleRate: Double) -> Data? {
        var data = Data()
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 4))
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 2))
        }
        let dataBytes = UInt32(frames * 2)
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        appendU32(36 + dataBytes)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x66, 0x6D, 0x74, 0x20]) // WAVEfmt
        appendU32(16)
        appendU16(1)
        appendU16(1)
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate) * 2)
        appendU16(2)
        appendU16(16)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        appendU32(dataBytes)
        let twoPi = 2.0 * Double.pi
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let f1 = sin(twoPi * frequency * t)
            let f2 = 0.36 * sin(twoPi * frequency * 2.0 * t)
            let f3 = 0.16 * sin(twoPi * frequency * 3.0 * t)
            var sample = f1 + f2 + f3
            let attack = min(1.0, Double(i) / (sampleRate * 0.008))
            let release = min(1.0, Double(frames - i) / (sampleRate * 0.015))
            sample *= (attack * release)
            // Soft saturation / acoustic compression for punch & clarity over car audio
            sample = tanh(sample * 1.35)
            var s = Int16(max(-32767, min(32767, sample * 32760.0)))
            var le = s.littleEndian
            data.append(Data(bytes: &le, count: 2))
        }
        return data
    }

    private static func urlForClip(_ key: String) -> URL? {
        let name = key.hasSuffix(".mp3") ? String(key.dropLast(4)) : key
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "public/assets/audio/warn"),
            Bundle.main.resourceURL?
                .appendingPathComponent("public/assets/audio/warn/\(name).mp3"),
            Bundle.main.bundleURL
                .appendingPathComponent("public/assets/audio/warn/\(name).mp3"),
            Bundle.main.bundleURL
                .appendingPathComponent("www/assets/audio/warn/\(name).mp3"),
        ]
        for u in candidates {
            if let u, FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    // MARK: - Phrase → clip keys (unused after TTS removal; kept for clip catalog)

    private static let distM: [Int] = [
        50, 100, 150, 200, 250, 300, 350, 400, 500, 550, 600, 650, 700, 750, 800, 850, 900, 950,
    ]
    private static let distKm: [Int] = [1, 2, 3, 4, 5, 10]
    private static let limits: [Int] = [50, 70, 82, 90, 100, 110, 120, 130, 140]

    static func composeKeys(_ text: String) -> [String]? {
        var s = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "tr_TR"))
        guard !s.isEmpty else { return nil }

        // Normalize UI distance labels before punctuation strip.
        // After "1.2 km" → "1.2 kilometre", do not strip the decimal point.
        s = s
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: #"\b(\d+(?:\.\d+)?)\s*km\b"#, with: " $1 kilometre ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(\d+)\s*m\b"#, with: " $1 metre ", options: .regularExpression)
            .replacingOccurrences(of: #"[;:!?"'·]"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        if s == "yavaşla" || s == "yavasla" || s.hasPrefix("yavaşla") || s.hasPrefix("yavasla") {
            return ["yavasla"]
        }
        if s == "koridor bitti" { return ["koridor_bitti"] }

        if s.hasPrefix("rota hazır") || s.hasPrefix("rota hazir") {
            var keys = ["rota_hazir"]
            if let n = firstWordNumber(in: s), let w = wordNumKey(n) { keys.append(w) }
            keys.append("guzergahta_kritik_nokta_var")
            return keys
        }

        var keys: [String] = []
        if s.hasPrefix("radar yakın") || s.hasPrefix("radar yakin") {
            keys.append("radar_yakin")
            s = stripPrefix(s, patterns: ["radar yakın", "radar yakin"])
        } else if s.hasPrefix("koridor giriş") || s.hasPrefix("koridor giris") {
            keys.append("koridor_giris")
            s = stripPrefix(s, patterns: ["koridor giriş", "koridor giris"])
        } else if s.hasPrefix("hız koridoru") || s.hasPrefix("hiz koridoru") {
            keys.append("hiz_koridoru")
            s = stripPrefix(s, patterns: ["hız koridoru", "hiz koridoru"])
        } else if s.hasPrefix("şarj istasyonu") || s.hasPrefix("sarj istasyonu") {
            keys.append("sarj_istasyonu")
            s = stripPrefix(s, patterns: ["şarj istasyonu", "sarj istasyonu"])
        } else if s.hasPrefix("şiddetli hava") || s.hasPrefix("siddetli hava") {
            keys.append("siddetli_hava")
            s = stripPrefix(s, patterns: ["şiddetli hava", "siddetli hava"])
        } else if s.hasPrefix("hava olayı") || s.hasPrefix("hava olayi") {
            keys.append("hava_olayi")
            s = stripPrefix(s, patterns: ["hava olayı", "hava olayi"])
        } else if s.hasPrefix("lastik") || s.hasPrefix("tpms") {
            keys.append("kontrol")
            s = stripPrefix(s, patterns: ["lastik basıncı düşük", "lastik basinci dusuk", "lastik", "tpms"])
        } else if s.hasPrefix("batarya") || s.hasPrefix("battery") {
            keys.append("kontrol")
            s = stripPrefix(s, patterns: ["batarya kritik", "battery critical", "batarya"])
        } else if s.hasPrefix("kontrol") || s.hasPrefix("demiryolu") || s.hasPrefix("trafik")
                    || s.hasPrefix("dur ") || s == "dur" || s.hasPrefix("yol ver")
                    || s.hasPrefix("yaya") || s.hasPrefix("tümsek") || s.hasPrefix("tumsek") {
            keys.append("kontrol")
            for p in ["kontrol", "demiryolu geçidi", "demiryolu gecidi", "trafik lambası", "trafik lambasi",
                      "dur", "yol ver", "yaya geçidi", "yaya gecidi", "tümsek", "tumsek"] {
                if s.hasPrefix(p) {
                    s = String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        } else if s.hasPrefix("koridor") {
            keys.append("koridor")
            s = stripPrefix(s, patterns: ["koridor"])
        } else if s.hasPrefix("radar") {
            keys.append("radar")
            s = stripPrefix(s, patterns: ["radar"])
        } else {
            // Unknown phrase — still try distance-only after a generic radar chime.
            keys.append("radar")
        }

        s = s.trimmingCharacters(in: .whitespaces)
        var limit: Int?
        if let m = s.range(of: #"h[iı]z\s+s[iı]n[iı]r[iı]?\s*(\d{2,3})"#, options: .regularExpression) {
            let chunk = String(s[m])
            if let num = chunk.split(whereSeparator: { !$0.isNumber }).last.flatMap({ Int($0) }) {
                limit = num
            }
            s.removeSubrange(m)
            s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }

        if let dist = distKey(from: s) {
            keys.append(dist)
        }
        if let limit {
            keys.append("hiz_siniri")
            if let lk = limitKey(limit) { keys.append(lk) }
        }
        return keys.isEmpty ? nil : keys
    }

    private static func stripPrefix(_ s: String, patterns: [String]) -> String {
        for p in patterns where s.hasPrefix(p) {
            return String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    private static func distKey(from s: String) -> String? {
        if let m = s.range(of: #"(\d+(?:\.\d+)?)\s*kilometre"#, options: .regularExpression) {
            let chunk = String(s[m])
            let num = chunk.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
            if let v = Double(num) {
                return distKmKey(max(1, Int(v.rounded())))
            }
        }
        if let m = s.range(of: #"(\d+)\s*metre"#, options: .regularExpression) {
            let digits = String(s[m]).filter(\.isNumber)
            if let v = Int(digits) { return nearestDistMeters(v) }
        }
        let wordKm: [(String, Int)] = [
            ("bir kilometre", 1), ("iki kilometre", 2), ("üç kilometre", 3), ("uc kilometre", 3),
            ("dört kilometre", 4), ("dort kilometre", 4), ("beş kilometre", 5), ("bes kilometre", 5),
            ("on kilometre", 10),
        ]
        for (w, n) in wordKm where s.contains(w) { return distKmKey(n) }

        if let meters = parseTurkishMeters(s) { return nearestDistMeters(meters) }
        return nil
    }

    private static func parseTurkishMeters(_ s: String) -> Int? {
        var t = s
            .replacingOccurrences(of: #"h[iı]z\s+s[iı]n[iı]r[iı]?\s*\d*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "metre", with: "")
            .trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if t == "yüz" || t == "yuz" { return 100 }
        if t == "elli" { return 50 }

        let ones: [String: Int] = [
            "bir": 1, "iki": 2, "üç": 3, "uc": 3, "dört": 4, "dort": 4,
            "beş": 5, "bes": 5, "altı": 6, "alti": 6, "yedi": 7, "sekiz": 8, "dokuz": 9,
        ]
        let tens: [String: Int] = [
            "on": 10, "yirmi": 20, "otuz": 30, "kırk": 40, "kirk": 40, "elli": 50,
            "altmış": 60, "altmis": 60, "yetmiş": 70, "yetmis": 70, "seksen": 80, "doksan": 90,
        ]

        var total = 0
        if let r = t.range(of: #"^(iki|üç|uc|dört|dort|beş|bes|altı|alti|yedi|sekiz|dokuz)\s+(yüz|yuz)\b"#, options: .regularExpression) {
            let head = String(t[r]).split(separator: " ").first.map(String.init) ?? ""
            total += (ones[head] ?? 0) * 100
            t = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else if t.hasPrefix("yüz") || t.hasPrefix("yuz") || t.hasPrefix("bir yüz") || t.hasPrefix("bir yuz") {
            total += 100
            if let r = t.range(of: #"^(bir\s+)?(yüz|yuz)\b"#, options: .regularExpression) {
                t = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        for p in t.split(separator: " ").map(String.init) {
            if let v = tens[p] { total += v }
            else if let v = ones[p] { total += v }
        }
        return total > 0 ? total : nil
    }

    private static func nearestDistMeters(_ m: Int) -> String {
        if m >= 1000 {
            let km = m >= 2000 ? Int((Double(m) / 1000.0).rounded()) : 1
            return distKmKey(km)
        }
        let best = distM.min(by: { abs($0 - m) < abs($1 - m) }) ?? 50
        return "d_\(best)m"
    }

    private static func distKmKey(_ km: Int) -> String {
        let best = distKm.min(by: { abs($0 - km) < abs($1 - km) }) ?? 1
        return "d_\(best)km"
    }

    private static func limitKey(_ n: Int) -> String? {
        let best = limits.min(by: { abs($0 - n) < abs($1 - n) }) ?? n
        return "n\(best)"
    }

    private static func wordNumKey(_ n: Int) -> String? {
        switch n {
        case 1: return "w_bir"
        case 2: return "w_iki"
        case 3: return "w_uc"
        case 4: return "w_dort"
        case 5: return "w_bes"
        case 6: return "w_alti"
        case 7: return "w_yedi"
        case 8: return "w_sekiz"
        case 9: return "w_dokuz"
        default: return nil
        }
    }

    private static func firstWordNumber(in s: String) -> Int? {
        let map: [String: Int] = [
            "bir": 1, "iki": 2, "üç": 3, "uc": 3, "dört": 4, "dort": 4,
            "beş": 5, "bes": 5, "altı": 6, "alti": 6, "yedi": 7, "sekiz": 8, "dokuz": 9,
        ]
        for (w, n) in map where s.contains(w) { return n }
        return nil
    }
}
