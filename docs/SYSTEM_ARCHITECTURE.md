# Etubu / Lokus — Sistem Mimarisi ve Bağlam Özeti

Bu belge, mevcut iOS uygulamasını **yeniden kurmadan** geliştirmek isteyen bir asistan için bağlamdır. Ham kaynak kopyalanmaz; veri hattı, sahiplik ve kısıtlar özetlenir.

**Repo:** `/Users/sinan/Projects/etubu`  
**Build:** `xcodebuild -workspace ios/App/App.xcworkspace -scheme Etubu -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`  
**Hedef:** iOS 17+, Capacitor + native SwiftUI cluster overlay.

---

## 1. Proje özeti ve dosya ağacı

### Amaç

Tesla (VIN eşleşmeli BLE) odaklı **sürüş kümesi**: hız, vites, güç/regen, SoC, menzil, TPMS, iklim, kilit, rota, yol uyarıları, EV sesi, Live Activity / Dynamic Island, uzaktan BLE komutları. Tesla yoksa ELM327 **OBD BLE** yedek hız kaynağıdır.

Capacitor WKWebView (`public/`) hâlâ durur (rota yedeği, ses, yasal sayfalar). Kullanıcıya görünen asıl UI, Capacitor’ün **üstünde ayrı bir `UIWindow`** içinde SwiftUI cluster’dır.

### Teknolojiler

| Katman | Teknoloji |
|--------|-----------|
| UI | SwiftUI overlay (`EtubuClusterPresenter`) |
| Shell | Capacitor + WKWebView |
| Tesla | Vendored `swift-tesla-ble` (CoreBluetooth, protobuf, ECDH oturum) |
| GPS | CoreLocation (`EtubuMapLocationHelper`) |
| OBD | CoreBluetooth ELM327 (`EtubuObdBleManager`) |
| Harita | MapKit |
| Widget / Island | WidgetKit, ActivityKit |
| IAP | StoreKit (`EtubuPremiumManager`, ürün `com.etubu.premium`) |
| Ses | Native `AVAudioEngine` + Cap `audio-engine.js` |
| Test | Maestro (`.maestro/`) |

### Kritik kısıtlar (asistan kuralları)

- **`EtubuCameraCutout.swift` yerleşimini değiştirme** (notch / Dynamic Island).
- CarPlay ve Apple Watch **kullanıcı tarafından ertelendi**; entitlement yok, shipping değil.
- `EtubuClusterL10n` içinde **dil başına anahtar tekrarı yok** (iOS 27 dictionary literal trap).
- Commit yalnızca kullanıcı isterse.
- BLE kablosu **tek in-flight imzalı istek**; drive poll’u 3 Hz yapma (extras/SoC aç kalır).

### Hiyerarşik ağaç (kritik)

```
etubu/
├── ios/App/
│   ├── App.xcworkspace          ← açılacak workspace
│   ├── App/                     ← native target Etubu
│   │   ├── AppDelegate.swift    ← overlay kurulumu, ses oturumu
│   │   ├── Info.plist           ← BLE + WhenInUse/Always location
│   │   ├── Tesla/
│   │   │   ├── EtubuTeslaBleSession.swift    ← pair, poll, komutlar
│   │   │   ├── EtubuVehicleTelemetry.swift   ← tekil cluster state
│   │   │   ├── EtubuSpeedFusion.swift        ← BLE+GPS tamamlayıcı filtre
│   │   │   ├── EtubuTeslaVinStore.swift      ← Keychain VIN
│   │   │   ├── EtubuBluetoothGate.swift
│   │   │   └── EtubuChargeEstimator.swift
│   │   ├── Cluster/             ← ana sürüş UI + rota + uyarı
│   │   │   ├── EtubuClusterPresenter.swift
│   │   │   ├── EtubuClusterRootView.swift    ← dashboard (~3k satır)
│   │   │   ├── EtubuClusterComponents.swift  ← kadran, uyarı kartı
│   │   │   ├── EtubuMapLocationHelper.swift  ← CoreLocation
│   │   │   ├── EtubuRouteBridge.swift / EtubuRoutePickerView.swift
│   │   │   ├── EtubuDriveWarnings.swift / EtubuHazardMerge.swift
│   │   │   ├── EtubuOsmHazardsMonitor.swift / EtubuLiveRadarMonitor.swift
│   │   │   ├── EtubuEvRoutePlanner.swift
│   │   │   ├── EtubuCameraCutout.swift       ← DOKUNMA
│   │   │   ├── EtubuCarPlaySceneDelegate.swift  ← stub, shipping değil
│   │   │   └── EtubuClusterL10n.swift
│   │   ├── OBD/                 ← ELM327 yedek
│   │   ├── Dashboard/           ← eski OBD panosu (cluster birincil)
│   │   └── EtubuLiveActivityController.swift
│   └── EtubuWidgets/            ← Live Activity + status widget
├── ios/Vendor/swift-tesla-ble/  ← TeslaVehicleClient, Dispatcher, BLETransport
├── public/                      ← Capacitor web (route-guard, audio)
├── docs/                        ← bu dosya + TESLA_BLE_TELEMETRY.md (kısmen eski)
└── .maestro/                    ← UI otomasyon
```

---

## 2. Mimari ve state yönetimi

Klasik per-screen MVVM yok. **Paylaşılan `@MainActor` singleton `ObservableObject`’ler** + SwiftUI `@ObservedObject`. Combine dolaylı (Published). Capacitor JS köprüsü (`EtubuClusterAudioBridge.evalJS`) web yedeğini besler.

```
BLE / OBD / GPS / OSM
        │
        ▼
EtubuVehicleTelemetry.shared     ← hız, vites, SoC, TPMS, konum, connectionState
EtubuDriveWarnings.shared        ← primary/queue, hazards, corridor
EtubuMapLocationHelper.shared    ← CLLocation, gpsIndicator
EtubuTeslaBleSession.shared      ← pairStep, komutlar
EtubuPremiumManager.shared
EtubuEvRoutePlanner.shared
        │
        ▼
EtubuClusterRootView  (@ObservedObject singletons, @State UI, @AppStorage tercih)
        │
        ▼
EtubuSpeedDialView / Map / uyarı kartları / ayarlar sheet
```

| Sınıf | Rol |
|-------|-----|
| `EtubuVehicleTelemetry` | Tek doğruluk kaynağı: `kmh` / `kmhFine`, `gear`, `socPercent`, `connectionState`, `source` (`.tesla` / `.obd` / `.gps` / `.demo` / `.none`) |
| `EtubuTeslaBleSession` | VIN pair (NFC kart), connect, poll loop, remote commands |
| `EtubuDriveWarnings` | Rota/yaklaşma uyarı kuyruğu; HUD `primary` |
| `EtubuMapLocationHelper` | GPS start/pause (araç oturumu, rota picker, aktif rota, Maestro) |
| `EtubuClusterPresenter` | Overlay `UIWindow` + `UIHostingController<EtubuClusterRootView>` |
| `EtubuRouteBridge` | Native OSRM/Overpass plan + Cap RouteGuard enjeksiyonu |

Yerel UI state (`showSettings`, tema, klavye) `EtubuClusterRootView` içinde `@State`. Tercihler `@AppStorage` / `UserDefaults`.

**Veri akışı (hız):**  
`TeslaVehicleClient.fetchDrive` → `applyDrive` → `applyTeslaDrive` → `SpeedFusion.blend` → `kmhFine`/`kmh` → kadran 30 Hz chase.

---

## 3. Tesla BLE ve sensör füzyonu

### 3.1 Kütüphane bağı

Vendored paket: `ios/Vendor/swift-tesla-ble`. Session `import TeslaBLE` ile `TeslaVehicleClient` kullanır. Anahtarlar Keychain’de (`KeychainTeslaKeyStore`, service `com.etubu.app.teslaBLE`). VIN `EtubuTeslaVinStore`.

`Dispatcher`: Infotainment ve VCSEC için **tek kablo** (`wireBusy`). Timeout’lu imzalı istek. `fetchDrive(timeout:)` = `.driveOnly` (küçük protobuf, düşük gecikme). Tam snapshot `.charge` / `.climate` / `.tirePressure` / `.location` / `.closures`.

### 3.2 Çekme döngüsü (`startPolling`)

Hepsi `Task` + `async/await` + `Task.sleep` (DispatchTimer drive için yok). Döngüler **birbirini iptal etmez**.

| Loop | Cadence | Kaynak | Alanlar |
|------|---------|--------|---------|
| Drive | hareket ~**0.7 s** sleep + RTT ≈ 1 Hz; park **~2.2 s**; timeout **2 s** | `client.fetchDrive` | speedMph, shift, power, odo, active route |
| Extras | SoC yoksa ~8 s; sağlıklıysa **~60 s** | sequential `fetch(.categories)` | charge, climate, TPMS, location, closures |
| VCSEC | **~2.5 s** | `query(.bodyControllerState)` | kilit, kullanıcı varlığı |
| Keepalive | ~12 s | `send(.security(.wakeVehicle))` | infotainment uyumasın |
| Heal | ~30 s | extras taze değilse wake + bootstrap | donmuş SoC |

Bağlantı: `connected` / `reconnecting` = `teslaSessionLive`. İlk eşleşmeden sonra **yeni anahtar / NFC kart istenmez**; reconnect mevcut oturumla.

`applyDrive`: `speedMph * 1.60934` → km/h. `speedMph == nil` ise önceki hız **silinmez**.

### 3.3 GPS (HUD değil, harita + füzyon girdisi)

`EtubuMapLocationHelper` CoreLocation’ı **sürekli açık tutmaz**. Çalışır: Tesla/OBD oturumu, rota picker, aktif rota, veya Maestro. Bağcılar yörünge sim’i **kaldırıldı**. Dururken pin donar (`isVehicleStopped`).

HUD için GPS **yalnızca** `location.speed` (m/s×3.6) ve geçerlilik: `horizontalAccuracy` 0…20 m, `speed >= 0`. Haversine türevi kadrana yazılmaz.

### 3.4 SpeedFusion (tamamlayıcı filtre)

Dosya: `ios/App/App/Tesla/EtubuSpeedFusion.swift`  
Saf fonksiyon; BLE/GPS sahibi değil.

Çağrı: `EtubuVehicleTelemetry.publishFusedHudSpeed` Tesla dalında.

```swift
// P/N veya BLE < 2 km/h → 0 (GPS yok)
// BLE yaşı < 0.35 s → sadece Tesla
// 0.35…8 s → wGps = (age-0.35)/(8-0.35)  → fused = ble*(1-w) + gps*w
// ≥ 8 s → geçerli GPS; yoksa son BLE tutulur
```

Entegrasyon:

```swift
// MapLocationHelper didUpdateLocations
if SpeedFusion.isGpsSampleValid(loc) {
    t.applyGpsSpeedBridge(kmh: loc.speed * 3.6, sampleValid: true)
} else {
    t.applyGpsSpeedBridge(kmh: 0, sampleValid: false)
}

// publishFusedHudSpeed
if teslaSession {
    let out = SpeedFusion.blend(.init(
        gear: gearNow, parkedHint: parkedHint == true,
        bleKmh: teslaKmhFineHeld, bleAge: teslaAge,
        gpsKmh: gpsKmhFine, gpsValid: gpsSampleValid && gpsAge < 1.6))
    kmhFine = out.kmh
}
```

**OBD füzyona girmez:** `source == .obd` iken SpeedFusion atlanır; OBD km/h (ingest &lt; 5 → 0, gösterim &lt; 3 → 0). Tesla reconnect/connecting iken OBD yazmaz.

**Eşleşmemiş telefon:** `vehicleSessionLive == false` → HUD 0. GPS kadranı sürmez.

Kadran `kmhFine` okur; ayrı bir `SpeedFusionManager` / ikinci `CLLocationManager` yok.

---

## 4. Arayüz katmanı

### Overlay

`AppDelegate.didFinishLaunching` → `EtubuClusterPresenter.installOverCapacitor()`. Cluster, Cap root VC’nin çocuğu değildir; scene bounds + orientation ile tam ekran overlay.

Onboarding / yasal kabul / sim `EtubuClusterRootView` içinde; bitince `startCoreIfNeeded()` (BLE bootstrap, warnings poll, idle timer off). GPS izni cluster açılışında değil, araç/rota ihtiyacında.

### Dashboard kompozisyonu (`EtubuClusterRootView`)

Tek ekran, yatay/dikey `EtubuClusterLayoutMetrics`:

- Üst: bağlantı, GPS chip, tema, ayarlar, çıkış  
- Orta: MapKit (araç pini, rota polyline, hotspot’lar)  
- `EtubuSpeedDialView`: hız halkası, vites, kW, SoC halka  
- İkiz kartlar: koridor ort. + **yol uyarıları** (`EtubuRoadWarnTwinView` ← `warnings.primary`)  
- SoC / TPMS / iklim / medya panelleri  
- Uzaktan komut şeridi (`EtubuRemotePinnedBar`)  
- Stealth: `EtubuStealthSpeedView` (OLED yalnızca hız; 10 sn dokunmama)

Rota: sheet `EtubuRoutePickerView` — tüm dillerde TR yapısı (Buradan → Nereye, plan, özet, **Rotayı sil**). Uyarı listesi: yol uyarıları 1., şarj 2.

**Premium:** free = kadran + OSM hız limiti. Premium = rota, radar/koridor, şarj planı, temalar, canlı harita uyarıları.

### 30 Hz akıcılık

`AnimatableModifier` yok. `EtubuSpeedDialView` `Timer.publish(every: 1/30)` ile `displayKmh`’yi `kmhFine` hedefine **üstel chase** (tau ~0.055–0.10 s, max km/h/s tavanı). Park/P/N veya hedef &lt; 2 km/h → 0’a sönüm. `contentTransition(.identity)` (sayı zıplamasın).

Live Activity ~0.5 s throttle; widget `EtubuSharedDriveSnapshot`.

**Notch / Island:** `EtubuCameraCutout` + `EtubuNotchAuraView`. Geometry’yi “iyileştirme” — **yapma**.

---

## 5. Eksikler, sapmalar, TODO

Kodda neredeyse **TODO/FIXME yok**. Gerçek boşluklar:

| Durum | Not |
|-------|-----|
| CarPlay | `EtubuCarPlaySceneDelegate` stub. `carplay-charging` entitlement yok. **Shipping değil.** Kullanıcı erteledi. |
| Apple Watch | Yok. Kullanıcı erteledi. |
| AdMob | Native reddeder; cluster’da yok. Web `ADS_ENABLED` ile Yandex/AdSense olabilir. |
| `EtubuVehicleLaunchNotifier.configure()` | `AppDelegate` içinde **ertelendi** (erken bildirim izni diyaloğu). |
| `docs/TESLA_BLE_TELEMETRY.md` | **Eski:** drive’ı ~3 Hz yazar; gerçek ~1 Hz + SpeedFusion. |
| `docs/APP_OVERVIEW.md` | Bağcılar sim GPS hâlâ yazılı; yörünge **kaldırıldı**. |
| EGM resmi radar | Emekli. OSM + TR koridor cache. |
| Dashboard/ | Eski OBD pano; birincil UI cluster. OBD **çalışır** (ayarlar picker, PID 010D hız). |
| Charge schedule protobuf | Kütüphanede “not yet surfaced”. |
| ClusterRootView | Çok büyük tek View; fazla `onChange` type-check süresini patlatabilir. |

### Bilinen doğru davranış (hız)

Tesla asıl; GPS boşluk doldurur; P/N veya BLE &lt; 2 → 0; eşleşmemiş GPS HUD yok.

### Yol uyarıları

`SpeedFusion` ile karıştırma. HUD kuyruğu `EtubuDriveWarnings`: radar/koridor/tünel/hemzemin **önce**, şarj **ikinci** (`warnPriority`, şarj HUD eşiği ~800 m veya `needsChargeStop`).

### Test

`.maestro/` — çoğu `etubuSkipOnboarding` + `etubuForcePremium`. Rota planı picker açıkken simülatör GPS ister (`simctl location`).

### İlgili belgeler

- `docs/APP_OVERVIEW.md` — ürün rehberi (GPS sim maddesi stale olabilir)  
- `docs/HAZARD_SOURCES.md` — OSM / koridor  
- `docs/LIVE_ROUTE_RULES.md`  
- `docs/TESLA_BLE_TELEMETRY.md` — alan haritası hâlâ faydalı; poll tablosu güncel değil  

---

## Asistan için kısa karar ağacı

1. Hız yanlış/geç → `SpeedFusion` + `publishFusedHudSpeed` + drive poll aralığı; UI kadranını yeniden yazma.  
2. Uyarı sırası → `EtubuDriveWarnings.warnPriority` / `sortedForDisplay`; SpeedFusion’a dokunma.  
3. Island/notch kaydı → `EtubuCameraCutout` **yok**.  
4. Yeni Swift dosyası → bu proje **folder sync kullanmaz**; `project.pbxproj` Sources’a ekle (ör. `EtubuChargeEstimator` / `EtubuSpeedFusion` kalıbı).  
5. CarPlay/Watch isteme → kullanıcı erteledi, entitlement yok.
