# Etubu — canlı veri, rota ve yol uyarı kuralları

Bu belge uygulamanın **zorunlu** çalışma düzenidir. Kod değişiklikleri bu kurallara uymalıdır.

---

## 1. Canlı telemetri (Tesla BLE)

| Kural | Açıklama |
|-------|----------|
| **Sürekli akış** | Drive poll (`fetchDrive`) hata olsa bile **döngüden çıkmaz**; soft reconnect + backoff ile devam eder. |
| **Öncelik** | Hareket halindeyken Infotainment kuyruğunda **hız/vites/güç** > SoC/iklim/TPMS > media. |
| **Çift döngü** | Drive ~10–12 Hz (parkta yavaş); extras parkta ~1 Hz, hareketliyken seyrek/kısa timeout. |
| **VCSEC** | Kilit/presence ~1 Hz; drive’ı öldürmez. |
| **Sağlık** | Oturum sağlığı `lastDriveValueAt` ile ölçülür (boş paket `lastDriveAt` şişirmez). |
| **Watchdog** | Drive değeri ~4.5 sn bayatsa poll yeniden başlar. |
| **Nil hız** | Geçerli mph yoksa önceki km/h korunur; park (P/N ve &lt;3 km/h) → 0. |
| **Yedek canlı** | (1) Drive poll (2) extras her 12 sn “yeni bağlanmış” bootstrap (3) GPS HUD Tesla donunca (4) boş paket reconnect (5) 22 sn donunca tam re-handshake. |
| **Otomatik bağlan** | İlk başarılı eşleşmeden sonra VIN + Keychain varken kopunca backoff (en fazla 12 sn) ile **süresiz** yeniden bağlanır. |
| **Konum** | Tesla `LocationState` extras ~1 Hz; telefon GPS yalnızca Tesla konumu ~2.8 sn bayatsa yazar. |

---

## 2. Hız kadranı

| Kural | Açıklama |
|-------|----------|
| **Hedef** | `telemetry.kmh` (veya demo). |
| **P/N** | Yalnız &lt;3 km/h iken kadran 0; hareketliyken vites D gibi gösterilir. |
| **Yumuşatma** | Yakında ±1 km/h @ ~20 Hz; büyük sıçramada orantılı catch-up (takılma yok). |
| **Animasyon** | Her km/h adımında ring spring animasyonu yok. |

---

## 3. Yol uyarıları — ne zaman açık?

| Durum | Yol uyarıları (radar, koridor, OSM kritik, ses) |
|-------|--------------------------------------------------|
| **Uygulama rotası çizili** (`routeActive`) | **Açık** |
| **Araçta navigasyon var** (Tesla hedef / kalan mesafe) | **Açık** (uygulama rotası olmasa da) |
| **Demo drive** | **Açık** |
| **İkisi de yok** | **Kapalı** — yalnız aşırı güvenlik (TPMS / kritik SoC) |

Tek kapı: `EtubuVehicleTelemetry.hasActiveNavigation`.

Araç navigasyonu bitince sticky `navDestination` / `navRemainKm` **temizlenir** (aksi halde uyarılar kapanmaz).

**Premium:** Tam radar/koridor/OSM stack premium. Ücretsiz katmanda OSM hız levhası.

---

## 4. Kritik nokta kaynak önceliği

| Öncelik | Kaynak |
|---------|--------|
| **1 — OSM** | Overpass: radar, koridor, ışık, yaya, tünel, viraj, tırmanış, yol şartı, şarj |
| **2 — TR koridor cache** | Dil TR: gömülü + haftalık OSM (EGM yok) |
| **3 — Hava** | Open-Meteo (WMO) + MGM uyarı (TR, varsa) |
| **Karma çekim** | Rota çizilince koridor cache hemen; OSM + şarj + hava paralel. |
| **Canlı karma** | Navigasyon açıkken LiveRadar + OsmHazards + Weather **paralel**. |

Kurallar (`EtubuHazardMerge` + `docs/HAZARD_SOURCES.md`):

- OSM **led** (EGM kullanılmaz).
- Rota polyline varsa yol hazard’ları ~**160 m**; hava 8 km; şarj 450 m.
- Koridor ortalaması yalnız **gerçek koridor girişinde**.

---

## 5. Ev / İş / kısa adlı adresler

| Kural | Açıklama |
|-------|----------|
| **Pin-first** | Tesla charge state’ten gelen home/work lat-lng UserDefaults’ta tutulur. |
| **Routing** | `ev` / `iş` / `home` / `work` / … → **kayıtlı koordinat**; şehir araması **yok**. |
| **TR fold** | `"İş"` → `aliasFold` / `foldQuery` (düz `.lowercased()` kullanılmaz). |
| **Isparta yasağı** | `iş` → `is` şehir prefix skoruna **düşmez**; alias + pinsiz → sonuç yok / plan yok. |
| **Araç nav** | Tesla “İş/Ev” → pin veya `activeRoute` lat/lng ile plan; Nominatim ile rastgele şehir **yasak**. |
| **Arka plan** | Pin her charge/extras turunda yenilenir; rota her zaman lat/lng ile çizilir. |

---

## 6. Rota çizimi

1. Kullanıcı veya araç hedefi resolve (pin → OSM Photon/Nominatim dünya; TR index yedek; alias istisnaları §5).
2. OSRM / native polyline.
3. Polyline üzerinde TR koridor cache hemen; OSM (radar, tünel, hemzemin, viraj, tırmanış) + şarj + hava paralel karma merge.
4. `routeActive` + uyarı poll; 600 m sapmada replan.
5. Koridor ortalaması yalnız **gerçek koridor girişinde**.
6. Adres araması dünya OSM (Photon); hava olayları Open-Meteo, OSM özetinden ayrı.

---

## 7. Uyarı sesi

TTS yok. Yalnız native bip; her olay türünün kendi tonu vardır.

| Kural | Açıklama |
|-------|----------|
| **Bir kez** | Aynı OSM/radar noktası rota oturumunda **bir** ses verir (geri sayım yok). |
| **Tekrar** | Koridor ortalaması sınırı aşıyorsa YAVAŞLA ~14 sn’de bir; TPMS/kritik SoC aynı. |
| **Çakışma** | Koridor aşımı varken yakındaki radar çalmaz. Farklı olaylar arasında ~2.4 sn boşluk. |
| **Mesafe** | Radar/koridor ~520 m yaklaşınca; kentsel ışık/yaya yalnız yakın/kritik. |
| **Koridor ortalama** | Girişte anlık hız; ≥50 m ve ~5 sn sonra mesafe/zaman ortalaması. Aşım: `trueAvg > limit+2` (histerezis `> limit`). |

Müzik üstünde: `alertOverMusic` + `duckOthers` (BT A2DP). `setActive(false)` yok.

---

## 8. Hızlı regresyon listesi

1. BLE bağla → hız/SoC sürekli güncellenir; kadran takılmaz.
2. App rotası aç → uyarılar gelir; kapat + araç nav yok → yol uyarıları durur.
3. Yalnız araç nav → uyarılar gelir (plan/pin ile polyline).
4. `İş` / `Ev` → pin koordinatı; Isparta/İstanbul yanlış eşleşme yok.
5. TR rota → OSM + TR koridor cache; EGM yok.
6. Uyarı sesi yalnız bip (TTS yok); aynı nokta bir kez.
7. SoC &lt; %10 → ince kırmızı çerçeve pulse.
