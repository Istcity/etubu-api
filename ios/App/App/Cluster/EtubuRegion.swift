import Foundation
import CoreLocation

/// Türkiye bounding box + son bilinen bölge (rota/dil için).
enum EtubuRegion {
    /// OSM/EGM ayrımı için kaba TR kutusu (Ege–Doğu Anadolu).
    static let minLat = 35.8
    static let maxLat = 42.35
    static let minLng = 25.6
    static let maxLng = 45.0

    private static let storageKey = "etubu.region.inTurkey"
    private static let updatedKey = "etubu.region.updatedAt"

    static func inTurkeyBounds(lat: Double, lng: Double) -> Bool {
        lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng
    }

    /// Kayıtlı GPS bölgesi var mı? Yoksa cold start — pipeline bilinmiyor.
    static var hasKnownRegion: Bool {
        UserDefaults.standard.object(forKey: storageKey) != nil
    }

    /// Son bilinen konum TR içinde mi?
    /// Kayıt yoksa `false` (yurt dışı cold start güvenli: EGM/TR seed / forceTr yok).
    /// İlk GPS fix `updateFrom` ile yazar; TR kullanıcılar ve Maestro İstanbul hızlıca TR yoluna geçer.
    static var lastKnownInTurkey: Bool {
        get {
            if UserDefaults.standard.object(forKey: storageKey) == nil { return false }
            return UserDefaults.standard.bool(forKey: storageKey)
        }
        set {
            let prevObj = UserDefaults.standard.object(forKey: storageKey) as? Bool
            UserDefaults.standard.set(newValue, forKey: storageKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: updatedKey)
            if prevObj != newValue {
                NotificationCenter.default.post(name: .etubuRegionDidChange, object: newValue)
            }
        }
    }

    /// GPS güncellemesi — dil otomatik (manuel override yoksa) + bölge bayrağı.
    static func updateFrom(lat: Double, lng: Double) {
        guard lat.isFinite, lng.isFinite, abs(lat) > 0.01 || abs(lng) > 0.01 else { return }
        let inTR = inTurkeyBounds(lat: lat, lng: lng)
        lastKnownInTurkey = inTR
        EtubuAppLanguage.applyAutoFromRegion(inTurkey: inTR)
    }
}

extension Notification.Name {
    static let etubuRegionDidChange = Notification.Name("etubuRegionDidChange")
}
