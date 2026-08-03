# Etubu — Uygulama Rehberi

Etubu, Tesla (BLE) odaklı bir **sürüş kümesi (cluster)** uygulamasıdır: hız, şarj, lastik, uyarılar, rota ve uzaktan komutlar tek ekranda, sürüşe uygun şekilde sunulur.

## Ne işe yarar?

- Canlı araç telemetrisi (hız, vites, güç/regen, SoC, menzil, TPMS, iç/dış sıcaklık)
- Rota planlama + yol üstü **kritik noktalar** (radar, hız koridoru, şarj, hava)
- Tesla’da başlayan navigasyonu uygulamaya aktarma (arka planda rota + uyarılar)
- EV sürüş sesi, Live Activity / Dynamic Island, uzaktan BLE komutları
- Tema mağazası ve premium kilitler

## Mimari (kısa)

| Katman | Rol |
|--------|-----|
| SwiftUI Cluster (`EtubuClusterRootView`) | Ana sürüş UI |
| Capacitor Web (`RouteGuard`, AudioEngine) | Rota/uyarı/ses yedeği |
| `EtubuTeslaBleSession` | BLE telemetri + komutlar |
| `EtubuRouteBridge` | Rota planı (EGM TR / OSRM+OSM global) |
| `EtubuDriveWarnings` + `EtubuLiveRadarMonitor` | Radar / koridor / yaklaşma |
| `EtubuPremiumManager` | StoreKit lifetime premium |
| Live Activity | Dynamic Island özeti |

## Rota mantığı

1. **Uygulamada rota:** Kullanıcı varış yazar → TR’de EGM (+ seed/OSM), yurt dışında OSRM + Overpass.
2. **İl/ilçe:** UI’da zorunlu değil; arka planda TR index veya Nominatim ile çözülür.
3. **Bölge cold start:** GPS yokken TR varsayılmaz — ilk fix sonrası pipeline seçilir (Maestro İstanbul GPS ile TR yolu açılır).
4. **Araç navigasyonu:** Tesla `activeRouteDestination` paylaşırsa ve app’te kullanıcı rotası yoksa → otomatik “Konumum → hedef” planı + kritik nokta servisleri (**Premium** — free’de plan/radar yok; dial + OSM hız + hedef etiketi kalır).
5. App rotası aktifken Tesla nav hedefi **ezmez** (bağımsız hat).

## Uzaktan komutlar

- Yeşil: açık/aktif durum veya kullanılabilir
- Kırmızı: hareket halinde kilitli (frunk, bagaj, cam, şarj kapağı)
- Bagaj / şarj kapağı: aynı tuş aç-kapa (toggle)
- Frunk: BLE yalnızca açma; kapatma manuel

## Premium

- Ürün: `com.etubu.premium` (ömür boyu)
- Cache + StoreKit; cold start’ta yanlış “kilitli” flash engellenir
- Maestro / debug: `etubuForcePremium`
- Free: kadran + OSM hız limiti. Premium: rota, radar/koridor, temalar, canlı harita
- Onboarding (sim sayfa 3) + paywall bu ayrımı açıkça gösterir

## Legal

- 7 dil (`EtubuClusterL10n`); gövde `legalSec*` anahtarları
- Bağlıyken BLE uzaktan komutlar (iklim/kilit/bagaj) açıkça bildirilir; sürüş kontrolü yok

## Ses

- Native `EtubuNativeDriveAudio` cold-start/demo sahibi; Cap ısınırsa el değiştirir
- İkisi birden mute olmaz; demo’da native birincil kalır
- EV Sound varsayılan kapalı; tek seferlik keşif ipucu (+ sim sayfa 4)

## Arka plan

- Rota aktifken GPS background + uyarı tick
- Dynamic Island: hareket **veya** aktif app rotası varken tutulur; park + rota yoksa kapanır (~25s BG task yalnızca idle’da end eder)

## Region

- Cold start: `lastKnownInTurkey` defaults **false / unknown** until first GPS fix (no EGM/TR seeds overseas by mistake).
- After GPS: TR bounds → EGM + OSM enrich; outside → OSRM + Overpass cameras.
- Cap `etubu_force_tr_route` mirrors the same flag; Nominatim when not-TR.
- İlçe zorunlu değil (native + Cap route-guard).

## CarPlay / Ads

- **CarPlay:** foundation scene exists (`EtubuCarPlaySceneDelegate`) but **not shipping** — no `carplay-charging` entitlement; Apple will not show the app on CarPlay until granted.
- **AdMob:** not wired. Native plugin refuses; Cap ads.js skips native/cluster. Web may still run Yandex/AdSense when `ADS_ENABLED`.

## Dosya haritası (sık dokunulanlar)

- `ios/App/App/Cluster/` — UI, rota, uyarı, premium, ses
- `ios/App/App/Tesla/` — BLE oturum + telemetri modeli
- `public/js/route-guard.js` — web rota/uyarı
- `.maestro/` — UI otomasyon

## Test

```bash
npm run test:maestro
```

Simülatör konumu suite içinde İstanbul’a set edilir; premium force arg ile kilitler açılır.
