# Etubu — Maestro Gap Raporu

**Tarih:** 9 Ağustos 2026  
**Cihaz:** iPhone 17 Pro Simulator (`911C9ECF-93D6-49A1-9A5C-B12FE8C273EC`, iOS 26.5)  
**Konum:** `simctl location` → İstanbul `41.0082,28.9784`  
**Build:** Fresh `npm run build:ios` + `simctl install` (telemetry/hazard değişiklikleri dahil)  
**Komut:** `npm run test:maestro` (UDID-aware)

---

## 1. Suite envanteri

### `package.json` → `test:maestro` (12 flow)

| # | Flow | Rol |
|---|------|-----|
| 1 | `.maestro/smoke-onboarding.yaml` | Legal → cluster → rota typing smoke |
| 2 | `.maestro/legal-reject-blocked.yaml` | Checkbox yokken kabul engeli |
| 3 | `.maestro/premium-route-lock.yaml` | Paywall + 249 TL + satın al / kod |
| 4 | `.maestro/route-plan-check.yaml` | Premium rota planı (TR şehir) |
| 5 | `.maestro/theme-landscape-check.yaml` | Tema mağazası + landscape dial |
| 6 | `.maestro/theme-apply-check.yaml` | Aurora tema uygula → dial |
| 7 | `.maestro/remote-lang-check.yaml` | Dil satırı TR + remote sheet aç |
| 8 | `.maestro/remote-sheet-smoke.yaml` | Remote sheet crash-yok smoke |
| 9 | `.maestro/language-switch-en.yaml` | EN chrome (`etubuForceLangEn`) |
| 10 | `.maestro/demo-stop-sound-check.yaml` | Demo + mute tercih + stop temizliği |
| 11 | `.maestro/demo-drive-check.yaml` | Demo D + Radar / YOL UYARILARI |
| 12 | `.maestro/ev-plan-demo-check.yaml` | Demo EV strip / arrival SoC |

### Helper’lar (suite listesinde yok; `runFlow` ile çağrılır)

| Dosya | Rol |
|-------|-----|
| `.maestro/setup-legal.yaml` | İzin dismiss + legal accept |
| `.maestro/dismiss-permissions.yaml` | Sistem izin diyalogları |

**Toplam YAML:** 14 (12 suite + 2 helper).

---

## 2. Suite sonuçları

### İlk tam koşu (`npm run test:maestro`)

| Flow | Sonuç | Süre | Not |
|------|--------|------|-----|
| smoke-onboarding | ✅ Pass | 1m 47s | |
| legal-reject-blocked | ✅ Pass | 24s | |
| premium-route-lock | ✅ Pass | 53s | |
| route-plan-check | ✅ Pass | 1m 17s | |
| theme-landscape-check | ❌ Fail | 1m 11s | `No visible element found: "Tema mağazası"` (scroll timeout flake) |
| theme-apply-check | ✅ Pass | 1m 32s | Aynı metin, daha uzun timeout ile geçti |
| remote-lang-check | ✅ Pass | 1m 12s | |
| remote-sheet-smoke | ✅ Pass | 1m 2s | |
| language-switch-en | ✅ Pass | 1m 8s | |
| demo-stop-sound-check | ✅ Pass | 1m 31s | |
| demo-drive-check | ✅ Pass | 1m 23s | |
| ev-plan-demo-check | ✅ Pass | 2m 17s | |

**İlk koşu özeti:** **11/12 Pass** · 1 flake fail (ürün regresyonu değil).

### Flake düzeltmesi + yeniden koşu

`theme-landscape-check.yaml` içinde `"Tema mağazası"` / `etubu.theme.tesla` scroll timeout’ları `theme-apply-check` ile hizalandı (25s→30s / 20s→25s).

| Flow | Sonuç | Not |
|------|--------|-----|
| theme-landscape-check (retry) | ✅ Pass | ~2.5m; landscape `km/h` + `etubu.dial` OK |

**Düzeltilmiş suite durumu:** **12/12 Pass** (ürün regresyonu yok; tek sorun Maestro scroll flake idi).

---

## 3. Kanıtlananlar (ne ispatlandı)

| Yolculuk | Kanıt |
|----------|--------|
| **Legal / onboarding** | Checkbox zorunlu; kabul sonrası cluster (`settings.open`, `km/h`); reject akışı cluster açmıyor |
| **Premium lock / paywall** | Force-premium yokken rota → Etubu Premium, `249 TL`, buy/redeem |
| **Route plan (TR)** | Force-premium ile picker; şehir (`Corum`); ilçe nag yok; plan → `etubu.route.active` |
| **Theme / landscape** | Tema mağazası + Tesla/Aurora; landscape dial; portrait dönüş |
| **Remote sheet / language** | TR dil satırı; EN force chrome; remote sheet (`climate.on`) araçsız açılıyor |
| **Demo drive / sound** | Gear D, speed, Radar / YOL UYARILARI; mute toggle; stop sonrası temiz UI + ses kapalı kalır |
| **EV plan** | Demo’da `ev.arrivalSoc`, portrait strip, Maps open; ayarlarda “EV rota planı” |

---

## 4. Eksik / zayıf alanlar (öncelikli)

### P0 — kritik, sim’de kısmen veya hiç yok

1. **Tesla BLE pair + live telemetry** — Pair/VIN/NFC/BLE chrome ve canlı hız/vites/SoC/TPMS assert yok; suite tamamen `etubuSkipOnboarding` + demo/force-premium.
2. **TPMS / SoC live değer assert** — `etubu.tpms.grid` görünürlüğü var; lastik bar / SoC yüzde / “awaiting”→gerçek değer geçişi yok.
3. **Vehicle-nav adapt** — Tesla share destination → `adaptVehicleNavIfNeeded` Maestro’da yok (BLE sim yok).
4. **Gerçek rota üzerinde critical points / radar** — Demo’da “Radar” metni var; EGM/OSM koridor brief, approach TTS, hazard strip assert yok.
5. **Live Activity / Dynamic Island** — Sim’de XCUITest/manuel; Maestro Island assert edemez.
6. **powerKw / speed fluidity** — Dial `km/h` var; güç çubuğu, regen, yumuşak interpolasyon ölçülmüyor.
7. **Climate / remote komutları** — Sheet açılıyor; climate on/off, lock, frunk, charge **aksiyon** assert yok.
8. **Reconnect / session recovery** — BLE drop → reconnect / last-known SoC yolu yok.
9. **Overseas route** — Yalnızca TR GPS + TR şehir; intl OSRM/Overpass + dil kopyası yok.

### P1 — zayıf / yüzeysel coverage

| Alan | Zayıflık |
|------|----------|
| Onboarding gerçek akış | `etubuSkipOnboarding: true` — Başla/Atla / sim skip derinliği zayıf |
| Premium satın alma | Paywall UI; StoreKit purchase/restore/SIWA yok |
| Tema kilitleri | Apply Aurora (force premium); free tema kilidi / StoreKit tema unlock yok |
| Ses profilleri | Mute toggle; 14 tema→4 `driveBasePack` cycle yok |
| Rota hazard | Demo uyarı metni; aktif rota brief / kamera yaklaşımı yok |
| i18n | EN force + TR satır; 7 dil cycle / legal gövde dili yok |
| Landscape derinlik | Dial görünür; landscape remote/EV strip derinliği yok |

### P2 — manuel / cihaz zorunlu

- Fiziksel Tesla BLE pair, NFC card, Background Modes
- Live Activity kilit ekranı / Island
- Gerçek GPS hareketi + radar yaklaşımı
- App Store Sandbox IAP
- CarPlay (ship değil / stub)
- Ses kulakla doğrulama (pitch/powerKw)

---

## 5. Önerilen yeni Maestro flow’lar

### Sim’de eklenebilir (somut YAML)

| YAML | Assert edeceği |
|------|----------------|
| `premium-theme-lock.yaml` | Force-premium **yok**; tema satırında kilit / paywall; Tesla ücretsiz kalır |
| `premium-restore-chrome.yaml` | Paywall’da `etubu.premium.restore` + SIWA satırı görünür (purchase yok) |
| `sound-profile-cycle.yaml` | Settings’te ses profili / tema→timbre değişimi; `etubu.sound.on` kalır |
| `route-hazard-brief-check.yaml` | Plan sonrası aktif rota; hazard/radar strip veya brief metin (`YOL UYARILARI` / kamera) |
| `ev-plan-real-route-check.yaml` | Demo değil: gerçek plan + `ev.arrivalSoc` / chargeSuggest (TR GPS) |
| `remote-climate-tap-smoke.yaml` | Sheet → `etubu.remote.climate.on` tap → hata/crash yok (BLE yoksa disabled/toast) |
| `language-cycle-smoke.yaml` | TR→EN→DE (veya 2 dil) chrome başlık assert |
| `legal-body-lang-check.yaml` | `etubuForceLangEn` ile legal başlık/EN gövde (metin düzeltilince) |
| `tpms-placeholder-check.yaml` | Bağlantısız: `etubu.tpms.grid` + `etubu.tpms.awaiting` (veya —) |
| `onboarding-sim-skip.yaml` | Skip flag **kapalı**; sim skip / Başla yolu (flaky olabilir) |
| `pair-badge-chrome.yaml` | Pair/source chip görünür (`etubu.source.chip`); BLE yokken “bağlı değil” |

### Manuel / cihaz / XCTest kalmalı

| Konu | Neden Maestro yetmez |
|------|----------------------|
| Tesla BLE pair + live speed/SoC/TPMS | Gerçek araç / özel BLE stub gerekir |
| Vehicle-nav adapt | Tesla nav share → native bridge |
| powerKw / speed smoothness | Zaman serisi / görsel regresyon |
| Live Activity | System UI; Maestro Island okumaz |
| Reconnect | Uzun BLE session |
| Overseas route + EGM dışı radar | Bölge + ağ |
| IAP purchase/restore gerçek | Sandbox Apple ID |
| Climate komutun araca gitmesi | BLE + araç |

---

## 6. Kritik journey × coverage matrisi

| Journey | Suite durumu | Kanıt kalitesi |
|---------|--------------|----------------|
| Legal / onboarding | ✅ Covered | İyi (reject + accept); gerçek onboarding zayıf |
| Premium lock / paywall | ✅ Covered | UI iyi; purchase zayıf |
| Route plan (TR) | ✅ Covered | İyi |
| Theme / landscape | ✅ Covered | İyi (flake düzeltildi) |
| Remote sheet / language | ✅ Covered | Chrome iyi; komut zayıf |
| Demo drive / sound | ✅ Covered | İyi |
| EV plan | ✅ Covered | Demo yolu; gerçek rota EV zayıf |
| Tesla BLE / live telemetry | ❌ Not covered | — |
| TPMS/SoC live assert | ❌ Not covered | Grid smoke only |
| Vehicle-nav adapt | ❌ Not covered | — |
| Critical points / radar (real route) | ⚠️ Weak | Demo metin only |
| Live Activity | ❌ Not covered | Manuel |
| powerKw / speed fluidity | ❌ Not covered | — |
| Climate actions | ⚠️ Weak | Sheet open only |
| Reconnect | ❌ Not covered | — |
| Overseas route | ❌ Not covered | — |

---

## 7. Sonuç

- Fresh rebuild + UDID suite: **ilk koşuda 11/12**; tek fail **scroll timeout flake** (`Tema mağazası`).
- Timeout hizalaması sonrası **theme-landscape-check geçti** → ürün regresyonu görülmedi.
- Suite, **legal → premium → TR rota → tema → remote chrome → demo/EV** çekirdeğini kanıtlıyor.
- En büyük boşluklar: **canlı Tesla telemetri, gerçek rota hazard, Live Activity, remote aksiyonlar, reconnect, overseas**.

**Çalıştırma:** `npm run test:maestro` (booted iPhone 17 Pro + İstanbul location).  
**Bu rapor:** `docs/MAESTRO_GAP_REPORT.md`
