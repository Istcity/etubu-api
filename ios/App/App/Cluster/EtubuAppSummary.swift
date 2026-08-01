import Foundation

/// Kısa ürün özeti — ayarlar DisclosureGroup (varsayılan kapalı).
enum EtubuAppSummary {
    static let text = """
    Etubu, Tesla aracınızla Bluetooth üzerinden bağlanarak hız, vites, menzil, lastik basıncı ve iklim verilerini araç içi kadran tarzında gösterir.

    SoC (State of Charge), bataryanın yüzde olarak şarj durumudur. Etubu canlı bağlantıda anlık SoC ve menzili gösterir; bağlantı kesilince son bilinen şarj durumu ekranda kalır. Rota planında “hedef varış SoC” ile varışta istenen minimum şarjı seçebilirsiniz; kalan mesafe buna yetmeyecekse rota üzerindeki şarj noktaları önerilir. “Haritada aç” ile en yakın önerilen şarj istasyonuna yol tarifi alabilirsiniz.

    Rota çizerek radar (TR’de EGM + her yerde OSM kamera), şarj istasyonu, hava ve hız limitlerini haritada ve Dynamic Island / Live Activity’de takip edebilirsiniz. Uyarılar müzik üstünde duyulur; EV Sound hızlanma ve yavaşlamaya duyarlıdır.

    Temalar, çentik efektleri ve ses profilleri ayarlardan özelleştirilir. Veriler cihazınızda kalır; Tesla ile resmi bir bağlantı veya iş ortaklığı yoktur.

    Yol ve hız limiti verilerinin bir kısmı © OpenStreetMap contributors (ODbL). Ayrıntı: Ayarlar → Harita özellikleri / Uygulama hakkında ve https://www.openstreetmap.org/copyright
    """
}
