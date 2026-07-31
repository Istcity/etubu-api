import SwiftUI

/// İlk açılışta hüküm ve koşullar — metin sonunda “Okudum, anladım” olmadan giriş yok.
enum EtubuLegalAcceptance {
    static let acceptedKey = "etubu.legal.accepted.v1"
    static var isAccepted: Bool { UserDefaults.standard.bool(forKey: acceptedKey) }
    static func accept() { UserDefaults.standard.set(true, forKey: acceptedKey) }
}

struct EtubuLegalAcceptanceView: View {
    var theme: ClusterTheme
    var onAccepted: () -> Void

    @State private var checked = false

    var body: some View {
        GeometryReader { geo in
            let topInset = max(geo.safeAreaInsets.top, Self.windowTopInset(), 12)
            let bottomInset = max(geo.safeAreaInsets.bottom, Self.windowBottomInset(), 12)

            ZStack {
                LinearGradient(
                    colors: theme.canvasGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Başlık — güvenli alanın içinde
                    VStack(spacing: 6) {
                        Text("Hüküm ve Koşullar")
                            .font(EtubuClusterFonts.ui(22, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text("Devam için metni okuyun, sonda kutuyu işaretleyin")
                            .font(EtubuClusterFonts.ui(12, weight: .medium))
                            .foregroundStyle(theme.mutedText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, topInset + 8)
                    .padding(.bottom, 12)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            legalBody

                            Divider().overlay(Color.white.opacity(0.15))
                                .padding(.vertical, 6)

                            // Onay kutusu metnin SONUNDA — kaydırmadan görünmez
                            Button {
                                checked.toggle()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(checked ? theme.accent : .white.opacity(0.9))
                                    Text("Okudum, anladım. Sürüş ve yasal sorumluluğun bana ait olduğunu kabul ediyorum.")
                                        .font(EtubuClusterFonts.ui(14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(checked ? theme.accent.opacity(0.16) : Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(
                                                    checked ? theme.accent.opacity(0.7) : Color.white.opacity(0.2),
                                                    lineWidth: 1.2
                                                )
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)

                            Button {
                                guard checked else { return }
                                EtubuLegalAcceptance.accept()
                                onAccepted()
                            } label: {
                                Text("Kabul et ve devam et")
                                    .font(EtubuClusterFonts.ui(17, weight: .bold))
                                    .foregroundStyle(checked ? .black : .white.opacity(0.45))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(
                                        (checked ? theme.accent : Color.white.opacity(0.12)),
                                        in: Capsule()
                                    )
                            }
                            .disabled(!checked)
                            .padding(.top, 8)
                            .padding(.bottom, 20)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, bottomInset + 8)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, max(8, bottomInset - 4))
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
    }

    private var legalBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            section(
                "1. Amaç ve kapsam",
                "ETUBU Cluster; Tesla aracıyla Bluetooth üzerinden alınan telemetriyi, rota ve yol uyarısı bilgilerini araç içi kadran tarzında gösteren yardımcı bir uygulamadır. Uygulama sürüşü yönetmez, araca komut göndermez ve resmi bir navigasyon veya güvenlik sistemi değildir."
            )
            section(
                "2. Veri kaynakları",
                "Uygulamada gösterilen radar, hız koridoru, kontrol noktası, yol ve hız limiti bilgileri kamuya açık, resmi veya açık veri kaynaklarından derlenir. Bunlar arasında Emniyet Genel Müdürlüğü (EGM) yayınları, OpenStreetMap (ODbL lisanslı açık harita verisi), hava durumu servisleri ve benzeri kaynaklar yer alabilir. Kaynaklar değişebilir, gecikebilir, eksik veya hatalı olabilir."
            )
            section(
                "2a. OpenStreetMap atıfı ve lisans",
                """
                © OpenStreetMap contributors. Yol, hız limiti ve ilgili coğrafi verilerin bir kısmı OpenStreetMap’ten alınır ve Open Database License (ODbL) ile sunulur.

                Lisans: https://www.openstreetmap.org/copyright
                ODbL: https://opendatacommons.org/licenses/odbl/

                OSM verisini kopyalayan, dağıtan veya uyarlayan herkes ODbL koşullarına (atıf + share-alike) uymakla yükümlüdür.
                """
            )
            section(
                "3. Sorumluluk beyanı",
                "ETUBU, Tesla Inc. veya bağlı kuruluşlarıyla resmi bir ortaklık, onay veya bağlantı içinde değildir. “Tesla” yalnızca uyumluluk bağlamında anılır. Uygulama “olduğu gibi” sunulur; doğruluk, kesintisizlik veya belirli bir amaca uygunluk konusunda açık veya zımni garanti verilmez."
            )
            section(
                "4. Kullanıcının yasal sorumluluğu",
                "Trafik kurallarına uymak, hız limitlerine riayet etmek, dikkat dağıtıcı cihaz kullanımını önlemek ve güvenli sürüş tamamen kullanıcının / sürücünün yasal sorumluluğundadır. Uygulamadaki uyarılar, Türkiye hız tabloları, harita, Dynamic Island / Live Activity bildirimleri ve sesli uyarılar yalnızca yardımcı bilgidir; trafik levhaları, yol durumu ve sürücü dikkatinin yerini tutmaz."
            )
            section(
                "5. Yanlış / eksik bilgi",
                "Hız limiti, radar konumu, koridor, şarj veya hava uyarısı yanlış, eksik veya güncel olmayabilir. Buna dayanarak alınan kararlardan, cezai veya idari yaptırımlardan, kazalardan ve maddi/manevi zararlardan uygulama geliştiricisi sorumlu tutulamaz."
            )
            section(
                "6. Gizlilik",
                "VIN ve bağlantı anahtarları cihazınızda tutulur. Konum, rota ve telemetri işlevleri için gerekli veriler işlenebilir. Verilerinizi üçüncü taraflara satmayız. Apple / App Store ödemeleri Apple’ın kurallarına tabidir."
            )
            section(
                "7. Kabul",
                "Aşağıdaki “Okudum, anladım” kutusunu işaretleyerek bu hükümleri okuduğunuzu, anladığınızı ve sürüş ile yasal sorumluluğun size ait olduğunu kabul etmiş olursunuz."
            )

            Text("Son güncelleme: 31 Temmuz 2026")
                .font(EtubuClusterFonts.ui(11, weight: .medium))
                .foregroundStyle(theme.mutedText)
                .padding(.top, 4)

            Link(destination: EtubuOsmAttribution.copyrightURL) {
                Text(EtubuOsmAttribution.credit + " · ODbL")
                    .font(EtubuClusterFonts.ui(11, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(EtubuClusterFonts.ui(14, weight: .bold))
                .foregroundStyle(theme.accent)
            Text(body)
                .font(EtubuClusterFonts.ui(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func windowTopInset() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        return window?.safeAreaInsets.top ?? 47
    }

    private static func windowBottomInset() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        return window?.safeAreaInsets.bottom ?? 20
    }
}
