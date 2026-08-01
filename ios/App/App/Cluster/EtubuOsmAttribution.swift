import SwiftUI

/// OpenStreetMap ODbL atıf metinleri — telif / lisans uyumu.
enum EtubuOsmAttribution {
    /// Harita köşesi / kompakt UI
    static let short = "© OpenStreetMap"
    /// Görünür kısa satır
    static let credit = "© OpenStreetMap contributors"
    /// ODbL açıklaması (TR)
    static let licenseNoteTR =
        "Harita ve yol verilerinin bir kısmı OpenStreetMap katkıda bulunanlarına aittir ve Open Database License (ODbL) kapsamında sunulur."
    static let licenseNoteEN =
        "Some map and road data © OpenStreetMap contributors, available under the Open Database License (ODbL)."
    /// Tam bilgilendirme (ayarlar / hakkında)
    static let fullTR = """
    OpenStreetMap verisi, OpenStreetMap Foundation tarafından Open Database License (ODbL) ile sunulur.

    • Atıf: © OpenStreetMap contributors
    • Lisans: https://www.openstreetmap.org/copyright
    • ODbL metni: https://opendatacommons.org/licenses/odbl/

    Uygulamada hız limitleri, yol sınıfları ve benzeri bilgiler Overpass / OSM verisinden alınabilir. Veriyi uyarlarsanız ODbL paylaşı alike koşullarına uymanız gerekir. OSM, Tesla veya Etubu’nun resmi ortağı değildir.
    """

    static let copyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!
    static let odblURL = URL(string: "https://opendatacommons.org/licenses/odbl/")!
}

/// Harita köşesinde kompakt atıf (tıklanınca copyright sayfası).
struct EtubuOsmAttributionChip: View {
    var compact: Bool = true
    var theme: ClusterTheme = .tesla

    var body: some View {
        Link(destination: EtubuOsmAttribution.copyrightURL) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: compact ? 8 : 9, weight: .bold))
                Text(compact ? EtubuOsmAttribution.short : EtubuOsmAttribution.credit)
                    .font(.system(size: compact ? 8 : 9, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 3 : 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("OpenStreetMap attribution")
        .accessibilityHint("Opens OpenStreetMap copyright page")
    }
}

/// Ayarlar / hakkında için genişletilmiş OSM lisans satırı.
struct EtubuOsmAttributionBlock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenStreetMap")
                .font(.subheadline.weight(.bold))
            Text(EtubuOsmAttribution.licenseNoteTR)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(EtubuOsmAttribution.fullTR)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("openstreetmap.org/copyright", destination: EtubuOsmAttribution.copyrightURL)
                .font(.caption.weight(.semibold))
            Link("ODbL lisans metni", destination: EtubuOsmAttribution.odblURL)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
