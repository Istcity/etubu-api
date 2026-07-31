import Foundation

struct EtubuRoutePlace: Identifiable, Equatable, Hashable {
    var id: String {
        if isMyLocation { return "konumum" }
        return "\(cityName)|\(districtName)|\(label)"
    }
    let label: String
    let cityName: String
    let districtName: String
    let isMyLocation: Bool
    var isMerkez: Bool = false
    var nearLabel: String = ""
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

/// Drives Cap-side RouteGuard + RadarAlert with the same place resolve logic as web.
enum EtubuRouteBridge {
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
        nearLabel: p.nearLabel || ''
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

    /// Builds TR place index (web RouteGuard) and enables route UI even when Cap UI lang ≠ tr.
    static func ensureIndex(completion: ((Bool) -> Void)? = nil) {
        // Native URLSession first (Cap WebView CORS often blocks etubu.com fetch).
        Task {
            var injected = false
            do {
                var n = try await EtubuTrafikAPI.buildAndCachePlaceIndex()
                // First launch after UTF-8 fix: rebuild if only legacy/corrupt cache exists
                if n < 100 {
                    n = try await EtubuTrafikAPI.buildAndCachePlaceIndex(force: true)
                }
                if n > 100, let raw = EtubuTrafikAPI.cachedIndexJSONString() {
                    let b64 = Data(raw.utf8).base64EncodedString()
                    // atob alone breaks UTF-8 (Çorum → mojibake). Decode bytes → TextDecoder.
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
                    injected = true
                }
            } catch {
                // Fall through to JS RouteGuard.buildPlaceIndex via native trafikGet.
            }
            _ = injected
            DispatchQueue.main.async {
                EtubuClusterAudioBridge.evalJS("""
                (async function(){
                  try {
                    localStorage.setItem('etubu_force_tr_route', '1');
                    sessionStorage.setItem('etubu_force_tr_route', '1');
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
                    if (navigator.geolocation) {
                      navigator.geolocation.getCurrentPosition(function(pos){
                        try {
                          localStorage.setItem('etubu_last_map_location', JSON.stringify({
                            lat: pos.coords.latitude, lng: pos.coords.longitude
                          }));
                        } catch(e) {}
                      }, function(){}, { enableHighAccuracy: true, timeout: 10000, maximumAge: 120000 });
                    }
                  } catch (e) {}
                })();
                """)
                pollIndexReady(attemptsLeft: 60, completion: completion)
            }
        }
    }

    private static func pollIndexReady(attemptsLeft: Int, completion: ((Bool) -> Void)?) {
        EtubuClusterAudioBridge.evalJSReturning("""
        (async function(){
          try {
            if (window.RouteGuard && window.RouteGuard.buildPlaceIndex) {
              await window.RouteGuard.buildPlaceIndex();
            }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                pollIndexReady(attemptsLeft: attemptsLeft - 1, completion: completion)
            }
        }
    }

    /// Autocomplete — prefers live `RouteGuard.suggest` (builds index, Jul-29 city/district UX).
    static func search(query: String, forFrom: Bool, completion: @escaping ([EtubuRoutePlace]) -> Void) {
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
                completion(Self.parsePlaces(raw))
            }
        }
    }

    /// True when `text` matches a city name with more than one district and no
    /// unambiguous (Merkez / exact-district) match — UI must ask the user to pick a district.
    static func needsDistrictPick(text: String, completion: @escaping (Bool) -> Void) {
        let tJSON = jsStringLiteral(text)
        EtubuClusterAudioBridge.evalJSReturning("""
        (async function(){
          try {
            var t = \(tJSON);
            if (window.RouteGuard && window.RouteGuard.buildPlaceIndex) {
              await window.RouteGuard.buildPlaceIndex();
            }
            // Web: yalnızca büyükşehir adı tek başına → ilçe şart
            if (window.RouteGuard && window.RouteGuard.needsDistrictPick) {
              return window.RouteGuard.needsDistrictPick(t) ? '1' : '0';
            }
            \(placeHelpersJS)
            var q = __etubuFold(t);
            if (!q || q === 'konumum' || q === 'konum') return '0';
            var tokens = q.split(' ').filter(Boolean);
            if (tokens.length !== 1) return '0';
            var items = __etubuPlaceItems();
            var distExact = items.some(function(p){ return __etubuFold(p.districtName) === q; });
            if (distExact) return '0';
            var cityRows = items.filter(function(p){ return __etubuFold(p.cityName) === q; });
            if (cityRows.length <= 1) return '0';
            // Merkez varsa tek başına il kabul (normal iller)
            if (cityRows.some(function(p){ return p.isMerkez; })) return '0';
            // Büyükşehir (Merkez yok) → ilçe seç
            return '1';
          } catch(e) { return '0'; }
        })();
        """) { raw in
            DispatchQueue.main.async {
                completion(raw == "1")
            }
        }
    }

    /// Resolve typed text like web (Çorum→Merkez, Alaca→Çorum/Alaca).
    static func resolve(text: String, completion: @escaping (EtubuRoutePlace?) -> Void) {
        let tJSON = jsStringLiteral(text)
        EtubuClusterAudioBridge.evalJSReturning("""
        (async function(){
          try {
            var t = \(tJSON);
            if (window.RouteGuard && window.RouteGuard.resolve) {
              var p = await window.RouteGuard.resolve(t);
              return JSON.stringify(p || null);
            }
            \(placeHelpersJS)
            return JSON.stringify(__etubuMapPlace(__etubuResolvePlace(t)) || null);
          } catch(e) { return 'null'; }
        })();
        """) { raw in
            DispatchQueue.main.async {
                if raw == nil || raw == "null" {
                    completion(nil)
                    return
                }
                let trimmed = raw!.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("{") {
                    completion(parsePlaces("[\(trimmed)]").first)
                } else {
                    completion(parsePlaces(trimmed).first)
                }
            }
        }
    }

    static func plan(from: String, to: String, completion: ((Bool, String) -> Void)? = nil) {
        primeWarningAudio()
        EtubuDriveWarnings.armRouteHazardHook()
        let fromJSON = jsStringLiteral(from.isEmpty ? "Konumum" : from)
        let toJSON = jsStringLiteral(to)
        EtubuClusterAudioBridge.evalJSReturning("""
        (async function(){
          try {
            localStorage.setItem('etubu_force_tr_route', '1');
            sessionStorage.setItem('etubu_force_tr_route', '1');
            if (window.RadarAlert && window.RadarAlert.primeAudio) window.RadarAlert.primeAudio();
            var rg = document.getElementById('routeGuard');
            if (rg) { rg.hidden = false; rg.classList.remove('is-collapsed','is-drive-hidden'); }
            var form = document.getElementById('routeForm');
            if (form) form.hidden = false;
            var fromLabel = \(fromJSON);
            var toLabel = \(toJSON);
            // Same path as web Cap bridge — resolve + buildRoute (createRoute + hazards + brief)
            if (window.RouteGuard && window.RouteGuard.buildRoute) {
              var out = await window.RouteGuard.buildRoute(fromLabel, toLabel);
              return JSON.stringify(out || { ok: false, message: 'Rota kurulamadı' });
            }
            return JSON.stringify({ ok: false, message: 'RouteGuard yok' });
          } catch (e) {
            return JSON.stringify({ ok: false, message: String(e && e.message ? e.message : e) });
          }
        })();
        """) { raw in
            var ok = false
            var msg = "Rota kurulamadı"
            if let raw, let data = raw.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                ok = json["ok"] as? Bool ?? false
                msg = (json["message"] as? String) ?? msg
            }
            if ok {
                pollPlanReady(attemptsLeft: 16) { ready, statusMsg in
                    completion?(ready, ready ? statusMsg : (statusMsg.isEmpty ? msg : statusMsg))
                }
            } else {
                // Still poll briefly — createRoute may have partially activated
                pollPlanReady(attemptsLeft: 6) { ready, statusMsg in
                    completion?(ready || ok, ready ? statusMsg : msg)
                }
            }
        }
    }

    private static func pollPlanReady(attemptsLeft: Int, completion: ((Bool, String) -> Void)?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            status { st in
                let enriched = st.brief.hasAny || st.hazardCount > 0 || (st.active && !st.navOnly)
                if st.active && (enriched || st.navOnly || attemptsLeft <= 3) {
                    let msg: String
                    if st.navOnly {
                        msg = "Rota çizildi (navigasyon) — yurt dışı / OSRM; radar-koridor TR verisi yok"
                    } else if st.active {
                        msg = "Rota aktif · \(st.brief.radarCount) radar · \(st.brief.corridorCount) koridor · \(st.brief.chargeCount) şarj · \(st.brief.weatherCount) hava"
                    } else {
                        msg = st.statusText.isEmpty ? "Kuruluyor…" : st.statusText
                    }
                    completion?(st.active, msg)
                    return
                }
                if attemptsLeft <= 0 {
                    completion?(st.active, st.statusText.isEmpty ? (st.active ? "Rota aktif" : "Rota kurulamadı") : st.statusText)
                    return
                }
                let fail = st.statusText.lowercased()
                if !st.statusText.isEmpty,
                   fail.contains("fail") || fail.contains("hata") || fail.contains("bulunamad") {
                    completion?(false, st.statusText)
                    return
                }
                pollPlanReady(attemptsLeft: attemptsLeft - 1, completion: completion)
            }
        }
    }

    static func clear() {
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
            var cardsEl = document.querySelectorAll('.route-brief-cards > div');
            if (cardsEl && cardsEl.length >= 5) {
              function num(el){ var em = el && el.querySelector('em'); return em ? parseInt(em.textContent, 10) || 0 : 0; }
              brief.radar = num(cardsEl[0]);
              brief.control = num(cardsEl[1]);
              brief.corridor = num(cardsEl[2]);
              brief.charge = num(cardsEl[3]);
              brief.weather = num(cardsEl[4]);
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
                    completion(EtubuRouteStatus(active: false, fromLabel: "", toLabel: "", statusText: "", briefText: ""))
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
                completion(EtubuRouteStatus(
                    active: json["active"] as? Bool ?? false,
                    fromLabel: json["from"] as? String ?? "",
                    toLabel: json["to"] as? String ?? "",
                    statusText: json["status"] as? String ?? "",
                    briefText: json["brief"] as? String ?? "",
                    brief: summary,
                    hazardCount: hazardCount,
                    navOnly: json["navOnly"] as? Bool ?? false,
                    hazardDetails: details
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
            return EtubuRoutePlace(
                label: label,
                cityName: (row["cityName"] as? String) ?? "",
                districtName: (row["districtName"] as? String) ?? "",
                isMyLocation: (row["isMyLocation"] as? Bool) ?? false,
                isMerkez: (row["isMerkez"] as? Bool) ?? false,
                nearLabel: (row["nearLabel"] as? String) ?? ""
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
