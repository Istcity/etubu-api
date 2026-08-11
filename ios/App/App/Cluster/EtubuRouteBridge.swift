import Foundation
import CoreLocation
import MapKit
import UIKit

struct EtubuRoutePlace: Identifiable, Equatable, Hashable {
    var id: String {
        if isMyLocation { return "konumum" }
        if let lat, let lng { return "\(label)|\(lat)|\(lng)" }
        return "\(cityName)|\(districtName)|\(label)"
    }
    let label: String
    let cityName: String
    let districtName: String
    let isMyLocation: Bool
    var isMerkez: Bool = false
    var nearLabel: String = ""
    var lat: Double? = nil
    var lng: Double? = nil
    var districtId: String = ""
}

struct EtubuRouteStatus: Equatable {
    var active: Bool
    var fromLabel: String
    var toLabel: String
    var statusText: String
    var briefText: String
    var brief: EtubuRouteBriefSummary = EtubuRouteBriefSummary()
    var hazardCount: Int = 0
    /// Outside TR / OSRM-only polyline (no EGM radars)
    var navOnly: Bool = false
    /// Full hazard list for route plan detail UI.
    var hazardDetails: [EtubuRouteHazard] = []
}

enum EtubuRouteBridge {
    /// Kullanıcı rotayı temizlediyse araç nav uyarlamasını kısa süre bastır.
    private static var suppressVehicleNavAdaptUntil: Date?
    private static var lastVehicleNavDestKey = ""
    private static var vehicleNavAdaptWork: DispatchWorkItem?
    /// Son plan araç navigasyonundan mı geldi?
    private static var routeFromVehicleNav = false

    /// Shared JS helpers mirroring js/route-guard.js fold / searchPlaces / resolvePlace.
    private static let placeHelpersJS = """
    function __etubuFold(s){
      var t = String(s||'').normalize('NFC').toLocaleLowerCase('tr-TR')
        .replace(/[\\u0300-\\u036f]/g,'');
      return t
        .replace(/ğ/g,'g').replace(/ü/g,'u').replace(/ş/g,'s')
        .replace(/ı/g,'i').replace(/İ/g,'i').replace(/ö/g,'o').replace(/ç/g,'c')
        .replace(/[^a-z0-9\\s]/g,' ').replace(/\\s+/g,' ').trim();
    }
    function __etubuPlaceItems(){
      try {
        // Prefer v4 (UTF-8 safe inject); fall back to v3/v2
        var raw = JSON.parse(
          localStorage.getItem('etubu_place_index_v4')
          || sessionStorage.getItem('etubu_place_index_v4')
          || localStorage.getItem('etubu_place_index_v3')
          || sessionStorage.getItem('etubu_place_index_v3')
          || localStorage.getItem('etubu_place_index_v2')
          || sessionStorage.getItem('etubu_place_index_v2')
          || '{}'
        );
        return raw.items || [];
      } catch(e) { return []; }
    }
    function __etubuSearchPlaces(q, limit){
      var query = __etubuFold(q);
      if (!query || query.length < 2) return [];
      var tokens = query.split(' ').filter(Boolean);
      var items = __etubuPlaceItems();
      var maxN = limit || 8;

      // İlçe adı tek başına (Çankaya) → il + ilçe birlikte listelenir
      var districtExact = items.filter(function(p){ return __etubuFold(p.districtName) === query; });
      if (districtExact.length) {
        districtExact.sort(function(a,b){
          return String(a.label||'').localeCompare(String(b.label||''), 'tr');
        });
        return districtExact.slice(0, Math.max(maxN, 12));
      }

      // Tek il adı → tüm ilçeler, Merkez başta
      var cityExact = items.filter(function(p){ return __etubuFold(p.cityName) === query; });
      if (cityExact.length >= 2 && tokens.length === 1) {
        cityExact.sort(function(a,b){
          if (!!b.isMerkez !== !!a.isMerkez) return a.isMerkez ? -1 : 1;
          return String(a.districtName||'').localeCompare(String(b.districtName||''), 'tr');
        });
        return cityExact;
      }

      // "Ankara Çankaya" / "ankara cankaya"
      if (tokens.length >= 2) {
        var cityTok = tokens[0];
        var distTok = tokens.slice(1).join(' ');
        var compound = [];
        for (var c = 0; c < items.length; c++) {
          var cp = items[c];
          var cCity = __etubuFold(cp.cityName);
          var cDist = __etubuFold(cp.districtName);
          if (cCity !== cityTok && cCity.indexOf(cityTok) !== 0) continue;
          var distScore = 0;
          if (cDist === distTok) distScore = 100;
          else if (cDist.indexOf(distTok) === 0) distScore = 85;
          else if (distTok.indexOf(cDist) === 0 && cDist.length >= 3) distScore = 70;
          else if ((cp.search || '').indexOf(distTok) >= 0) distScore = 50;
          else continue;
          compound.push({ p: cp, score: distScore + (cp.isMerkez ? 2 : 0) });
        }
        if (compound.length) {
          compound.sort(function(a,b){
            if (b.score !== a.score) return b.score - a.score;
            return String(a.p.label||'').localeCompare(String(b.p.label||''), 'tr');
          });
          return compound.slice(0, Math.max(maxN, 12)).map(function(x){ return x.p; });
        }
      }

      var scored = [];
      for (var i = 0; i < items.length; i++) {
        var p = items[i];
        var search = p.search || __etubuFold((p.cityName||'') + ' ' + (p.districtName||'') + ' ' + (p.label||''));
        var score = 0;
        if (search === query) score = 100;
        else if (__etubuFold(p.districtName) === query) score = 90;
        else if (__etubuFold(p.cityName) === query && p.isMerkez) score = 88;
        else if (search.indexOf(query) === 0) score = 70;
        else if (__etubuFold(p.districtName).indexOf(query) === 0) score = 65;
        else if (tokens.every(function(tok){ return search.indexOf(tok) >= 0; })) score = 55;
        else if (search.indexOf(query) >= 0) score = 40;
        else continue;
        if (p.isMerkez) score += 3;
        scored.push({ p: p, score: score });
      }
      scored.sort(function(a,b){
        if (b.score !== a.score) return b.score - a.score;
        return String(a.p.label||'').localeCompare(String(b.p.label||''), 'tr');
      });
      return scored.slice(0, maxN).map(function(x){ return x.p; });
    }
    function __etubuInTurkey(lat, lng){
      return lat >= 35.8 && lat <= 42.35 && lng >= 25.6 && lng <= 45.0;
    }
    function __etubuLiveCoords(){
      try {
        var loc = JSON.parse(localStorage.getItem('etubu_last_map_location') || '{}');
        if (Number.isFinite(loc.lat) && Number.isFinite(loc.lng)) return { lat: loc.lat, lng: loc.lng };
      } catch(e) {}
      try {
        if (typeof GpsTracker !== 'undefined' && GpsTracker.getLastPosition) {
          var fix = GpsTracker.getLastPosition();
          if (fix && Number.isFinite(fix.lat) && Number.isFinite(fix.lng)) return { lat: fix.lat, lng: fix.lng };
        }
      } catch(e2) {}
      return null;
    }
    function __etubuNearestDistrict(lat, lng){
      var best = null, bestD = Infinity;
      var items = __etubuPlaceItems();
      for (var i = 0; i < items.length; i++) {
        var p = items[i];
        if (p.lat == null || p.lng == null) continue;
        var dLat = (Number(p.lat)-lat) * Math.PI/180;
        var dLon = (Number(p.lng)-lng) * Math.PI/180;
        var a = Math.sin(dLat/2)*Math.sin(dLat/2) +
          Math.cos(lat*Math.PI/180)*Math.cos(Number(p.lat)*Math.PI/180)*Math.sin(dLon/2)*Math.sin(dLon/2);
        var d = 2*6371000*Math.asin(Math.sqrt(a));
        if (d < bestD) { bestD = d; best = p; }
      }
      return best;
    }
    function __etubuMyLocation(){
      var pos = __etubuLiveCoords();
      if (!pos) return null;
      var near = __etubuNearestDistrict(pos.lat, pos.lng);
      return {
        label: 'Konumum',
        cityName: near?.cityName || '',
        districtName: near?.districtName || '',
        isMyLocation: true,
        isMerkez: false,
        nearLabel: near?.label || '',
        lat: pos.lat, lng: pos.lng
      };
    }
    function __etubuResolvePlace(text){
      var q = __etubuFold(text);
      if (!q) return null;
      if (q === 'konumum' || q === 'konum' || q === 'my location' || q === 'location') {
        return __etubuMyLocation();
      }
      var tokens = q.split(' ').filter(Boolean);
      // "Ankara Çankaya" → doğrudan il+ilçe
      if (tokens.length >= 2) {
        var hitsCompound = __etubuSearchPlaces(text, 8);
        if (hitsCompound.length) return hitsCompound[0];
      }
      var hits = __etubuSearchPlaces(text, 5);
      if (!hits.length) return null;
      // Tek il adı → Merkez (Ankara → Ankara (Merkez))
      var cityOnly = hits.find(function(h){ return __etubuFold(h.cityName) === q && h.isMerkez; });
      if (cityOnly) return cityOnly;
      var distExact = hits.find(function(h){ return __etubuFold(h.districtName) === q; });
      if (distExact) return distExact;
      return hits[0];
    }
    function __etubuMapPlace(p){
      if (!p) return null;
      return {
        label: p.label || ((p.cityName||'') + (p.isMerkez ? ' (Merkez)' : (' / ' + (p.districtName||'')))),
        cityName: p.cityName || '',
        districtName: p.districtName || '',
        isMyLocation: !!p.isMyLocation,
        isMerkez: !!p.isMerkez,
        nearLabel: p.nearLabel || '',
        lat: (typeof p.lat === 'number') ? p.lat : (p.latitude != null ? Number(p.latitude) : null),
        lng: (typeof p.lng === 'number') ? p.lng : (p.longitude != null ? Number(p.longitude) : (p.lon != null ? Number(p.lon) : null))
      };
    }
    """

    static func primeWarningAudio() {
        EtubuClusterAudioBridge.evalJS("""
        (function(){
          try {
            if (window.RadarAlert && window.RadarAlert.primeAudio) window.RadarAlert.primeAudio();
            if (window.AudioEngine && window.AudioEngine.resume) window.AudioEngine.resume();
            var Ctx = window.AudioContext || window.webkitAudioContext;
            if (Ctx) {
              if (!window.__etubuBeepCtx) window.__etubuBeepCtx = new Ctx();
              if (window.__etubuBeepCtx.state === 'suspended') window.__etubuBeepCtx.resume();
            }
          } catch (e) {}
        })();
        """)
    }

    /// Seed RouteGuard / GpsTracker with native CLLocation before Cap geolocation resolves.
    static func pushNativeLocationToWeb() {
        let t = EtubuVehicleTelemetry.shared
        guard let lat = t.latitude, let lng = t.longitude,
              lat.isFinite, lng.isFinite else { return }
        EtubuClusterAudioBridge.evalJS("""
        (function(){
          try {
            var loc = { lat: \(lat), lng: \(lng) };
            localStorage.setItem('etubu_last_map_location', JSON.stringify(loc));
            sessionStorage.setItem('etubu_last_map_location', JSON.stringify(loc));
          } catch (e) {}
        })();
        """)
    }

    /// Cap stub (`index.html`) → `index-app.html` + RouteGuard script. Autocomplete can
    /// work via native helpers without this; `buildRoute` prefers Cap but has native fallback.
    static func ensureCapAppReady(attemptsLeft: Int = 45, completion: @escaping (Bool) -> Void) {
        EtubuCapBridgeViewController.armWebContent()
        // Short timeout — stub navigation aborts in-flight evaluateJavaScript.
        EtubuClusterAudioBridge.evalJSReturning("""
        (function(){
          try {
            window.__ETUBU_NATIVE_CLUSTER__ = true;
            window.__ETUBU_GPS_ARMED__ = true;
            try {
              var forceTr = \(EtubuRegion.lastKnownInTurkey ? "1" : "0");
              localStorage.setItem('etubu_force_tr_route', forceTr);
              sessionStorage.setItem('etubu_force_tr_route', forceTr);
              window.__etubuForceTrRoute = +forceTr;
            } catch (e0) {}
            if (window.RouteGuard && typeof window.RouteGuard.buildRoute === 'function') return '1';
            if (document.getElementById('routeGuard') && document.querySelector('script[src*=\"route-guard\"]')) return '2';
            if (typeof window.__ETUBU_LOAD_APP__ === 'function') {
              try { window.__ETUBU_LOAD_APP__(); } catch (e) {}
              return '0';
            }
            if (!document.getElementById('routeGuard')) {
              try { location.replace('index-app.html'); } catch (e2) {}
            }
            return '0';
          } catch (e) { return '0'; }
        })();
        """, timeout: 3.5) { raw in
            let ready = (raw == "1" || raw == "\"1\"")
            if ready {
                DispatchQueue.main.async { completion(true) }
                return
            }
            // Scripts present but RouteGuard global not yet — give it a few more ticks.
            let almost = (raw == "2" || raw == "\"2\"")
            if attemptsLeft <= 0 {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let delay = almost ? 0.22 : 0.15
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ensureCapAppReady(attemptsLeft: attemptsLeft - 1, completion: completion)
            }
        }
    }

    /// Builds TR place index (native first) and unlocks route UI without waiting on Cap WebView.
    /// Cap inject / RouteGuard rebuild continues in the background for map + planRoute.
    static func ensureIndex(completion: ((Bool) -> Void)? = nil) {
        Task {
            final class Once: @unchecked Sendable {
                private let lock = NSLock()
                private var done = false
                func run(_ body: () -> Void) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !done else { return }
                    done = true
                    body()
                }
            }
            let once = Once()
            let finish: @Sendable (Bool) -> Void = { ready in
                once.run {
                    DispatchQueue.main.async { completion?(ready) }
                }
            }

            // Instant unlock when a previous session already cached the directory.
            let cached = EtubuTrafikAPI.cachedItemCount()
            if cached > 100 {
                finish(true)
            }

            var nativeReady = cached > 100
            do {
                var n = try await EtubuTrafikAPI.buildAndCachePlaceIndex()
                if n < 100 {
                    n = try await EtubuTrafikAPI.buildAndCachePlaceIndex(force: true)
                }
                nativeReady = n > 100
            } catch {
                nativeReady = EtubuTrafikAPI.cachedItemCount() > 100
            }

            if let raw = EtubuTrafikAPI.cachedIndexJSONString(), EtubuTrafikAPI.cachedItemCount() > 100 {
                await MainActor.run { injectPlaceIndexJSON(raw) }
            }

            // Always finish the spinner once native path settles — Cap can lag forever.
            finish(nativeReady)

            // Background: warm Cap + RouteGuard for planning / map polyline.
            await MainActor.run {
                ensureCapAppReady(attemptsLeft: 24) { _ in
                    if let raw = EtubuTrafikAPI.cachedIndexJSONString(), EtubuTrafikAPI.cachedItemCount() > 100 {
                        injectPlaceIndexJSON(raw)
                    }
                    EtubuClusterAudioBridge.evalJS("""
                    (async function(){
                      try {
                        var forceTr = \(EtubuRegion.lastKnownInTurkey ? "1" : "0");
                        localStorage.setItem('etubu_force_tr_route', forceTr);
                        sessionStorage.setItem('etubu_force_tr_route', forceTr);
                        window.__etubuForceTrRoute = +forceTr;
                        var rg = document.getElementById('routeGuard');
                        if (rg) { rg.hidden = false; rg.classList.remove('is-collapsed','is-drive-hidden'); }
                        var form = document.getElementById('routeForm');
                        if (form) form.hidden = false;
                        if (window.RouteGuard && window.RouteGuard.buildPlaceIndex) {
                          await window.RouteGuard.buildPlaceIndex();
                        }
                        var from = document.getElementById('routeFromInput');
                        if (from) {
                          if (!from.value || !String(from.value).trim()) from.value = 'Konumum';
                          from.dispatchEvent(new Event('focus', { bubbles: true }));
                          from.dispatchEvent(new Event('input', { bubbles: true }));
                        }
                      } catch (e) {}
                    })();
                    """)
                }
            }
        }
    }

    /// Inject UTF-8 place index JSON into Cap localStorage (TextDecoder; not raw atob).
    private static func injectPlaceIndexJSON(_ raw: String) {
        let b64 = Data(raw.utf8).base64EncodedString()
        EtubuClusterAudioBridge.evalJS("""
        (function(){
          try {
            var bin = atob('\(b64)');
            var bytes = new Uint8Array(bin.length);
            for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
            var raw = (typeof TextDecoder !== 'undefined')
              ? new TextDecoder('utf-8').decode(bytes)
              : decodeURIComponent(escape(bin));
            localStorage.setItem('etubu_place_index_v3', raw);
            sessionStorage.setItem('etubu_place_index_v3', raw);
            localStorage.setItem('etubu_place_index_v4', raw);
            sessionStorage.setItem('etubu_place_index_v4', raw);
          } catch (e) {}
        })();
        """)
    }

    private static func pollIndexReady(attemptsLeft: Int, completion: ((Bool) -> Void)?) {
        // Index'i her tick'te yeniden build etme — yalnızca hazır mı bak.
        EtubuClusterAudioBridge.evalJSReturning("""
        (function(){
          try {
            var raw = JSON.parse(
              localStorage.getItem('etubu_place_index_v4')
              || sessionStorage.getItem('etubu_place_index_v4')
              || localStorage.getItem('etubu_place_index_v3')
              || sessionStorage.getItem('etubu_place_index_v3')
              || localStorage.getItem('etubu_place_index_v2')
              || '{}'
            );
            var n = (raw.items || []).length;
            return JSON.stringify({ ready: n > 100, count: n });
          } catch(e) { return JSON.stringify({ ready: false, count: 0 }); }
        })();
        """) { raw in
            var ready = false
            if let raw, let data = raw.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                ready = json["ready"] as? Bool ?? false
            }
            if ready || attemptsLeft <= 0 {
                DispatchQueue.main.async { completion?(ready) }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                pollIndexReady(attemptsLeft: attemptsLeft - 1, completion: completion)
            }
        }
    }

    /// Autocomplete — TR içinde native index; yurt dışında Nominatim (uluslararası).
    static func search(query: String, forFrom: Bool, completion: @escaping ([EtubuRoutePlace]) -> Void) {
        let overseas = !EtubuRegion.lastKnownInTurkey
        if overseas {
            Self.nominatimSearch(query: query, completion: completion)
            return
        }

        let native = EtubuTrafikAPI.searchPlaces(query: query, limit: 48)
        if !native.isEmpty {
            DispatchQueue.main.async { completion(native) }
            return
        }

        let qJSON = jsStringLiteral(query)
        let forFromJS = forFrom ? "true" : "false"
        EtubuClusterAudioBridge.evalJSReturning("""
        (async function(){
          try {
            var qRaw = \(qJSON);
            if (window.RouteGuard && window.RouteGuard.suggest) {
              var hits = await window.RouteGuard.suggest(qRaw, \(forFromJS));
              return JSON.stringify((hits || []).slice(0, 48));
            }
            \(placeHelpersJS)
            var qf = __etubuFold(qRaw);
            var out = [];
            var mine = __etubuMyLocation();
            if (\(forFromJS)) {
              var wantMine = !qf || qf.length < 2 ||
                'konumum'.indexOf(qf) === 0 || qf.indexOf('konum') >= 0 ||
                'mylocation'.indexOf(qf.replace(/\\s/g,'')) === 0;
              var hits = qf.length >= 2 ? __etubuSearchPlaces(qRaw, 40) : [];
              hits = hits.filter(function(p){ return !p.isMyLocation; });
              if (wantMine && mine) out.push(__etubuMapPlace(mine));
              hits.forEach(function(p){ out.push(__etubuMapPlace(p)); });
              return JSON.stringify(out.slice(0, 48));
            }
            if (qf.length < 2) return '[]';
            __etubuSearchPlaces(qRaw, 40).forEach(function(p){ out.push(__etubuMapPlace(p)); });
            return JSON.stringify(out.slice(0, 48));
          } catch (e) {
            return '[]';
          }
        })();
        """) { raw in
            DispatchQueue.main.async {
                let places = Self.parsePlaces(raw)
                if !places.isEmpty {
                    completion(places)
                    return
                }
                // TR index boş / yurt dışı sorgu → Nominatim
                Self.nominatimSearch(query: query, completion: completion)
            }
        }
    }

    private static func nominatimSearch(query: String, completion: @escaping ([EtubuRoutePlace]) -> Void) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            completion([])
            return
        }
        let qJSON = jsStringLiteral(q)
        EtubuClusterAudioBridge.evalJSReturning("""
        (async function(){
          try {
            var t = \(qJSON);
            var url = 'https://nominatim.openstreetmap.org/search?format=json&limit=12&q=' + encodeURIComponent(t);
            var res = await fetch(url, { headers: { 'Accept-Language': (window.__etubuLang || 'en'), 'User-Agent': 'Etubu/1.0 (com.etubu.app)' } });
            if (!res.ok) return '[]';
            var arr = await res.json();
            return JSON.stringify((arr || []).map(function(hit){
              return {
                id: 'nom-' + hit.place_id,
                label: hit.display_name || t,
                city: '',
                district: '',
                lat: Number(hit.lat),
                lng: Number(hit.lon),
                isMyLocation: false
              };
            }));
          } catch(e) { return '[]'; }
        })();
        """) { raw in
            DispatchQueue.main.async { completion(Self.parsePlaces(raw)) }
        }
    }

    /// True when `text` matches a city name with more than one district…
    /// Artık ilçe zorunlu değil — şehir merkezi / OSM resolve yeterli.
    static func needsDistrictPick(text: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { completion(false) }
    }

    private static func nativeNeedsDistrictFromCache(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count == 1 else { return false }
        let hits = EtubuTrafikAPI.searchPlaces(query: trimmed, limit: 80)
        guard !hits.isEmpty else { return nativeNeedsDistrictHeuristic(text) }
        // Exact district name alone (Çankaya) — no pick needed
        if hits.contains(where: {
            $0.districtName.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR")) == .orderedSame
        }) {
            return false
        }
        let cityRows = hits.filter {
            $0.cityName.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR")) == .orderedSame
        }
        if cityRows.count <= 1 { return false }
        if cityRows.contains(where: \.isMerkez) { return false }
        return true
    }

    /// Cap cold-start fallback — tek token büyükşehir adını ilçe ister.
    private static func nativeNeedsDistrictHeuristic(_ text: String) -> Bool {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr_TR"))
        guard !q.isEmpty else { return false }
        let tokens = q.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard tokens.count == 1 else { return false }
        let metros: Set<String> = [
            "istanbul", "ankara", "izmir", "bursa", "antalya", "adana", "konya",
            "gaziantep", "mersin", "kayseri", "eskişehir", "eskisehir", "diyarbakir",
            "diyarbakır", "samsun", "denizli", "sanliurfa", "şanlıurfa", "malatya",
            "erzurum", "van", "batman", "elazig", "elazığ", "manisa", "balikesir",
            "balıkesir", "kahramanmaras", "kahramanmaraş", "aydın", "aydin", "tekirdag",
            "tekirdağ", "sakarya", "mugla", "muğla", "trabzon", "ordu",
        ]
        return metros.contains(tokens[0])
    }

    /// Resolve typed text like web (Çorum→Merkez, Alaca→Çorum/Alaca). Falls back to Nominatim worldwide.
    static func resolve(text: String, completion: @escaping (EtubuRoutePlace?) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !EtubuRegion.lastKnownInTurkey {
            Task {
                let p = await nominatimResolveNative(trimmed)
                await MainActor.run { completion(p) }
            }
            return
        }
        if let native = resolveNative(trimmed) {
            DispatchQueue.main.async { completion(native) }
            return
        }

        let tJSON = jsStringLiteral(text)
        EtubuClusterAudioBridge.evalJSReturning("""
        (async function(){
          try {
            var t = \(tJSON);
            if (window.RouteGuard && window.RouteGuard.resolve) {
              var p = await window.RouteGuard.resolve(t);
              if (p) return JSON.stringify(p);
            }
            \(placeHelpersJS)
            var local = __etubuMapPlace(__etubuResolvePlace(t));
            if (local) return JSON.stringify(local);
            // Global geocode — OpenStreetMap Nominatim
            var url = 'https://nominatim.openstreetmap.org/search?format=json&limit=1&q=' + encodeURIComponent(t);
            var res = await fetch(url, { headers: { 'Accept-Language': (window.__etubuLang || 'en'), 'User-Agent': 'Etubu/1.0 (com.etubu.app)' } });
            if (!res.ok) return 'null';
            var arr = await res.json();
            if (!arr || !arr.length) return 'null';
            var hit = arr[0];
            return JSON.stringify({
              id: 'nom-' + hit.place_id,
              label: hit.display_name || t,
              city: hit.address && (hit.address.city || hit.address.town || hit.address.village) || '',
              district: hit.address && hit.address.suburb || '',
              lat: Number(hit.lat),
              lng: Number(hit.lon),
              isMyLocation: false
            });
          } catch(e) { return 'null'; }
        })();
        """) { raw in
            DispatchQueue.main.async {
                if raw == nil || raw == "null" {
                    completion(nil)
                    return
                }
                let body = raw!.trimmingCharacters(in: .whitespacesAndNewlines)
                if body.hasPrefix("{") {
                    completion(parsePlaces("[\(body)]").first)
                } else {
                    completion(parsePlaces(body).first)
                }
            }
        }
    }

    /// Prefer exact label / Merkez / single-hit from native index.
    /// Tek token şehir adı → Merkez veya ilk eşleşme (ilçe şartı yok).
    private static func resolveNative(_ text: String) -> EtubuRoutePlace? {
        let hits = EtubuTrafikAPI.searchPlaces(query: text, limit: 24)
        guard !hits.isEmpty else { return nil }
        let foldQ = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = hits.first(where: { $0.label.compare(text, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR")) == .orderedSame }) {
            return exact
        }
        if hits.count == 1 { return hits[0] }
        if let merkez = hits.first(where: { $0.isMerkez }) { return merkez }
        // "Ankara Çankaya" compound — top score already first
        if foldQ.contains(" ") { return hits.first }
        // Tek kelime şehir — Merkez yoksa ilk eşleşme (OSM yedek planNative’de)
        return hits.first
    }

    static func plan(
        from: String,
        to: String,
        toPlace: EtubuRoutePlace? = nil,
        fromVehicleNav: Bool = false,
        completion: ((Bool, String) -> Void)? = nil
    ) {
        if !fromVehicleNav {
            routeFromVehicleNav = false
            suppressVehicleNavAdaptUntil = nil
        }
        primeWarningAudio()
        EtubuDriveWarnings.armRouteHazardHook()
        EtubuMapLocationHelper.shared.startIfNeeded()
        // Seed Cap RouteGuard with native GPS before "Konumum" resolve.
        pushNativeLocationToWeb()
        let fromLabel = from.isEmpty ? EtubuClusterL10n.myLocation : from
        let toLabel = toPlace?.label ?? to
        // Native Trafik/OSRM — Cap WKWebView buildRoute beklemeden hızlı özet.
        // Polyline + radar hemen; şarj/hava arka planda; sonuç Cap'e inject edilir.
        planNative(from: fromLabel, to: toLabel, toPlace: toPlace, completion: { ok, msg in
            if ok {
                routeFromVehicleNav = fromVehicleNav
                EtubuMapLocationHelper.shared.enableBackgroundForRouteIfNeeded()
            }
            completion?(ok, msg)
        })
        EtubuCapBridgeViewController.armWebContent()
    }

    /// Tesla aktif navigasyonu → uygulama rota hattı (EGM/OSM uyarıları).
    /// Kullanıcı app içinde rota kurduysa dokunma; temizlediyse kısa süre bastır.
    /// Premium gate: aynı `openRouteOrPaywall` felsefesi — free dial/OSM hız; rota+radar yok.
    @MainActor
    static func adaptVehicleNavIfNeeded(
        destination: String?,
        remainKm: Double?,
        etaMinutes: Double?,
        destLat: Double? = nil,
        destLng: Double? = nil
    ) {
        let dest = (destination ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard dest.count >= 2 else { return }
        // Free: telemetride hedef etiketi kalabilir; plan/hazard stack Premium.
        guard EtubuPremiumManager.shared.isPremium else { return }

        let t = EtubuVehicleTelemetry.shared
        // Kullanıcı app rotası — araç nav ile ezme.
        if t.routeActive, !routeFromVehicleNav { return }
        if let until = suppressVehicleNavAdaptUntil, Date() < until { return }

        // UI’yi hemen güncelle.
        t.navDestination = dest
        t.routeTo = dest
        if let remainKm, remainKm > 0 {
            t.applyCapRouteRemain(active: true, remainKm: remainKm)
        }
        if let etaMinutes, etaMinutes >= 0 {
            t.navEtaMinutes = etaMinutes
        }

        // Aynı hedef — kalan mesafe güncelle + arka planda hazard yenile (radar bayatlamasın).
        let key = dest.lowercased()
        if t.routeActive, routeFromVehicleNav, key == lastVehicleNavDestKey {
            enrichActiveRouteFromNativeIfNeeded()
            Task { @MainActor in
                EtubuDriveWarnings.shared.startPolling()
            }
            return
        }

        // Resolve coordinates: Tesla route pin → Home/Work saved pins → geocode.
        // Never invent Home/Work via Nominatim (wrong cities).
        let coordPlace: EtubuRoutePlace? = {
            if let destLat, let destLng,
               destLat.isFinite, destLng.isFinite,
               abs(destLat) > 0.01 || abs(destLng) > 0.01 {
                return EtubuRoutePlace(
                    label: dest,
                    cityName: "",
                    districtName: "",
                    isMyLocation: false,
                    lat: destLat,
                    lng: destLng
                )
            }
            if let pin = EtubuVehicleTelemetry.savedPin(for: dest) {
                return EtubuRoutePlace(
                    label: dest,
                    cityName: "",
                    districtName: "",
                    isMyLocation: false,
                    lat: pin.lat,
                    lng: pin.lng
                )
            }
            return nil
        }()

        if isAmbiguousVehicleDest(dest), coordPlace == nil {
            // Label + remain only — do not plan garbage Home/Work routes.
            return
        }

        vehicleNavAdaptWork?.cancel()
        let work = DispatchWorkItem {
            lastVehicleNavDestKey = key
            if let place = coordPlace {
                plan(from: "Konumum", to: dest, toPlace: place, fromVehicleNav: true) { ok, _ in
                    if ok {
                        Task { @MainActor in
                            EtubuVehicleTelemetry.shared.routeActive = true
                            EtubuVehicleTelemetry.shared.routeTo = dest
                            EtubuVehicleTelemetry.shared.navDestination = dest
                            EtubuVehicleTelemetry.shared.routeDestLat = place.lat
                            EtubuVehicleTelemetry.shared.routeDestLng = place.lng
                            EtubuDriveWarnings.shared.startPolling()
                            EtubuMapLocationHelper.shared.enableBackgroundForRouteIfNeeded()
                            enrichActiveRouteFromNativeIfNeeded()
                        }
                    }
                }
                return
            }
            // Named place (not Home/Work) — geocode; drop if resolve fails.
            resolve(text: dest) { place in
                guard let place, place.lat != nil, place.lng != nil else { return }
                // Reject geocode that looks like a wrong Home/Work substitute.
                if isAmbiguousVehicleDest(dest) { return }
                plan(from: "Konumum", to: dest, toPlace: place, fromVehicleNav: true) { ok, _ in
                    if ok {
                        Task { @MainActor in
                            EtubuVehicleTelemetry.shared.routeActive = true
                            EtubuVehicleTelemetry.shared.routeTo = dest
                            EtubuVehicleTelemetry.shared.navDestination = dest
                            EtubuDriveWarnings.shared.startPolling()
                            EtubuMapLocationHelper.shared.enableBackgroundForRouteIfNeeded()
                            enrichActiveRouteFromNativeIfNeeded()
                        }
                    }
                }
            }
        }
        vehicleNavAdaptWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// Tesla "Home"/"Work"/localized favorites — must not Nominatim to random cities.
    private static func isAmbiguousVehicleDest(_ dest: String) -> Bool {
        let fold = dest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ambiguous: Set<String> = [
            "home", "work", "ev", "iş", "is", "office",
            "casa", "maison", "zuhause", "arbeit", "travail",
            "oficina", "家", "仕事", "my home", "my work",
        ]
        return ambiguous.contains(fold)
    }

    /// If Cap RouteGuard left hazards empty (Radars[] often blank), fill from native enrichers.
    private static func enrichActiveRouteFromNativeIfNeeded() {
        Task {
            let existing = await MainActor.run { EtubuDriveWarnings.shared.hazards }
            let coordsCL = await MainActor.run { EtubuDriveWarnings.shared.routeCoords }
            var latLng: [(lat: Double, lng: Double)] = coordsCL.map { ($0.latitude, $0.longitude) }
            if latLng.count < 2 {
                // Try Cap stash
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    EtubuClusterAudioBridge.evalJSReturning("""
                    (function(){
                      try {
                        var c = (window.__etubuRouteState && window.__etubuRouteState.coords) || [];
                        return JSON.stringify(c.map(function(p){ return {lat:+p.lat, lng:+p.lng}; }));
                      } catch(e) { return '[]'; }
                    })();
                    """) { raw in
                        if let raw, let data = raw.data(using: .utf8),
                           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                            latLng = arr.compactMap { row in
                                let lat = (row["lat"] as? NSNumber)?.doubleValue ?? (row["lat"] as? Double)
                                let lng = (row["lng"] as? NSNumber)?.doubleValue ?? (row["lng"] as? Double)
                                guard let lat, let lng else { return nil }
                                return (lat, lng)
                            }
                        }
                        cont.resume()
                    }
                }
            }
            guard latLng.count >= 2 else { return }

            let hasCharge = existing.contains { $0.kind == "charge" }
            let hasWeather = existing.contains { $0.kind == "weather" }

            var merged = existing
            let inTR = latLng.contains { EtubuRegion.inTurkeyBounds(lat: $0.lat, lng: $0.lng) }
            // Always append TR seed hazards on Turkey routes when enriching.
            if inTR {
                merged.append(contentsOf: EtubuTrafikAPI.parseOfficialHazards(
                    data: [:], coords: latLng, includeSeeds: true
                ))
            }
            // OSM cameras: led outside TR / empty EGM; supplement inside TR (no cut of official).
            async let osmTask = EtubuTrafikAPI.fetchOsmCamerasAlong(coords: latLng)
            async let chargeTask: [EtubuRouteHazard] = hasCharge
                ? []
                : EtubuTrafikAPI.fetchChargersAlong(coords: latLng)
            async let weatherTask: [EtubuRouteHazard] = hasWeather
                ? []
                : EtubuTrafikAPI.fetchWeatherAlong(coords: latLng)
            let (osmCams, chargeHaz, wxHaz) = await (osmTask, chargeTask, weatherTask)
            let officialPart = merged.filter { !EtubuHazardMerge.isOsmSource($0) }
            let priorOsm = merged.filter { EtubuHazardMerge.isOsmSource($0) }
            merged = EtubuTrafikAPI.mergeOfficialWithOsm(
                official: officialPart,
                osm: priorOsm + osmCams,
                inTurkey: inTR
            )
            merged.append(contentsOf: chargeHaz)
            merged.append(contentsOf: wxHaz)
            merged = EtubuHazardMerge.dedupePreferOfficial(merged)
            merged.sort { ($0.routeIdx ?? 0) < ($1.routeIdx ?? 0) }
            guard merged.count > existing.count || !merged.isEmpty else { return }

            let brief = EtubuRouteBriefSummary(
                radarCount: merged.filter { $0.kind == "radar" }.count,
                controlCount: merged.filter { $0.kind == "control" }.count,
                corridorCount: merged.filter { $0.kind == "corridor" }.count,
                chargeCount: merged.filter { $0.kind == "charge" }.count,
                weatherCount: merged.filter { $0.kind == "weather" }.count,
                chargeNames: merged.filter { $0.kind == "charge" }.prefix(4).map(\.label),
                weatherLabels: merged.filter { $0.kind == "weather" }.prefix(4).map(\.label)
            )
            await MainActor.run {
                let w = EtubuDriveWarnings.shared
                w.hazards = merged
                w.remainingHazards = merged
                if !w.brief.hasAny || w.brief.chargeCount == 0 || w.brief.weatherCount == 0 {
                    w.brief = brief
                    w.remainingBrief = brief
                }
                if w.routeCoords.isEmpty {
                    w.routeCoords = latLng.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                }
                w.startPolling()
            }
        }
    }

    /// Vehicle >600 m from polyline — rebuild from current GPS to same destination; refresh EGM+OSM.
    @MainActor
    static func replanActiveRouteFromCurrentLocation(reason: String) {
        guard EtubuPremiumManager.shared.isPremium else { return }
        let t = EtubuVehicleTelemetry.shared
        guard t.routeActive else { return }
        let dest = t.routeTo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard dest.count >= 2 else { return }
        let fromLabel = EtubuClusterL10n.myLocation
        plan(from: fromLabel, to: dest, toPlace: nil, fromVehicleNav: routeFromVehicleNav) { ok, _ in
            if ok {
                Task { @MainActor in
                    enrichActiveRouteFromNativeIfNeeded()
                    EtubuDriveWarnings.shared.startPolling()
                    _ = reason // keep call-site reason for future diagnostics
                }
            }
        }
    }

    /// Cap-independent route build: TR → EGM+OSRM; yurt dışı → yalnızca OSM/OSRM + Overpass uyarıları.
    private static func planNative(
        from: String,
        to: String,
        toPlace hintPlace: EtubuRoutePlace? = nil,
        completion: ((Bool, String) -> Void)?
    ) {
        Task {
            var toPlace: EtubuRoutePlace? = {
                if let p = hintPlace, p.lat != nil, p.lng != nil { return p }
                if let p = resolveNative(to) { return p }
                let hits = EtubuTrafikAPI.searchPlaces(query: to, limit: 8)
                return hits.first
            }()
            if toPlace?.lat == nil || toPlace?.lng == nil {
                toPlace = await nominatimResolveNative(to) ?? toPlace
            }
            guard let toPlace, let toLat = toPlace.lat, let toLng = toPlace.lng else {
                await MainActor.run {
                    completion?(false, String(format: EtubuClusterL10n.t("routePlaceNotFoundFmt"), to))
                }
                return
            }

            let fromIsMine = {
                let f = from.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return f.isEmpty || f == "konumum" || f == "my location" || f.contains("konum")
                    || f == "mylocation" || f == "location"
            }()

            var fromLat: Double?
            var fromLng: Double?
            var fromDistrictId = ""
            var fromResolvedLabel = from

            if fromIsMine {
                let t = EtubuVehicleTelemetry.shared
                fromLat = t.latitude
                fromLng = t.longitude
                fromResolvedLabel = EtubuClusterL10n.myLocation
                if fromLat == nil || fromLng == nil {
                    await MainActor.run {
                        completion?(false, EtubuClusterL10n.t("routeNeedLocation"))
                    }
                    return
                }
                if let near = EtubuTrafikAPI.nearestPlace(lat: fromLat!, lng: fromLng!) {
                    fromDistrictId = near.districtId
                }
            } else if let fp = resolveNative(from) ?? EtubuTrafikAPI.searchPlaces(query: from, limit: 8).first,
                      let la = fp.lat, let ln = fp.lng {
                fromLat = la
                fromLng = ln
                fromResolvedLabel = fp.label
                fromDistrictId = fp.districtId
            } else if let fp = await nominatimResolveNative(from), let la = fp.lat, let ln = fp.lng {
                fromLat = la
                fromLng = ln
                fromResolvedLabel = fp.label
            } else {
                await MainActor.run {
                    completion?(false, String(format: EtubuClusterL10n.t("routePlaceNotFoundFmt"), from))
                }
                return
            }

            guard let fLat = fromLat, let fLng = fromLng else {
                await MainActor.run { completion?(false, EtubuClusterL10n.t("routeLocFailed")) }
                return
            }

            EtubuRegion.updateFrom(lat: fLat, lng: fLng)

            let domestic = EtubuRegion.inTurkeyBounds(lat: fLat, lng: fLng)
                && EtubuRegion.inTurkeyBounds(lat: toLat, lng: toLng)

            var toDistrictId = toPlace.districtId
            if domestic {
                if toDistrictId.isEmpty,
                   let nearTo = EtubuTrafikAPI.nearestPlace(lat: toLat, lng: toLng) {
                    toDistrictId = nearTo.districtId
                }
                if fromDistrictId.isEmpty {
                    fromDistrictId = toDistrictId.isEmpty ? "0" : toDistrictId
                }
            }

            var coords: [[String: Double]] = []
            var navOnly = false
            var routeData: [String: Any]?
            var statusNote = ""

            // Yurt dışı / uluslararası: EGM atla — doğrudan OSRM (OSM).
            if domestic {
                do {
                    let body: [String: Any] = [
                        "action": "createRoute",
                        "fromLatitude": String(fLat),
                        "fromLongitude": String(fLng),
                        "toLatitude": String(toLat),
                        "toLongitude": String(toLng),
                        "fromDistrictId": fromDistrictId,
                        "toDistrictId": toDistrictId,
                        "fromLabel": fromResolvedLabel,
                        "toLabel": toPlace.label,
                    ]
                    let json = try await EtubuTrafikAPI.postCreateRoute(body: body)
                    if let data = json["data"] as? [String: Any],
                       let arr = data["Coordinates"] as? [[String: Any]], !arr.isEmpty {
                        coords = arr.compactMap { row in
                            let x = (row["x"] as? NSNumber)?.doubleValue ?? (row["x"] as? Double)
                            let y = (row["y"] as? NSNumber)?.doubleValue ?? (row["y"] as? Double)
                            guard let x, let y else { return nil }
                            return ["x": x, "y": y]
                        }
                        routeData = data
                        statusNote = "\(fromResolvedLabel) → \(toPlace.label)"
                    }
                } catch {
                    // Fall through to OSRM
                }
            }

            if coords.count < 2 {
                do {
                    coords = try await fetchOsrmCoordinates(fromLat: fLat, fromLng: fLng, toLat: toLat, toLng: toLng)
                    navOnly = true
                    statusNote = domestic
                        ? EtubuClusterL10n.t("routeDrawnOsrm")
                        : String(format: EtubuClusterL10n.t("routeArrowOsmFmt"), fromResolvedLabel, toPlace.label)
                } catch {
                    await MainActor.run {
                        completion?(false, EtubuClusterL10n.t("routePlanNetworkFail"))
                    }
                    return
                }
            }

            let latLngCoords: [(lat: Double, lng: Double)] = coords.compactMap { row in
                guard let x = row["x"], let y = row["y"] else { return nil }
                return (lat: y, lng: x)
            }

            var hazards: [EtubuRouteHazard] = []
            if domestic {
                if let data = routeData {
                    hazards = EtubuTrafikAPI.parseOfficialHazards(
                        data: data, coords: latLngCoords, includeSeeds: true
                    )
                } else {
                    hazards = EtubuTrafikAPI.parseOfficialHazards(
                        data: [:], coords: latLngCoords, includeSeeds: true
                    )
                }
            } else {
                hazards = []
            }

            // OSM: led outside TR / empty EGM; supplement in TR (official wins on conflict).
            async let osmEarly = EtubuTrafikAPI.fetchOsmCamerasAlong(coords: latLngCoords)
            let osmFirst = await osmEarly
            hazards = EtubuTrafikAPI.mergeOfficialWithOsm(
                official: hazards,
                osm: osmFirst,
                inTurkey: domestic
            )

            let remainKm: Double = {
                guard latLngCoords.count >= 2 else { return 0 }
                var sum: Double = 0
                for i in 1..<latLngCoords.count {
                    sum += EtubuTrafikAPI.haversineKm(
                        latLngCoords[i - 1].lat, latLngCoords[i - 1].lng,
                        latLngCoords[i].lat, latLngCoords[i].lng
                    )
                }
                return sum
            }()

            // Hızlı UI: önce rota + radar/koridor; şarj/hava arka planda.
            let quickBrief = EtubuRouteBriefSummary(
                radarCount: hazards.filter { $0.kind == "radar" }.count,
                controlCount: (routeData?["ControlPointCount"] as? NSNumber)?.intValue
                    ?? (routeData?["ControlPointCount"] as? Int)
                    ?? hazards.filter { $0.kind == "control" }.count,
                corridorCount: hazards.filter { $0.kind == "corridor" }.count,
                chargeCount: 0,
                weatherCount: 0
            )

            await MainActor.run {
                let t = EtubuVehicleTelemetry.shared
                t.routeActive = true
                t.routeFrom = fromResolvedLabel
                t.routeTo = toPlace.label
                t.navDestination = toPlace.label
                t.routeDestLat = toLat
                t.routeDestLng = toLng
                t.applyCapRouteRemain(active: true, remainKm: remainKm > 0 ? remainKm : nil)
                EtubuEvRoutePlanner.shared.refreshFromLiveState()

                let w = EtubuDriveWarnings.shared
                w.hazards = hazards
                w.remainingHazards = hazards
                w.brief = quickBrief
                w.remainingBrief = quickBrief
                w.routeCoords = latLngCoords.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
                }
                w.startPolling()

                injectNativeRouteIntoCap(
                    fromLabel: fromResolvedLabel,
                    toLabel: toPlace.label,
                    coords: coords,
                    hazards: hazards,
                    navOnly: navOnly || !domestic,
                    brief: quickBrief
                )

                let radarN = quickBrief.radarCount
                let corridorN = quickBrief.corridorCount
                let msg: String
                if !domestic {
                    msg = String(
                        format: EtubuClusterL10n.t("routeOverseasBriefFmt"),
                        statusNote, radarN, corridorN
                    )
                } else if hazards.isEmpty && navOnly {
                    msg = statusNote.isEmpty
                        ? EtubuClusterL10n.t("routeDrawnNoWarn")
                        : String(format: EtubuClusterL10n.t("routeWarnLimitedFmt"), statusNote)
                } else {
                    msg = String(format: EtubuClusterL10n.t("routeActiveBriefFmt"), radarN, corridorN)
                }
                completion?(true, msg)
            }

            // Şarj + hava — UI’yi bekletmeden zenginleştir (OSM already merged above).
            async let charges = EtubuTrafikAPI.fetchChargersAlong(coords: latLngCoords)
            async let weather = EtubuTrafikAPI.fetchWeatherAlong(coords: latLngCoords)
            let (chargeHaz, wxHaz) = await (charges, weather)
            guard !chargeHaz.isEmpty || !wxHaz.isEmpty else { return }

            await MainActor.run {
                let w = EtubuDriveWarnings.shared
                var merged = w.hazards
                merged.append(contentsOf: chargeHaz)
                merged.append(contentsOf: wxHaz)
                var seen = Set<String>()
                merged = merged.filter { seen.insert($0.id).inserted }
                merged.sort { ($0.routeIdx ?? 0) < ($1.routeIdx ?? 0) }
                let brief = EtubuRouteBriefSummary(
                    radarCount: merged.filter { $0.kind == "radar" }.count,
                    controlCount: merged.filter { $0.kind == "control" }.count,
                    corridorCount: merged.filter { $0.kind == "corridor" }.count,
                    chargeCount: merged.filter { $0.kind == "charge" }.count,
                    weatherCount: merged.filter { $0.kind == "weather" }.count,
                    chargeNames: merged.filter { $0.kind == "charge" }.prefix(4).map(\.label),
                    weatherLabels: merged.filter { $0.kind == "weather" }.prefix(4).map(\.label)
                )
                w.hazards = merged
                w.remainingHazards = merged
                w.brief = brief
                w.remainingBrief = brief
                injectNativeRouteIntoCap(
                    fromLabel: fromResolvedLabel,
                    toLabel: toPlace.label,
                    coords: coords,
                    hazards: merged,
                    navOnly: navOnly || !domestic,
                    brief: brief
                )
            }
        }
    }

    /// Nominatim (OSM) — Cap WebView’e ihtiyaç duymadan destinasyon çözümü.
    private static func nominatimResolveNative(_ query: String) async -> EtubuRoutePlace? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return nil }
        var comps = URLComponents(string: "https://nominatim.openstreetmap.org/search")
        comps?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "q", value: q),
        ]
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Etubu/1.0 (com.etubu.app)", forHTTPHeaderField: "User-Agent")
        req.setValue(EtubuAppLanguage.current.rawValue, forHTTPHeaderField: "Accept-Language")
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let hit = arr.first
            else { return nil }
            let lat = (hit["lat"] as? NSNumber)?.doubleValue
                ?? Double(hit["lat"] as? String ?? "")
            let lon = (hit["lon"] as? NSNumber)?.doubleValue
                ?? Double(hit["lon"] as? String ?? "")
            guard let lat, let lon else { return nil }
            let label = (hit["display_name"] as? String) ?? q
            return EtubuRoutePlace(
                label: label,
                cityName: "",
                districtName: "",
                isMyLocation: false,
                lat: lat,
                lng: lon,
                districtId: ""
            )
        } catch {
            return nil
        }
    }

    private static func fetchOsrmCoordinates(
        fromLat: Double, fromLng: Double, toLat: Double, toLng: Double
    ) async throws -> [[String: Double]] {
        let urlStr =
            "https://router.project-osrm.org/route/v1/driving/"
            + "\(fromLng),\(fromLat);\(toLng),\(toLat)"
            + "?overview=full&geometries=geojson"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Etubu/1.0 (com.etubu.app)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 18
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["code"] as? String) == "Ok",
              let routes = json["routes"] as? [[String: Any]],
              let geom = routes.first?["geometry"] as? [String: Any],
              let pairs = geom["coordinates"] as? [[Double]], pairs.count >= 2
        else { throw URLError(.cannotParseResponse) }
        return pairs.map { pair in
            ["x": pair[0], "y": pair[1]]
        }
    }

    private static func injectNativeRouteIntoCap(
        fromLabel: String,
        toLabel: String,
        coords: [[String: Double]],
        hazards: [EtubuRouteHazard],
        navOnly: Bool,
        brief: EtubuRouteBriefSummary
    ) {
        guard let coordsData = try? JSONSerialization.data(withJSONObject: coords),
              let coordsJSON = String(data: coordsData, encoding: .utf8) else { return }
        let hazardPayload: [[String: Any]] = hazards.map { h in
            var row: [String: Any] = [
                "id": h.id,
                "kind": h.kind,
                "label": h.label,
                "lat": h.lat,
                "lng": h.lng,
            ]
            if let ms = h.maxspeed { row["maxspeed"] = ms }
            if let kw = h.kw { row["kw"] = kw }
            if let idx = h.routeIdx { row["routeIdx"] = idx }
            if let along = h.alongKm { row["alongKm"] = along }
            return row
        }
        guard let hazData = try? JSONSerialization.data(withJSONObject: hazardPayload),
              let hazJSON = String(data: hazData, encoding: .utf8) else { return }
        let fromJS = jsStringLiteral(fromLabel)
        let toJS = jsStringLiteral(toLabel)
        EtubuClusterAudioBridge.evalJS("""
        (function(){
          try {
            window.__ETUBU_GPS_ARMED__ = true;
            var forceTr = \(EtubuRegion.lastKnownInTurkey ? "1" : "0");
            localStorage.setItem('etubu_force_tr_route', forceTr);
            sessionStorage.setItem('etubu_force_tr_route', forceTr);
            window.__etubuForceTrRoute = +forceTr;
            window.__etubuRouteState = window.__etubuRouteState || { hazards: [], coords: [], at: 0 };
            window.__etubuRouteState.coords = (\(coordsJSON)).map(function(p){
              return { lng: +p.x, lat: +p.y };
            });
            window.__etubuRouteState.hazards = \(hazJSON);
            window.__etubuRouteState.at = Date.now();
            window.__etubuLastPlanMeta = {
              navOnly: \(navOnly ? "true" : "false"),
              from: \(fromJS),
              to: \(toJS),
              radar: \(brief.radarCount),
              corridor: \(brief.corridorCount),
              charge: \(brief.chargeCount),
              weather: \(brief.weatherCount),
              control: \(brief.controlCount)
            };
            var from = document.getElementById('routeFromInput');
            var to = document.getElementById('routeToInput');
            if (from) from.value = \(fromJS);
            if (to) to.value = \(toJS);
            if (typeof MiniMap !== 'undefined' && MiniMap.setRoute) {
              MiniMap.setRoute(
                window.__etubuRouteState.coords.map(function(p){ return [p.lng, p.lat]; }),
                window.__etubuRouteState.hazards
              );
            } else if (typeof MiniMap !== 'undefined' && MiniMap.setHazards) {
              MiniMap.setHazards(window.__etubuRouteState.hazards);
            }
            // RouteGuard dahili hazards/active — Cap listAhead / TTS / warn-reel native ile aynı.
            if (window.RouteGuard && typeof window.RouteGuard.applyNativeRoute === 'function') {
              window.RouteGuard.applyNativeRoute({
                from: \(fromJS),
                to: \(toJS),
                coords: window.__etubuRouteState.coords,
                hazards: window.__etubuRouteState.hazards,
                navOnly: \(navOnly ? "true" : "false"),
                brief: {
                  radar: \(brief.radarCount),
                  corridor: \(brief.corridorCount),
                  charge: \(brief.chargeCount),
                  weather: \(brief.weatherCount),
                  control: \(brief.controlCount)
                }
              });
            }
          } catch (e) {}
        })();
        """)
    }

    private static func pollPlanReady(attemptsLeft: Int, delay: Double = 0.15, completion: ((Bool, String) -> Void)?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            status { st in
                // Aktif rota yeter — brief/enrich arka planda tamamlanır.
                if st.active {
                    let msg: String
                    if st.navOnly {
                        msg = EtubuClusterL10n.t("routeDrawnOsrmNoEgm")
                    } else if st.brief.hasAny || st.hazardCount > 0 {
                        msg = String(
                            format: EtubuClusterL10n.t("routeActiveFullFmt"),
                            st.brief.radarCount, st.brief.corridorCount,
                            st.brief.chargeCount, st.brief.weatherCount
                        )
                    } else {
                        msg = st.statusText.isEmpty ? EtubuClusterL10n.t("routeActiveShort") : st.statusText
                    }
                    completion?(true, msg)
                    return
                }
                if attemptsLeft <= 0 {
                    completion?(st.active, st.statusText.isEmpty ? (st.active ? EtubuClusterL10n.t("routeActiveShort") : EtubuClusterL10n.t("routeFailedShort")) : st.statusText)
                    return
                }
                let fail = st.statusText.lowercased()
                if !st.statusText.isEmpty,
                   fail.contains("fail") || fail.contains("hata") || fail.contains("bulunamad") {
                    completion?(false, st.statusText)
                    return
                }
                let nextDelay = min(0.35, delay + 0.05)
                pollPlanReady(attemptsLeft: attemptsLeft - 1, delay: nextDelay, completion: completion)
            }
        }
    }

    static func clear() {
        vehicleNavAdaptWork?.cancel()
        vehicleNavAdaptWork = nil
        routeFromVehicleNav = false
        lastVehicleNavDestKey = ""
        suppressVehicleNavAdaptUntil = Date().addingTimeInterval(90)
        EtubuClusterAudioBridge.evalJS("""
        (function(){
          try {
            if (window.RouteGuard && window.RouteGuard.clear) window.RouteGuard.clear();
            document.getElementById('routeClearBtn')?.click?.();
            var from = document.getElementById('routeFromInput');
            if (from) from.value = 'Konumum';
            if (window.__etubuRouteState) {
              window.__etubuRouteState.hazards = [];
              window.__etubuRouteState.coords = [];
            }
          } catch (e) {}
        })();
        """)
        Task { @MainActor in
            let t = EtubuVehicleTelemetry.shared
            t.routeActive = false
            t.routeTo = ""
            t.routeFrom = ""
            t.routeDestLat = nil
            t.routeDestLng = nil
            t.capRouteRemainKm = nil
            t.refreshEnergyPlan()
            EtubuDriveWarnings.shared.clearCriticalAlerts()
            EtubuMapLocationHelper.shared.disableBackgroundUpdates()
        }
    }

    /// Hedef koordinatı oku (Maps handoff).
    static func readDestinationCoordinate(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        EtubuClusterAudioBridge.evalJSReturning("""
        (function(){
          try {
            var saved = JSON.parse(sessionStorage.getItem('etubu_route_last') || localStorage.getItem('etubu_route_last') || '{}');
            if (saved && saved.to && typeof saved.to.lat === 'number' && typeof saved.to.lng === 'number') {
              return JSON.stringify({ lat: saved.to.lat, lng: saved.to.lng });
            }
            var coords = (window.__etubuRouteState && window.__etubuRouteState.coords) || [];
            if (coords.length) {
              var last = coords[coords.length - 1];
              return JSON.stringify({ lat: last.lat, lng: last.lng });
            }
            return 'null';
          } catch(e) { return 'null'; }
        })();
        """) { raw in
            DispatchQueue.main.async {
                guard let raw, raw != "null",
                      let data = raw.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let lat = json["lat"] as? Double ?? (json["lat"] as? NSNumber)?.doubleValue,
                      let lng = json["lng"] as? Double ?? (json["lng"] as? NSNumber)?.doubleValue
                else {
                    completion(nil)
                    return
                }
                completion(CLLocationCoordinate2D(latitude: lat, longitude: lng))
            }
        }
    }

    static func openInMaps(destinationName: String) {
        readDestinationCoordinate { coord in
            Task { @MainActor in
                let name = destinationName.isEmpty ? "Etubu rota" : destinationName
                let resolved = coord ?? {
                    if let lat = EtubuVehicleTelemetry.shared.routeDestLat,
                       let lng = EtubuVehicleTelemetry.shared.routeDestLng {
                        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    }
                    return nil
                }()
                openCoordinateInMaps(resolved, name: name)
            }
        }
    }

    /// Şarj önerisi / Haritada aç (şarj): en yakın şarj istasyonu.
    static func openNearestChargeInMaps() {
        Task { @MainActor in
            if openNearestChargeStopIfAvailable() { return }
            openCoordinateInMaps(nil, name: EtubuClusterL10n.t("warnKindCharge"))
        }
    }

    /// Önerilen / rota üzerindeki en yakın şarj (alongKm veya kullanıcıya mesafe).
    @MainActor
    @discardableResult
    static func openNearestChargeStopIfAvailable() -> Bool {
        let planner = EtubuEvRoutePlanner.shared
        let warnings = EtubuDriveWarnings.shared
        let candidates: [EtubuRouteHazard] = {
            if !planner.suggestedStops.isEmpty { return planner.suggestedStops }
            let pool = warnings.remainingHazards.isEmpty ? warnings.hazards : warnings.remainingHazards
            return pool.filter { $0.kind == "charge" }
        }()
        guard !candidates.isEmpty else { return false }
        let t = EtubuVehicleTelemetry.shared
        let nearest: EtubuRouteHazard = {
            if let lat = t.latitude, let lng = t.longitude {
                return candidates.min(by: { a, b in
                    haversineKm(lat, lng, a.lat, a.lng) < haversineKm(lat, lng, b.lat, b.lng)
                }) ?? candidates[0]
            }
            return candidates.sorted { ($0.alongKm ?? 1e9) < ($1.alongKm ?? 1e9) }.first ?? candidates[0]
        }()
        openChargeStop(nearest)
        return true
    }

    @MainActor
    static func openChargeStop(_ stop: EtubuRouteHazard) {
        let name = stop.label.isEmpty ? EtubuClusterL10n.t("warnKindCharge") : stop.label
        let coord = CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng)
        guard CLLocationCoordinate2DIsValid(coord),
              abs(stop.lat) > 0.01 || abs(stop.lng) > 0.01 else {
            openCoordinateInMaps(nil, name: name)
            return
        }
        openCoordinateInMaps(coord, name: name)
    }

    private static func openCoordinateInMaps(_ coord: CLLocationCoordinate2D?, name: String) {
        Task { @MainActor in
            if let coord {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                item.name = name
                item.openInMaps(launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                ])
            } else if let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: "http://maps.apple.com/?daddr=\(encoded)") {
                UIApplication.shared.open(url)
            }
        }
    }

    private static func haversineKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }

    static func status(completion: @escaping (EtubuRouteStatus) -> Void) {
        EtubuClusterAudioBridge.evalJSReturning("""
        (function(){
          try {
            \(placeHelpersJS)
            var active = !!(window.RouteGuard && window.RouteGuard.isActive && window.RouteGuard.isActive());
            var from = (document.getElementById('routeFromInput')?.value) || '';
            var to = (document.getElementById('routeToInput')?.value) || '';
            var status = (document.getElementById('routeStatus')?.textContent || '').trim();
            var briefText = (document.getElementById('routeBriefTop')?.innerText || '').trim().slice(0, 220);
            try {
              var saved = JSON.parse(localStorage.getItem('etubu_route_last') || '{}');
              if (saved.fromLabel) from = saved.fromLabel;
              if (saved.toLabel) to = saved.toLabel;
            } catch (e) {}
            var brief = { radar: 0, control: 0, corridor: 0, charge: 0, weather: 0, chargeNames: [], weatherLabels: [] };
            // Native plan fallback — Cap RouteGuard may be absent but coords/meta were injected.
            try {
              var meta = window.__etubuLastPlanMeta || {};
              var stCoords = (window.__etubuRouteState && window.__etubuRouteState.coords) || [];
              if (!active && stCoords.length >= 2) {
                active = true;
                if (meta.from) from = meta.from;
                if (meta.to) to = meta.to;
              }
              if (meta.radar) brief.radar = +meta.radar || 0;
              if (meta.corridor) brief.corridor = +meta.corridor || 0;
              if (meta.charge) brief.charge = +meta.charge || 0;
              if (meta.weather) brief.weather = +meta.weather || 0;
              if (meta.control) brief.control = +meta.control || 0;
            } catch (eN) {}
            var cardsEl = document.querySelectorAll('.route-brief-cards > div');
            if (cardsEl && cardsEl.length >= 5) {
              function num(el){ var em = el && el.querySelector('em'); return em ? parseInt(em.textContent, 10) || 0 : 0; }
              var domRadar = num(cardsEl[0]), domControl = num(cardsEl[1]), domCorridor = num(cardsEl[2]);
              var domCharge = num(cardsEl[3]), domWeather = num(cardsEl[4]);
              if (domRadar || domControl || domCorridor || domCharge || domWeather) {
                brief.radar = domRadar;
                brief.control = domControl;
                brief.corridor = domCorridor;
                brief.charge = domCharge;
                brief.weather = domWeather;
              }
            }
            var chargeBlock = document.querySelector('.route-brief-charge span');
            if (chargeBlock && chargeBlock.textContent) {
              brief.chargeNames = chargeBlock.textContent.split('·').map(function(s){ return s.trim(); }).filter(Boolean).slice(0, 4);
            }
            var wxBlock = document.querySelector('.route-brief-weather span');
            if (wxBlock && wxBlock.textContent) {
              brief.weatherLabels = wxBlock.textContent.split('·').map(function(s){ return s.trim(); }).filter(Boolean).slice(0, 4);
            }
            var hazards = (window.__etubuRouteState && window.__etubuRouteState.hazards) || [];
            var coords = (window.__etubuRouteState && window.__etubuRouteState.coords) || [];
            function alongKmForIdx(idx) {
              if (!coords.length || idx <= 0) return 0;
              var sum = 0;
              var n = Math.min(idx, coords.length - 1);
              for (var i = 1; i <= n; i++) {
                var a = coords[i-1], b = coords[i];
                var dLat = (b.lat - a.lat) * Math.PI/180;
                var dLon = (b.lng - a.lng) * Math.PI/180;
                var aa = Math.sin(dLat/2)*Math.sin(dLat/2) +
                  Math.cos(a.lat*Math.PI/180)*Math.cos(b.lat*Math.PI/180)*Math.sin(dLon/2)*Math.sin(dLon/2);
                sum += 2*6371000*Math.asin(Math.sqrt(aa));
              }
              return Math.round(sum / 100) / 10;
            }
            if ((!brief.radar && !brief.corridor && !brief.charge && !brief.weather) && hazards.length) {
              hazards.forEach(function(h){
                if (h.kind === 'corridor') brief.corridor++;
                else if (h.kind === 'charge') { brief.charge++; if (h.label && brief.chargeNames.length < 4) brief.chargeNames.push(h.label); }
                else if (h.kind === 'weather') { brief.weather++; if (h.label && brief.weatherLabels.length < 4) brief.weatherLabels.push(h.label); }
                else if (h.kind === 'control') brief.control++;
                else brief.radar++;
              });
            }
            var details = hazards.slice().sort(function(a,b){
              var ia = a.routeIdx != null ? +a.routeIdx : 1e9;
              var ib = b.routeIdx != null ? +b.routeIdx : 1e9;
              return ia - ib;
            }).slice(0, 80).map(function(h, i){
              var idx = h.routeIdx != null ? +h.routeIdx : null;
              var along = h.alongKm != null ? +h.alongKm : (idx != null ? alongKmForIdx(idx) : null);
              return {
                id: h.id || ((h.kind||'radar') + '-' + h.lat + ',' + h.lng + '-' + i),
                kind: h.kind || 'radar',
                label: h.label || h.name || '',
                lat: +h.lat, lng: +h.lng,
                maxspeed: h.maxspeed != null ? +h.maxspeed : null,
                kw: h.kw != null ? +h.kw : null,
                routeIdx: idx,
                alongKm: along
              };
            });
            var navOnly = false;
            try {
              if (window.__etubuLastPlanMeta && window.__etubuLastPlanMeta.navOnly) navOnly = true;
              var pos = __etubuLiveCoords();
              if (active && pos && !__etubuInTurkey(pos.lat, pos.lng)) navOnly = true;
            } catch(e3) {}
            return JSON.stringify({
              active: active, from: from, to: to, status: status, brief: briefText,
              counts: brief, hazardCount: hazards.length, navOnly: navOnly, details: details
            });
          } catch (e) {
            return JSON.stringify({ active: false, from: '', to: '', status: '', brief: '', counts: {}, hazardCount: 0, navOnly: false, details: [] });
          }
        })();
        """) { raw in
            guard let raw, let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                DispatchQueue.main.async {
                    let t = EtubuVehicleTelemetry.shared
                    let w = EtubuDriveWarnings.shared
                    if t.routeActive {
                        completion(EtubuRouteStatus(
                            active: true,
                            fromLabel: t.routeFrom,
                            toLabel: t.routeTo,
                            statusText: "",
                            briefText: "",
                            brief: w.brief,
                            hazardCount: w.hazards.count,
                            navOnly: !w.brief.hasAny && w.hazards.isEmpty,
                            hazardDetails: w.hazards
                        ))
                    } else {
                        completion(EtubuRouteStatus(active: false, fromLabel: "", toLabel: "", statusText: "", briefText: ""))
                    }
                }
                return
            }
            let counts = json["counts"] as? [String: Any] ?? [:]
            func count(_ key: String) -> Int {
                if let i = counts[key] as? Int { return i }
                if let d = counts[key] as? Double { return Int(d) }
                if let n = counts[key] as? NSNumber { return n.intValue }
                if let s = counts[key] as? String { return Int(s) ?? 0 }
                return 0
            }
            func dbl(_ any: Any?) -> Double? {
                if let d = any as? Double { return d }
                if let n = any as? NSNumber { return n.doubleValue }
                if let s = any as? String { return Double(s) }
                return nil
            }
            func intv(_ any: Any?) -> Int? {
                if let i = any as? Int { return i }
                if let d = any as? Double { return Int(d) }
                if let n = any as? NSNumber { return n.intValue }
                if let s = any as? String { return Int(s) }
                return nil
            }
            let summary = EtubuRouteBriefSummary(
                radarCount: count("radar"),
                controlCount: count("control"),
                corridorCount: count("corridor"),
                chargeCount: count("charge"),
                weatherCount: count("weather"),
                chargeNames: (counts["chargeNames"] as? [String]) ?? [],
                weatherLabels: (counts["weatherLabels"] as? [String]) ?? []
            )
            let hazardCount: Int = {
                if let i = json["hazardCount"] as? Int { return i }
                if let d = json["hazardCount"] as? Double { return Int(d) }
                if let n = json["hazardCount"] as? NSNumber { return n.intValue }
                return 0
            }()
            let details: [EtubuRouteHazard] = ((json["details"] as? [[String: Any]]) ?? []).compactMap { row in
                guard let lat = dbl(row["lat"]), let lng = dbl(row["lng"]) else { return nil }
                let kind = (row["kind"] as? String) ?? "radar"
                return EtubuRouteHazard(
                    id: (row["id"] as? String) ?? "\(kind)-\(lat),\(lng)",
                    kind: kind,
                    label: (row["label"] as? String) ?? "",
                    lat: lat,
                    lng: lng,
                    maxspeed: intv(row["maxspeed"]),
                    kw: intv(row["kw"]),
                    routeIdx: intv(row["routeIdx"]),
                    alongKm: dbl(row["alongKm"])
                )
            }
            DispatchQueue.main.async {
                var active = json["active"] as? Bool ?? false
                var fromLabel = json["from"] as? String ?? ""
                var toLabel = json["to"] as? String ?? ""
                var navOnly = json["navOnly"] as? Bool ?? false
                // Prefer live telemetry when Cap status is empty (native plan path).
                let t = EtubuVehicleTelemetry.shared
                let w = EtubuDriveWarnings.shared
                if !active && t.routeActive {
                    active = true
                    if fromLabel.isEmpty { fromLabel = t.routeFrom }
                    if toLabel.isEmpty { toLabel = t.routeTo }
                }
                var briefOut = summary
                var detailsOut = details
                var hazardOut = hazardCount
                if !briefOut.hasAny, w.brief.hasAny {
                    briefOut = w.brief
                }
                if detailsOut.isEmpty, !w.hazards.isEmpty {
                    detailsOut = w.hazards
                    hazardOut = w.hazards.count
                }
                if !briefOut.hasAny, !detailsOut.isEmpty {
                    briefOut = EtubuRouteBriefSummary(
                        radarCount: detailsOut.filter { $0.kind == "radar" }.count,
                        controlCount: detailsOut.filter { $0.kind == "control" }.count,
                        corridorCount: detailsOut.filter { $0.kind == "corridor" }.count,
                        chargeCount: detailsOut.filter { $0.kind == "charge" }.count,
                        weatherCount: detailsOut.filter { $0.kind == "weather" }.count,
                        chargeNames: detailsOut.filter { $0.kind == "charge" }.prefix(4).map(\.label),
                        weatherLabels: detailsOut.filter { $0.kind == "weather" }.prefix(4).map(\.label)
                    )
                }
                completion(EtubuRouteStatus(
                    active: active,
                    fromLabel: fromLabel,
                    toLabel: toLabel,
                    statusText: json["status"] as? String ?? "",
                    briefText: json["brief"] as? String ?? "",
                    brief: briefOut,
                    hazardCount: hazardOut,
                    navOnly: navOnly,
                    hazardDetails: detailsOut
                ))
            }
        }
    }

    private static func parsePlaces(_ raw: String?) -> [EtubuRoutePlace] {
        guard let raw, let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { row -> EtubuRoutePlace? in
            let label = (row["label"] as? String) ?? ""
            guard !label.isEmpty else { return nil }
            let lat: Double? = {
                if let n = row["lat"] as? Double { return n }
                if let n = row["lat"] as? NSNumber { return n.doubleValue }
                if let s = row["lat"] as? String { return Double(s) }
                return nil
            }()
            let lng: Double? = {
                if let n = row["lng"] as? Double { return n }
                if let n = row["lng"] as? NSNumber { return n.doubleValue }
                if let n = row["lon"] as? Double { return n }
                if let n = row["lon"] as? NSNumber { return n.doubleValue }
                if let s = row["lng"] as? String { return Double(s) }
                return nil
            }()
            return EtubuRoutePlace(
                label: label,
                cityName: (row["cityName"] as? String) ?? (row["city"] as? String) ?? "",
                districtName: (row["districtName"] as? String) ?? (row["district"] as? String) ?? "",
                isMyLocation: (row["isMyLocation"] as? Bool) ?? false,
                isMerkez: (row["isMerkez"] as? Bool) ?? false,
                nearLabel: (row["nearLabel"] as? String) ?? "",
                lat: lat,
                lng: lng,
                districtId: (row["districtId"] as? String) ?? ""
            )
        }
    }

    /// UTF-8 safe JS string literal (Turkish ç/ğ/ı/ö/ş/ü etc.).
    private static func jsStringLiteral(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed]),
              let out = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return out
    }

    private static func escape(_ s: String) -> String {
        // Prefer jsStringLiteral for query paths; kept for rare inline helpers.
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: "")
    }
}
