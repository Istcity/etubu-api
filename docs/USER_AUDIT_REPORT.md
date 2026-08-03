# Etubu — Kullanıcı Denetimi (Net Uygulama)

**Tarih:** Ağustos 2026  
**Kapsam:** iOS Tesla cluster (SwiftUI) + Cap yedek + Maestro + App Store IAP notları  
**Canvas:** `~/.cursor/projects/Users-sinan-Projects-etubu/canvases/etubu-user-audit.canvas.tsx`  
**Kaynaklar:** `docs/APP_OVERVIEW.md`, `ios/App/App/Cluster/*`, `ios/App/App/Tesla/*`, `.maestro/*`, `public/js/*`, `docs/app-store/iap-review-notes.txt`

---

## 1. Özet skor

| Metrik | Değer | Not |
|--------|-------|-----|
| Hazırlık (core loop) | **68/100** | Legal → sim → BLE → dial → rota → ses → tema → remote → Island **ship** |
| Cila / “net” his | **58/100** | Trust metinleri, katalog dürüstlüğü, i18n sızıntıları, ses keşfi |
| Maestro kritik coverage | **~48%** | Legal/premium/rota/demo güçlü; BLE/vehicle-nav/LA/remote aksiyon yok |
| Öncelik yükü | **4 P0 · 6 P1 · 3 P2** | Eksik özellikten çok tutarlılık ve iletişim |

**Yargı:** Sürüş döngüsü gerçek bir üründür. “Net uygulama” için engel yarım özellikler değil; legal/remote çelişkisi, premium vaat iletişimi, 14 tema→4 ses paketi, Cap+native ses yarışı ve Live Activity arka plan politikası.

### En kritik 5 risk

1. **Legal “araca komut göndermez”** — remote BLE komutları gönderiyor (`EtubuLegalAcceptanceView` vs `EtubuRemoteCommandCards`) → Store + güven.
2. **Legal gövde TR-only** — UI 7 dil; ilk açılış intl’de anlaşılmaz.
3. **Premium vaat iletişimi** — rota/radar IAP arkasında; free yalnızca OSM hız; sim bunu net söylemiyor.
4. **Ses Cap+native yarışı** — cold start / demo’da sessizlik riski.
5. **Tema/ses kataloğu** — 14 etiket, 4 `driveBasePack`; `webKey` çakışmaları (tesla/midnight→`aurora`).

---

## 2. Özellik matrisi

| Alan | Durum | Kullanıcı etkisi | Öneri | Maestro |
|------|-------|------------------|-------|---------|
| Ses (EV drive) | Kısmi | Default kapalı; 14→4 paket; Cap+native | Keşif + tek ses kaynağı | Var (demo-stop) · **sound-profile-cycle** |
| Temalar | Hazır | 14 tema; free=Tesla; StoreKit | webKey düzelt; apply assert | Kısmi · **theme-apply-check** |
| Yerleşim | Hazır | Portrait+landscape; notch landscape-only | Landscape remote/EV derinliği | Var (theme-landscape) |
| UX / onboarding | Kısmi | Legal→sim→cluster; coach-mark ölü | Spotlight sil/canlandır; free/premium cümlesi | Var (smoke, setup-legal) |
| Grafik / efekt | Kısmi | Dial rings, VFX, cutout; low-range pulse agresif | PowerKw/boost FX; font fallback | Yok |
| Rota oluşturma | Hazır | TR EGM + OSRM; intl OSRM+Overpass; district yok | L10n status; overseas copy | Var (route-plan-check) |
| Otomatik rota | Hazır | BLE dest→plan; app rotası ezilmez | Premium gate tutarlılığı | Yok · **vehicle-nav-adapt** |
| Tesla bağlantı | Hazır | VIN+NFC+BLE; yüksek sürtünme | TR/EN status; OBD ayır | Yok · **pair-badge-chrome** |
| Uzaktan | Hazır | Climate/charge/lock/frunk…; hareket kilidi | Legal metin hizala | Chrome only · **remote-sheet-smoke** |
| Uyarılar / Radar | Kısmi | Premium radar/koridor; free OSM; TTS TR-only | Gerçek rota brief assert | Kısmi (demo) · **route-hazard-brief-check** |
| Live Activity | Kısmi | Sürüşte Island; park’ta kapanır; ~25s BG end | Rota-aktif park politikası | Yok (XCTest/manuel) |
| Premium / IAP | Hazır | Lifetime, SIWA, restore, redeem, 249 TL | Storefront para birimi | Var (premium-route-lock) · **premium-theme-lock** |
| i18n / Region | Kısmi | 7 dil chrome; TR hardcode; TR default | Legal EN; hardcode temizliği | Kısmi · **language-switch-en** |
| Demo drive | Hazır | TR loop, hazard, ses, LA | Stop ses tercihini ezmesin | Var (3 demo flow) |
| Legal | Kırılgan | Gate OK; gövde TR; komut cümlesi yanlış | Metin + dil | Var · **legal-reject-blocked** |

---

## 3. Eksikler (P0 / P1 / P2)

### P0 — trust / core / Store

| ID | Başlık | Detay | Dosyalar |
|----|--------|-------|----------|
| p0-legal-commands | Legal ↔ remote çelişkisi | “Araca komut göndermez” ifadesi yanlış; remote sheet climate/lock/frunk gönderir | `EtubuLegalAcceptanceView.swift`, `EtubuRemoteCommandCards.swift` |
| p0-legal-lang | Legal gövde TR-only | UI L10n 7 dil; yasal gövde sabit TR | `EtubuLegalAcceptanceView.swift` |
| p0-premium-promise | Premium vaat iletişimi | IAP notes: route + radar/corridor premium. Free: dial + OSM. Sim net söylemezse “bozuk” algısı | `iap-review-notes.txt`, `EtubuClusterSimView`, `openRouteOrPaywall()` |
| p0-audio-race | Cap + native ses yarışı | AudioEngine Cap ısınana kadar flaky; demo retry | `EtubuClusterAudioBridge.swift`, `EtubuNativeDriveAudio.swift` |

### P1 — net uygulama cilası

| ID | Başlık | Detay | Dosyalar |
|----|--------|-------|----------|
| p1-theme-sound | 14 tema / 4 timbre + webKey | `driveBasePack`: calm-ev / ion-whisper / sport-ev / boost-launch. tesla+midnight→aurora webKey | `ClusterTheme.swift`, `EtubuSoundVoice.swift` |
| p1-live-activity | Park/idle Island kaybolur | `AppDelegate`: kmh&lt;5 → `endAllNow`; ~25s BG sonra yine end | `AppDelegate.swift`, `EtubuLiveActivityController.swift` |
| p1-vehicle-nav-gate | Manuel vs araç-nav premium | `openRouteOrPaywall` gated; `adaptVehicleNavIfNeeded` premium kontrolü yok. Hazard yine premium’da strip (`EtubuDriveWarnings`) | `EtubuRouteBridge.swift`, `EtubuDriveWarnings.swift` |
| p1-hardcoded-tr | Runtime TR hardcode | BLE status, “Rota aktif”, closures Kilitli/Açık | Tesla session, RouteBridge, ClosuresChip |
| p1-sound-discover | EV Sound keşfi | Default off; demo stop → silent-mode kullanıcı tercihini ezebilir | `EtubuDemoDrive.swift`, `EtubuSoundVoice.swift` |
| p1-coachmarks | Hotspot orphan | Spotlight kaldırılmış; Pair/Route keşfi zayıf | `EtubuClusterHotspots.swift`, `EtubuClusterSimView.swift` |

### P2 — sonra

| ID | Başlık | Detay |
|----|--------|-------|
| p2-region-default | `lastKnownInTurkey` default true | Intl cold start TR pipeline | **✅ P2: default false until GPS** |
| p2-ads-carplay | AdMob / CarPlay stub | “AdMob not wired”; CarPlay entitlement | **✅ P2: gated + docs; CarPlay not shipping** |
| p2-web-divergence | Web ads-free vs native IAP | `paywall.js` free catalog; `www→public` symlink; web district nag hâlâ `route-guard.js` | **✅ P2: aligned** |

---

## 4. Maestro test planı

### Suite bugün (`npm run test:maestro`)

İstanbul GPS `41.0082,28.9784`; çoğu flow `etubuForcePremium` + `etubuSkipOnboarding`; `premium-route-lock` force **yok**.

| Flow | Kanıtlar |
|------|----------|
| `smoke-onboarding.yaml` | Legal → cluster (km/h, TPMS) → rota → Ankara → ilçe nag yok |
| `premium-route-lock.yaml` | Paywall, 249 TL, feat.route, buy/redeem |
| `route-plan-check.yaml` | Corum plan → `etubu.route.active` + Konumum |
| `theme-landscape-check.yaml` | Theme store görünür + landscape dial |
| `remote-lang-check.yaml` | `etubu.remote.open` + language picker (sheet **açmaz**) |
| `demo-drive-check.yaml` | Demo D, Radar/YOL UYARILARI, ses |
| `demo-stop-sound-check.yaml` | Mute persist; stop temiz |
| `ev-plan-demo-check.yaml` | EV strip + settings EV rota planı |
| Helpers | `setup-legal.yaml`, `dismiss-permissions.yaml` |

### Önerilen yeni flow’lar

| Yeni dosya | Kanıtlamalı |
|------------|-------------|
| `premium-theme-lock.yaml` | Non-Tesla → paywall (themes) |
| `sound-profile-cycle.yaml` | Profil seç → on → mute profil bozmaz |
| `theme-apply-check.yaml` | Tema uygula → dial kullanılabilir |
| `remote-sheet-smoke.yaml` | Sheet chrome; araçsız crash yok |
| `language-switch-en.yaml` | EN string assert |
| `route-clear-and-replan.yaml` | Clear + yeniden plan |
| `route-hazard-brief-check.yaml` | Plan sonrası brief/hazard |
| `pair-badge-chrome.yaml` | Pair/source chip görünür |
| `legal-reject-blocked.yaml` | Checkbox yok → cluster yok |
| `vehicle-nav-adapt.yaml` | Mock dest launch arg (BLE fixture) |

**Hâlâ manuel / XCTest:** Tesla BLE pair, Live Activity Island, gerçek satın alma/restore.

**Coverage tahmini:** kritik yolculukların **~45–50%**’i (ağırlıklı: BLE, vehicle-nav, LA, remote aksiyon, purchase = büyük boşluklar).

---

## 5. Hızlı kazanımlar

1. Legal komut cümlesini remote ile hizala (tek paragraf).
2. Legal EN fallback gövde.
3. Sim’de free vs premium bir cümle (“Radar/rota Premium”).
4. İlk hareket sonrası EV Sound one-shot tip.
5. Demo stop kullanıcı ses tercihini ezmesin.
6. Closures + rota status → L10n.
7. Overseas note: OSM kamera var (kopya dürüstlüğü).
8. Orphan hotspot: sil veya coach-mark geri getir.
9. Media kart empty-state.
10. `remote-lang-check` sheet açacak şekilde uzat.

---

## Yolculuk haritası

| Adım | Deneyim | Sürtünme |
|------|---------|----------|
| İlk açılış | Legal → sim → cluster | Legal TR; sim atlanabilir |
| Bağlan | VIN → NFC → BLE | Yüksek; OBD karışıklığı |
| Sür | Dial / TPMS / SoC / powerKw | Free OK |
| Rota | Paywall veya picker | GPS; vaat iletişimi |
| Araç nav | Otomatik plan | Gate tutarsızlığı |
| Ses | Off default; tema=pack | 4 timbre / 14 etiket |
| Tema | Free Tesla | Kapı net |
| Remote | Sheet + hareket kilidi | Legal çelişkisi |
| Arka plan | Island ~25s sürüş | Park = kaybolur |

---

## Cap vs native

| Katman | Rol |
|--------|-----|
| **Native birincil** | SwiftUI cluster, legal, sim, Tesla BLE, StoreKit, vehicle-nav, remote, Live Activity, `EtubuRouteBridge`, `EtubuDriveWarnings` |
| **Cap yedek** | `AudioEngine`, RouteGuard helpers, radar/voice fallback |
| **www** | `www → public` symlink (ayrı kopya değil) |
| **Monetizasyon** | Web: ads-free catalog (`paywall.js`). Native: `com.etubu.premium` lifetime |

### Premium kapıları (shipped)

- Tüm temalar + wallpaper (free: Tesla + atmospheric)
- Live MapKit backdrop
- Rota planlama UI
- Radar / koridor / şarj / hava uyarıları  
- Free: OSM yol hız levhası (`meta: "OSM"`)
- Maestro: `etubuForcePremium`

### Region (shipped)

- Cold start: region unknown → not-TR pipeline until GPS (`lastKnownInTurkey` default false)
- TR domestic: EGM + OSM enrich  
- Overseas: OSRM + Overpass kameralar  
- Araç nav: app rotası yoksa adapt; app rotası aktifken ezmez

### CarPlay / Ads (not shipping)

- CarPlay scene stub only — no entitlement
- AdMob not wired; Cap skips native ads

---

## Önerilen ürün sırası (PO)

1. Legal metin (komut + dil) — P0  
2. Onboarding’de free/premium vaat — P0  
3. Ses stack güvenilirliği — P0  
4. Tema/ses katalog dürüstlüğü — P1  
5. i18n hardcode temizliği — P1  
6. Live Activity park/rota politikası — P1  
7. Vehicle-nav vs premium ürün kararı — P1  
8. Maestro gap flow’ları — paralel  
9. Ads/CarPlay — entitlement hazır olunca  

*Commit yok; bu rapor yalnızca denetim çıktısıdır.*

---

## P0 remediation (Ağustos 2026)

| ID | Durum | Not |
|----|-------|-----|
| p0-legal-commands | ✅ | Legal §1 BLE remote komutları + güvenlik uyarısı; `readOnly` hizalandı |
| p0-legal-lang | ✅ | `legalSec*` 7 dilde (`EtubuClusterL10n`); legal UI dil takip eder |
| p0-premium-promise | ✅ | Sim sayfa 3 + `premiumFreeNote` (sim chip + paywall); free=OSM/dial |
| p0-audio-race | ✅ | Native primary → Cap warm (2× streak) handoff; demo native owns; heartbeat reclaim; `endDrive` tercihi silmez |

P1 soft: EV sound one-shot tip + sim keşif cümlesi; demo stop `silent-mode` ezmesi kaldırıldı.

## P1 remediation (Ağustos 2026)

| ID | Durum | Not |
|----|-------|-----|
| p1-theme-sound | ✅ | Unique `webKey` (`tesla`/`midnight`/`plaid-boost`); Cap Scene MODE+DRAWERS; picker `Tema · Pack` + `voicePackShared` (14→4 timbre) |
| p1-live-activity | ✅ | BG: Island `routeActive \|\| kmh≥3 \|\| demo`; 25s end yalnızca park+rota yok |
| p1-vehicle-nav-gate | ✅ | `adaptVehicleNavIfNeeded` Premium gate (= `openRouteOrPaywall`); free dial/OSM + BLE hedef etiketi |
| p1-hardcoded-tr | ✅ | Closures, conn quality, BLE status, rota status, pair guide → `EtubuClusterL10n` (7 dil) |
| p1-sound-discover | ✅ | P0 tip + demo stop doğrulandı; ekstra spam yok |
| p1-coachmarks | ✅ | Sim orphan hotspot param kaldırıldı; one-shot Pair/Route tip; pair guide spotlight kaldı |

Maestro: `theme-apply-check`, `language-switch-en`, `remote-sheet-smoke`, `legal-reject-blocked`; `remote-lang-check` sheet açar. Legal accept checkbox zorunlu.

## P2 remediation (Ağustos 2026)

| ID | Durum | Not |
|----|-------|-----|
| p2-region-default | ✅ | `lastKnownInTurkey` kayıt yoksa **false**; `hasKnownRegion`; GPS `updateFrom` ile TR yolu. Cap `EtubuRegionHint` default false |
| p2-ads-carplay | ✅ | AdMob: plugin refuse + Cap ads.js native/cluster skip. CarPlay: **not shipping** (no entitlement) — docs + scene comment; full CarPlay yok |
| p2-web-divergence | ✅ | `route-guard` ilçe nag kaldırıldı; metro → Merkez/first; Cap paywall native katalog = IAP; `premiumFreeNote` i18n |

Leftover polish: overseas / place-not-found / planning status → `EtubuClusterL10n` (7 dil).
