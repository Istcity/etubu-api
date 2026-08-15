# Etubu crash — 2026-08-11 21:23

**Kaynak:** `/Users/sinan/Downloads/Etubu-2026-08-11-212321.ips`  
**Build:** TestFlight `1.0` (81), UUID `db0eba34-6de4-3bff-a218-af9920220aca`  
**Cihaz:** iPhone18,2 · iOS 27.0 beta (`24A5408d`)  
**Ömür:** ~154 ms (launch → crash)

## Dosya neden “açılmıyor”?

Apple `.ips` crash report’ları **tek JSON değil**, iki parça:

1. İlk satır: metadata JSON (`bug_type`, `bundleID`, …)
2. Sonrası: asıl crash body JSON

Bu yüzden TextEdit / birçok “JSON pretty” aracı `JSONDecodeError: Extra data` verir.  
Ayrıca dosyada `com.apple.quarantine` (AirDrop/sharingd) olabilir.

**Nasıl açılır:**

```bash
# Metadata + body’yi ayırıp body’yi pretty-print
python3 - <<'PY'
import json
p = open("/Users/sinan/Downloads/Etubu-2026-08-11-212321.ips").read()
i = p.find("\n")
print(json.dumps(json.loads(p[i+1:]), indent=2)[:4000])
PY
```

veya Xcode → **Devices and Simulators** → Open Console / crash logs; ya da `atos` ile dSYM eşleştirme.

## Bu Çıkış / `exit(0)` mu?

**Hayır.** Bu rapor `exit(0)` (Çıkış) değil.

| Beklenen `exit(0)` | Bu IPS |
|---|---|
| Temiz süreç sonu / bazen “abnormal termination” | `EXC_BAD_ACCESS` / `SIGSEGV` |
| `EtubuAppExit.quitFully` çerçevesi | Yok |
| Uzun oturum sonrası | Launch’tan ~154 ms |

Çıkış yolu yine de gürültülü log / .ips üretebilir. Kullanıcı isteğiyle Çıkış yine **`exit(0)`** (gerçek quit); Home suspend yetersiz kaldı / düğme “çalışmıyor” gibi hissedildi.

## Gerçek crash nedeni

- **Exception:** `EXC_BAD_ACCESS` · `KERN_PROTECTION_FAILURE` · **Stack Guard**
- **Mesaj:** `Could not determine thread index for stack guard region`
- **Termination:** `Segmentation fault: 11`
- **Faulting thread:** main (`com.apple.main-thread`), **281 frame** (stack overflow)

### Semantik zincir (atos + dSYM 11.08.2026 21:07)

1. `UIApplicationMain` → SwiftUI ViewGraph render  
2. Status bar / `UIWindow.safeAreaInsets` sorgusu  
3. `EtubuClusterRootView.windowSafeInsets()` (`EtubuClusterRootView.swift` ~936)  
4. `GeometryReader` body (`~158`, `~176`, `~199`, `~207`)  
5. AttributeGraph ↔ GeometryReader re-entrancy  
6. Derin Swift type-metadata demangle (`libswiftCore` `decodeMangledType` / `decodeGenericArgs`)  
7. Stack Guard’a çarpma → SIGSEGV

**Kök neden:** Overlay hosting’te SwiftUI `safeAreaInsets` sıfırlandığı için body içinde senkron `UIWindow.safeAreaInsets` okumak; bu da status-bar/safe-area yolunu yeniden tetikleyip AttributeGraph döngüsüne ve stack taşmasına yol açıyor (iOS 27 beta’da daha kırılgan).

## Uygulanan düzeltme

1. **`EtubuClusterRootView`:** window inset’leri `@State cachedWinInsets`’te tut; `GeometryReader` içinde UIKit okuma yok. Güncelleme `async` + geometry/orientation notification.  
2. **`EtubuLegalAcceptanceView`:** aynı anti-pattern giderildi.  
3. **`EtubuAppExit`:** kısa teardown (LA / audio / warn / best-effort BLE) sonrası **`exit(0)`** — gerçek uygulama çıkışı. `exit(0)` Analytics/.ips’te gürültülü görünebilir; yine de Çıkış anlamı quit’tir (araç bağlantısını kesmek değil).

## Stack özeti (kısaltılmış)

```
… Swift runtime type demangle (recursive) …
Etubu  __swift_instantiateConcreteTypeFromMangledNameV2
Etubu  EtubuClusterRootView.body  (GeometryReader closures)
SwiftUICore  GeometryReader.Child.updateValue
…
UIKit  -[UIWindow safeAreaInsets]
Etubu  windowSafeInsets()
Etubu  body GeometryReader
…
SwiftUICore  ViewGraph.updateOutputs / render
UIKit  UIApplicationMain
Etubu  main
```

## Doğrulama

- Yeni build’de cold start (legal + cluster overlay) crash olmamalı.  
- Çıkış: uygulamayı tamamen kapatmalı (`exit(0)`); Analytics’te SIGSEGV değil, isteğe bağlı “abrupt termination” gürültüsü olabilir.  
- Landscape/portrait dönüşte inset’ler bir frame gecikmeyle güncellenir (kabul edilebilir).
