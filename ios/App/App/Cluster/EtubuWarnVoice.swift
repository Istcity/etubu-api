import Foundation
import AVFoundation
import UIKit

/// Native ElevenLabs warn-clip player — does not depend on Cap WebView / TTS.
enum EtubuWarnVoice {
    private static var players: [AVAudioPlayer] = []
    private static var playToken = 0
    private static var lastKey = ""
    private static var lastAt = Date.distantPast

    private static let distM: [Int] = [
        50, 100, 150, 200, 250, 300, 350, 400, 500, 550, 600, 650, 700, 750, 800, 850, 900, 950,
    ]
    private static let distKm: [Int] = [1, 2, 3, 4, 5, 10]
    private static let limits: [Int] = [50, 70, 82, 90, 100, 110, 120, 130, 140]

    /// Speak a HUD/demo phrase using modular clips. Returns true if handled.
    @discardableResult
    static func speak(_ text: String, key: String? = nil, urgent: Bool = false) -> Bool {
        guard EtubuAppLanguage.current.warnTtsEnabled else { return false }
        let ttsOn = UserDefaults.standard.object(forKey: "etubu_radar_tts") as? Bool ?? true
        guard ttsOn else { return false }
        let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return false }

        let debounceKey = key ?? msg
        let now = Date()
        let gap: TimeInterval = urgent ? 12 : 26
        if debounceKey == lastKey, now.timeIntervalSince(lastAt) < gap { return true }
        lastKey = debounceKey
        lastAt = now

        guard let keys = composeKeys(msg), !keys.isEmpty else { return false }
        let urls = keys.compactMap { urlForClip($0) }
        guard urls.count == keys.count else { return false }

        AppDelegate.activateAlertDuckSession()
        playToken &+= 1
        let token = playToken
        players.forEach { $0.stop() }
        players.removeAll()

        let volume = Float(max(0.15, min(1.0, UserDefaults.standard.object(forKey: "etubu.cluster.alertVolume") as? Double ?? 0.9)))
        playSequence(urls: urls, index: 0, token: token, volume: volume)
        return true
    }

    /// Stop in-flight warn clips (demo end / mute path).
    static func stopAll() {
        playToken &+= 1
        players.forEach { $0.stop() }
        players.removeAll()
        lastKey = ""
        lastAt = Date.distantPast
        AppDelegate.deactivateAlertDuckSession()
    }

    private static func playSequence(urls: [URL], index: Int, token: Int, volume: Float) {
        guard token == playToken else { return }
        guard index < urls.count else {
            AppDelegate.deactivateAlertDuckSession()
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: urls[index])
            player.volume = volume
            player.prepareToPlay()
            players = [player]
            // Re-assert duck session in case Music stole the route mid-sequence.
            AppDelegate.activateAlertDuckSession()
            player.play()
            let delay = player.duration + (urgentGap(index: index, total: urls.count))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                playSequence(urls: urls, index: index + 1, token: token, volume: volume)
            }
        } catch {
            // Skip broken clip; continue chain.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                playSequence(urls: urls, index: index + 1, token: token, volume: volume)
            }
        }
    }

    private static func urgentGap(index: Int, total: Int) -> TimeInterval {
        index + 1 < total ? 0.06 : 0
    }

    private static func urlForClip(_ key: String) -> URL? {
        let name = key.hasSuffix(".mp3") ? String(key.dropLast(4)) : key
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "public/assets/audio/warn"),
            Bundle.main.resourceURL?
                .appendingPathComponent("public/assets/audio/warn/\(name).mp3"),
            Bundle.main.bundleURL
                .appendingPathComponent("public/assets/audio/warn/\(name).mp3"),
        ]
        for u in candidates {
            if let u, FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    // MARK: - Phrase → clip keys (mirrors public/js/warn-voice.js)

    static func composeKeys(_ text: String) -> [String]? {
        var s = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "tr_TR"))
        guard !s.isEmpty else { return nil }
        s = s
            .replacingOccurrences(of: #"[.,;:!?"']"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(\d+)\s*km\b"#, with: " $1 kilometre ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(\d+)\s*m\b"#, with: " $1 metre ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        if s == "yavaşla" || s == "yavasla" { return ["yavasla"] }
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
        } else if s.hasPrefix("kontrol") {
            keys.append("kontrol")
            s = stripPrefix(s, patterns: ["kontrol"])
        } else if s.hasPrefix("koridor") {
            keys.append("koridor")
            s = stripPrefix(s, patterns: ["koridor"])
        } else if s.hasPrefix("radar") {
            keys.append("radar")
            s = stripPrefix(s, patterns: ["radar"])
        } else {
            return nil
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
        if let m = s.range(of: #"(\d+(?:[.,]\d+)?)\s*kilometre"#, options: .regularExpression) {
            let num = String(s[m]).replacingOccurrences(of: ",", with: ".")
            if let v = Double(num.split(separator: " ").first.map(String.init) ?? "") {
                return distKmKey(Int(v.rounded()))
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
            "beş": 5, "bes": 5, "altı": 6, "alti": 6, "yedi": 7, "sekiz": 8, "dokuz": 9, "on": 10,
        ]
        for (w, n) in map where s.contains(w) { return n }
        if let r = s.range(of: #"\b(\d+)\b"#, options: .regularExpression) {
            return Int(s[r].filter(\.isNumber))
        }
        return nil
    }
}
