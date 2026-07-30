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
}

/// Drives Cap-side RouteGuard + RadarAlert with the same place resolve logic as web.
enum EtubuRouteBridge {
    /// Shared JS helpers mirroring js/route-guard.js fold / searchPlaces / resolvePlace.
    private static let placeHelpersJS = """
    function __etubuFold(s){
      return String(s||'').toLocaleLowerCase('tr-TR')
        .replace(/ğ/g,'g').replace(/ü/g,'u').replace(/ş/g,'s')
        .replace(/ı/g,'i').replace(/İ/g,'i').replace(/ö/g,'o').replace(/ç/g,'c')
        .replace(/[^a-z0-9\\s]/g,' ').replace(/\\s+/g,' ').trim();
    }
    function __etubuPlaceItems(){
      try {
        var raw = JSON.parse(localStorage.getItem('etubu_place_index_v2') || '{}');
        return raw.items || [];
      } catch(e) { return []; }
    }
    function __etubuSearchPlaces(q, limit){
      var query = __etubuFold(q);
      if (!query || query.length < 2) return [];
      var tokens = query.split(' ').filter(Boolean);
      var items = __etubuPlaceItems();
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
      // İl adı yazıldıysa (İstanbul): o ile bağlı ilçeleri öne çıkar / daralt
      var cityExact = items.filter(function(p){ return __etubuFold(p.cityName) === query; });
      if (cityExact.length >= 2) {
        cityExact.sort(function(a,b){
          if (!!b.isMerkez !== !!a.isMerkez) return a.isMerkez ? -1 : 1;
          return String(a.districtName||'').localeCompare(String(b.districtName||''), 'tr');
        });
        return cityExact.slice(0, Math.max(limit, 12));
      }
      return scored.slice(0, limit || 8).map(function(x){ return x.p; });
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
      var hits = __etubuSearchPlaces(text, 5);
      if (!hits.length) return null;
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
        EtubuClusterAudioBridge.evalJS("""
        (function(){
          try {
            localStorage.setItem('etubu_force_tr_route', '1');
            var rg = document.getElementById('routeGuard');
            if (rg) { rg.hidden = false; rg.classList.remove('is-collapsed','is-drive-hidden'); }
            var form = document.getElementById('routeForm');
            if (form) form.hidden = false;
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
        // Poll until index ready (web builds async)
        pollIndexReady(attemptsLeft: 40, completion: completion)
    }

    private static func pollIndexReady(attemptsLeft: Int, completion: ((Bool) -> Void)?) {
        EtubuClusterAudioBridge.evalJSReturning("""
        (function(){
          try {
            var raw = JSON.parse(localStorage.getItem('etubu_place_index_v2') || '{}');
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
            // Nudge web build again
            EtubuClusterAudioBridge.evalJS("""
            (function(){
              try {
                document.getElementById('routeFromInput')?.dispatchEvent(new Event('focus',{bubbles:true}));
                document.getElementById('routeFromInput')?.dispatchEvent(new Event('input',{bubbles:true}));
              } catch(e) {}
            })();
            """)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                pollIndexReady(attemptsLeft: attemptsLeft - 1, completion: completion)
            }
        }
    }

    /// Autocomplete — same scoring as web searchPlaces / fromSuggestList.
    static func search(query: String, forFrom: Bool, completion: @escaping ([EtubuRoutePlace]) -> Void) {
        let q = escape(query)
        EtubuClusterAudioBridge.evalJSReturning("""
        (function(){
          try {
            \(placeHelpersJS)
            var qRaw = '\(q)';
            var q = __etubuFold(qRaw);
            var out = [];
            var mine = __etubuMyLocation();
            if (forFromFlag) {
              var wantMine = !q || q.length < 2 ||
                'konumum'.indexOf(q) === 0 || q.indexOf('konum') >= 0 ||
                'mylocation'.indexOf(q.replace(/\\s/g,'')) === 0;
              var hits = q.length >= 2 ? __etubuSearchPlaces(qRaw, 8) : [];
              hits = hits.filter(function(p){ return !p.isMyLocation; });
              if (wantMine && mine) out.push(__etubuMapPlace(mine));
              hits.forEach(function(p){ out.push(__etubuMapPlace(p)); });
              return JSON.stringify(out.slice(0, 12));
            }
            if (q.length < 2) return '[]';
            __etubuSearchPlaces(qRaw, 12).forEach(function(p){ out.push(__etubuMapPlace(p)); });
            return JSON.stringify(out);
          } catch (e) {
            return '[]';
          }
        })();
        """.replacingOccurrences(of: "forFromFlag", with: forFrom ? "true" : "false")) { raw in
            DispatchQueue.main.async {
                completion(Self.parsePlaces(raw))
            }
        }
    }

    /// True when `text` matches a city name with more than one district and no
    /// unambiguous (Merkez / exact-district) match — UI must ask the user to pick a district.
    static func needsDistrictPick(text: String, completion: @escaping (Bool) -> Void) {
        let t = escape(text)
        EtubuClusterAudioBridge.evalJSReturning("""
        (function(){
          try {
            \(placeHelpersJS)
            var q = __etubuFold('\(t)');
            if (!q || q === 'konumum' || q === 'konum') return '0';
            var items = __etubuPlaceItems();
            var distExact = items.some(function(p){ return __etubuFold(p.districtName) === q; });
            if (distExact) return '0';
            var cityRows = items.filter(function(p){ return __etubuFold(p.cityName) === q; });
            if (cityRows.length === 0) return '0';
            var cityOnly = cityRows.some(function(p){ return p.isMerkez; });
            if (cityOnly) return '0';
            return cityRows.length > 1 ? '1' : '0';
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
        let t = escape(text)
        EtubuClusterAudioBridge.evalJSReturning("""
        (function(){
          try {
            \(placeHelpersJS)
            return JSON.stringify(__etubuMapPlace(__etubuResolvePlace('\(t)')) || null);
          } catch(e) { return 'null'; }
        })();
        """) { raw in
            DispatchQueue.main.async {
                if raw == nil || raw == "null" {
                    completion(nil)
                    return
                }
                completion(parsePlaces("[\(raw!)]").first)
            }
        }
    }

    static func plan(from: String, to: String, completion: ((Bool, String) -> Void)? = nil) {
        primeWarningAudio()
        Task { @MainActor in EtubuDriveWarnings.armRouteHazardHook() }
        let fromEsc = escape(from.isEmpty ? "Konumum" : from)
        let toEsc = escape(to)
        EtubuClusterAudioBridge.evalJS("""
        (function(){
          try {
            \(placeHelpersJS)
            localStorage.setItem('etubu_force_tr_route', '1');
            if (window.RadarAlert && window.RadarAlert.primeAudio) window.RadarAlert.primeAudio();
            var rg = document.getElementById('routeGuard');
            if (rg) { rg.hidden = false; rg.classList.remove('is-collapsed','is-drive-hidden'); }
            var form = document.getElementById('routeForm');
            if (form) form.hidden = false;
            var from = document.getElementById('routeFromInput');
            var to = document.getElementById('routeToInput');
            if (!from || !to) return;

            function applyResolved(input, text) {
              var p = __etubuResolvePlace(text);
              if (p && p.label) {
                input.value = p.label;
                return p;
              }
              input.value = text;
              return null;
            }

            // GPS for Konumum (web requestMyLocationOnce)
            function finish() {
              var fromPlace = applyResolved(from, '\(fromEsc)');
              var toPlace = applyResolved(to, '\(toEsc)');
              // Kick blur/enter resolve path used by web
              from.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
              setTimeout(function(){
                to.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                var go = document.getElementById('routeGoBtn');
                if (go) { go.disabled = false; go.click(); }
                window.__etubuLastPlanMeta = {
                  fromLabel: from.value,
                  toLabel: to.value,
                  navOnly: false
                };
                try {
                  var pos = __etubuLiveCoords();
                  if (pos && !__etubuInTurkey(pos.lat, pos.lng)) {
                    window.__etubuLastPlanMeta.navOnly = true;
                  }
                  if (toPlace && toPlace.lat != null && !__etubuInTurkey(+toPlace.lat, +toPlace.lng)) {
                    window.__etubuLastPlanMeta.navOnly = true;
                  }
                } catch(e) {}
              }, 100);
            }

            if (navigator.geolocation && (__etubuFold('\(fromEsc)') === 'konumum' || !__etubuLiveCoords())) {
              navigator.geolocation.getCurrentPosition(function(pos){
                try {
                  localStorage.setItem('etubu_last_map_location', JSON.stringify({
                    lat: pos.coords.latitude, lng: pos.coords.longitude
                  }));
                } catch(e) {}
                finish();
              }, function(){ finish(); }, { enableHighAccuracy: true, timeout: 8000, maximumAge: 60000 });
            } else {
              finish();
            }
          } catch (e) {}
        })();
        """)
        pollPlanReady(attemptsLeft: 14, completion: completion)
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
            if ((!brief.radar && !brief.corridor && !brief.charge && !brief.weather) && hazards.length) {
              hazards.forEach(function(h){
                if (h.kind === 'corridor') brief.corridor++;
                else if (h.kind === 'charge') { brief.charge++; if (h.label && brief.chargeNames.length < 4) brief.chargeNames.push(h.label); }
                else if (h.kind === 'weather') { brief.weather++; if (h.label && brief.weatherLabels.length < 4) brief.weatherLabels.push(h.label); }
                else if (h.kind === 'control') brief.control++;
                else brief.radar++;
              });
            }
            var navOnly = false;
            try {
              if (window.__etubuLastPlanMeta && window.__etubuLastPlanMeta.navOnly) navOnly = true;
              var pos = __etubuLiveCoords();
              if (active && pos && !__etubuInTurkey(pos.lat, pos.lng) && !brief.radar && !brief.corridor) navOnly = true;
              if (active && hazards.length === 0 && brief.radar === 0 && brief.corridor === 0) {
                // OSRM fallback often has empty official hazards
                var st = (window.__etubuRouteState && window.__etubuRouteState.coords) || [];
                if (st.length > 2) navOnly = navOnly || (!brief.charge && !brief.weather);
              }
            } catch(e3) {}
            return JSON.stringify({
              active: active, from: from, to: to, status: status, brief: briefText,
              counts: brief, hazardCount: hazards.length, navOnly: navOnly
            });
          } catch (e) {
            return JSON.stringify({ active: false, from: '', to: '', status: '', brief: '', counts: {}, hazardCount: 0, navOnly: false });
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
            DispatchQueue.main.async {
                completion(EtubuRouteStatus(
                    active: json["active"] as? Bool ?? false,
                    fromLabel: json["from"] as? String ?? "",
                    toLabel: json["to"] as? String ?? "",
                    statusText: json["status"] as? String ?? "",
                    briefText: json["brief"] as? String ?? "",
                    brief: summary,
                    hazardCount: hazardCount,
                    navOnly: json["navOnly"] as? Bool ?? false
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

    private static func escape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: "")
    }
}
