import Foundation
import Combine
import Capacitor
import UIKit
import CoreLocation

enum EtubuWarnStage: String {
    case idle, far, mid, near, critical
}

struct EtubuWarnItem: Equatable, Identifiable {
    var id: String
    var kind: String // radar | corridor | charge | weather | control
    var title: String
    var distanceLabel: String
    var stage: EtubuWarnStage
    var meta: String = ""
}

struct EtubuRouteHazard: Equatable, Identifiable {
    var id: String
    var kind: String
    var label: String
    var lat: Double
    var lng: Double
    var maxspeed: Int?
    var kw: Int?
    /// Index along route polyline (web RouteGuard).
    var routeIdx: Int? = nil
    /// Approx km from route start.
    var alongKm: Double? = nil
    /// Remaining straight-line distance label when known (e.g. "1.2 km").
    var distanceLabel: String = ""

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var kindTitleTR: String {
        switch kind {
        case "corridor": return "Hız koridoru"
        case "charge": return "Şarj istasyonu"
        case "weather": return "Hava olayı"
        case "control": return "Kontrol"
        default: return "Radar"
        }
    }
}

struct EtubuRouteBriefSummary: Equatable {
    var radarCount: Int = 0
    var controlCount: Int = 0
    var corridorCount: Int = 0
    var chargeCount: Int = 0
    var weatherCount: Int = 0
    var chargeNames: [String] = []
    var weatherLabels: [String] = []

    var hasAny: Bool {
        radarCount + controlCount + corridorCount + chargeCount + weatherCount > 0
    }
}

/// Mirrors ETUBU web RouteGuard hazards + warn-reel + corridor panel (same placement logic as web).
@MainActor
final class EtubuDriveWarnings: ObservableObject {
    static let shared = EtubuDriveWarnings()

    @Published var primary: EtubuWarnItem?
    @Published var queue: [EtubuWarnItem] = []
    @Published var hazards: [EtubuRouteHazard] = []
    /// Hazards still ahead on the active route (passed ones dropped).
    @Published var remainingHazards: [EtubuRouteHazard] = []
    @Published var routeCoords: [CLLocationCoordinate2D] = []
    @Published var brief = EtubuRouteBriefSummary()
    /// Brief counts for points still ahead (Island / Live Activity).
    @Published var remainingBrief = EtubuRouteBriefSummary()

    @Published var corridorActive = false
    @Published var corridorOver = false
    @Published var corridorAvgKmh: Int = 0
    @Published var corridorLimit: Int?
    @Published var corridorRemainLabel: String = ""
    @Published var corridorLabel: String = ""
    /// Trip distance meta when not in corridor (web `#avgSpeedMeta`).
    @Published var tripDistLabel: String = ""

    /// Demo drive mirror — RootView already observes this object (reliable UI refresh).
    @Published var demoActive = false
    @Published var demoKmh: Int = 0
    @Published var demoGear: String = "P"
    @Published var demoPowerKw: Int = 0

    private var timer: Timer?

    private init() {}

    func clearCriticalAlerts() {
        primary = nil
        queue = []
        hazards = []
        remainingHazards = []
        brief = EtubuRouteBriefSummary()
        remainingBrief = EtubuRouteBriefSummary()
        corridorActive = false
        corridorOver = false
        corridorAvgKmh = 0
        corridorLimit = nil
        corridorRemainLabel = ""
        corridorLabel = ""
        tripDistLabel = ""
        // demoActive / demoKmh — clearCriticalAlerts demo sürüşünü bozmasın;
        // sadece stop() / applyDemoDrive(false) sıfırlar.
    }

    func applyDemoDrive(active: Bool, kmh: Int, gear: String, power: Int) {
        demoActive = active
        demoKmh = kmh
        demoGear = gear
        demoPowerKw = power
    }

    private var lastPollJSONHash: Int = 0
    private var pollIdleTicks = 0

    func startPolling() {
        timer?.invalidate()
        Self.armRouteHazardHook()
        // 0.55s → 1.0s; yaklaşırken hızlanır (aşağıda).
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollOnce() }
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
        pollOnce()
    }

    /// Cap-side MiniMap.setRoute / setHazards stash — same hazards web places on the route.
    nonisolated static func armRouteHazardHook() {
        EtubuClusterAudioBridge.evalJS(injectScript)
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func pollOnce() {
        // Demo kendi uyarılarını yazar — web poll boş queue ile silmesin.
        if EtubuDemoDrive.isActive { return }
        let routeQuiet = routeCoords.isEmpty && queue.isEmpty && primary == nil
            && !EtubuVehicleTelemetry.shared.routeActive
        if routeQuiet {
            pollIdleTicks &+= 1
            // Rota yokken her 3. tikte bir oku (≈3s).
            if pollIdleTicks % 3 != 1 { return }
        } else {
            pollIdleTicks = 0
        }
        EtubuClusterAudioBridge.evalJSReturning(Self.readScript) { [weak self] raw in
            guard let self, let raw, let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            let hash = raw.hashValue
            Task { @MainActor in
                // Callback gecikmeli gelebilir — demo başlamışsa web sonucunu yoksay.
                if EtubuDemoDrive.isActive { return }
                if hash == self.lastPollJSONHash { return }
                self.lastPollJSONHash = hash
                self.apply(json)
            }
        }
    }

    private func apply(_ json: [String: Any]) {
        if let arr = json["queue"] as? [[String: Any]] {
            let parsed = arr.compactMap { Self.parseWarn($0) }
            // Radar + hız koridoru her zaman önce
            queue = parsed.sorted { a, b in
                let pa = Self.warnPriority(a.kind)
                let pb = Self.warnPriority(b.kind)
                if pa != pb { return pa < pb }
                return false
            }
            primary = queue.first
        } else {
            queue = []
            primary = nil
        }

        if let hs = json["hazards"] as? [[String: Any]] {
            hazards = hs.compactMap { row in
                guard let lat = Self.double(row["lat"]), let lng = Self.double(row["lng"]) else { return nil }
                let kind = (row["kind"] as? String) ?? "radar"
                let label = (row["label"] as? String) ?? ""
                return EtubuRouteHazard(
                    id: (row["id"] as? String) ?? "\(kind)-\(lat),\(lng)",
                    kind: kind,
                    label: label,
                    lat: lat,
                    lng: lng,
                    maxspeed: Self.int(row["maxspeed"]),
                    kw: Self.int(row["kw"]),
                    routeIdx: Self.int(row["routeIdx"]),
                    alongKm: Self.double(row["alongKm"]),
                    distanceLabel: (row["dist"] as? String) ?? ""
                )
            }
        }

        if let rh = json["remaining"] as? [[String: Any]] {
            remainingHazards = rh.compactMap { row in
                guard let lat = Self.double(row["lat"]), let lng = Self.double(row["lng"]) else { return nil }
                let kind = (row["kind"] as? String) ?? "radar"
                let label = (row["label"] as? String) ?? ""
                return EtubuRouteHazard(
                    id: (row["id"] as? String) ?? "rem-\(kind)-\(lat),\(lng)",
                    kind: kind,
                    label: label,
                    lat: lat,
                    lng: lng,
                    maxspeed: Self.int(row["maxspeed"]),
                    kw: Self.int(row["kw"]),
                    routeIdx: Self.int(row["routeIdx"]),
                    alongKm: Self.double(row["alongKm"]),
                    distanceLabel: (row["dist"] as? String) ?? ""
                )
            }
        } else if json["active"] as? Bool == true {
            remainingHazards = hazards
        } else {
            remainingHazards = []
        }

        if let cs = json["coords"] as? [[String: Any]] {
            routeCoords = cs.compactMap { row in
                guard let lat = Self.double(row["lat"]), let lng = Self.double(row["lng"]) else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
        } else if json["active"] as? Bool == false {
            routeCoords = []
        }

        if let b = json["brief"] as? [String: Any] {
            brief = EtubuRouteBriefSummary(
                radarCount: Self.int(b["radar"]) ?? 0,
                controlCount: Self.int(b["control"]) ?? 0,
                corridorCount: Self.int(b["corridor"]) ?? 0,
                chargeCount: Self.int(b["charge"]) ?? 0,
                weatherCount: Self.int(b["weather"]) ?? 0,
                chargeNames: (b["chargeNames"] as? [String]) ?? [],
                weatherLabels: (b["weatherLabels"] as? [String]) ?? []
            )
        }

        if let rb = json["remainingBrief"] as? [String: Any] {
            remainingBrief = EtubuRouteBriefSummary(
                radarCount: Self.int(rb["radar"]) ?? 0,
                controlCount: Self.int(rb["control"]) ?? 0,
                corridorCount: Self.int(rb["corridor"]) ?? 0,
                chargeCount: Self.int(rb["charge"]) ?? 0,
                weatherCount: Self.int(rb["weather"]) ?? 0,
                chargeNames: (rb["chargeNames"] as? [String]) ?? [],
                weatherLabels: (rb["weatherLabels"] as? [String]) ?? []
            )
        } else {
            remainingBrief = Self.briefFromHazards(remainingHazards)
        }

        // Derive brief counts from hazards if DOM brief not yet painted / enrich pending
        if !hazards.isEmpty, !brief.hasAny || brief.chargeCount == 0 || brief.weatherCount == 0 {
            let fromHaz = Self.briefFromHazards(hazards)
            if brief.radarCount == 0 { brief.radarCount = fromHaz.radarCount }
            if brief.corridorCount == 0 { brief.corridorCount = fromHaz.corridorCount }
            if brief.chargeCount == 0 {
                brief.chargeCount = fromHaz.chargeCount
                brief.chargeNames = fromHaz.chargeNames
            }
            if brief.weatherCount == 0 {
                brief.weatherCount = fromHaz.weatherCount
                brief.weatherLabels = fromHaz.weatherLabels
            }
            if brief.controlCount == 0 { brief.controlCount = fromHaz.controlCount }
        }

        corridorActive = json["corridor"] as? Bool ?? false
        corridorOver = json["over"] as? Bool ?? false
        corridorAvgKmh = Self.int(json["avg"]) ?? 0
        corridorLimit = Self.int(json["limit"])
        corridorRemainLabel = (json["remain"] as? String) ?? ""
        corridorLabel = (json["corridorLabel"] as? String) ?? ""
        tripDistLabel = (json["tripMeta"] as? String) ?? ""

        let routeOn = json["active"] as? Bool ?? false
        let remainKm: Double? = {
            if let n = json["remainKm"] as? Double { return n }
            if let n = json["remainKm"] as? NSNumber { return n.doubleValue }
            if let s = json["remainKm"] as? String { return Double(s) }
            // tripMeta "123 km" fallback
            if let meta = json["tripMeta"] as? String {
                let parts = meta.replacingOccurrences(of: ",", with: ".")
                if let match = parts.range(of: #"[0-9]+(?:\.[0-9]+)?\s*km"#, options: .regularExpression) {
                    let num = parts[match].replacingOccurrences(of: "km", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    return Double(num)
                }
            }
            return nil
        }()
        EtubuVehicleTelemetry.shared.applyCapRouteRemain(active: routeOn, remainKm: remainKm)

        // Native cluster: Cap TTS kapalı — ses burada.
        maybeSpeakPrimaryWarn()

        Self.pushLiveActivityBrief()
        EtubuVehicleTelemetry.shared.publishWidgetSnapshot(
            primaryWarn: primary.map { "\($0.title) \($0.distanceLabel)" }
        )
        EtubuEvRoutePlanner.shared.refreshFromLiveState()
    }

    private var lastSpokenWarnId = ""
    private var lastSpokenWarnStage = ""
    private func maybeSpeakPrimaryWarn() {
        guard !EtubuDemoDrive.isActive else { return }
        guard let item = primary else { return }
        guard item.stage == .far || item.stage == .near || item.stage == .critical else { return }
        let stage = item.stage.rawValue
        if item.id == lastSpokenWarnId, stage == lastSpokenWarnStage { return }
        lastSpokenWarnId = item.id
        lastSpokenWarnStage = stage
        let phrase = "\(item.title) \(item.distanceLabel)".trimmingCharacters(in: .whitespaces)
        guard !phrase.isEmpty else { return }
        EtubuClusterAudioBridge.playWarnCue(
            id: item.id,
            kind: item.kind,
            stage: stage,
            phrase: phrase
        )
    }

    private static var lastLivePushMs: Double = 0
    private static func pushLiveActivityBrief() {
        guard #available(iOS 16.2, *) else { return }
        let now = Date().timeIntervalSince1970 * 1000
        guard now - lastLivePushMs > 800 else { return }
        lastLivePushMs = now
        Task { await EtubuLiveActivityController.publishCurrent() }
    }

    private static func parseWarn(_ row: [String: Any]) -> EtubuWarnItem? {
        let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stage = EtubuWarnStage(rawValue: (row["stage"] as? String) ?? "idle") ?? .idle
        guard stage != .idle || !title.isEmpty else { return nil }
        guard !title.isEmpty else { return nil }
        let kind = (row["kind"] as? String) ?? "radar"
        return EtubuWarnItem(
            id: (row["id"] as? String) ?? "\(kind)-\(title)",
            kind: kind,
            title: title,
            distanceLabel: (row["dist"] as? String) ?? "",
            stage: stage == .idle ? .far : stage,
            meta: (row["meta"] as? String) ?? ""
        )
    }

    private static func warnPriority(_ kind: String) -> Int {
        switch kind {
        case "corridor", "radar": return 0
        case "charge": return 1
        case "weather": return 2
        default: return 3
        }
    }

    private static func briefFromHazards(_ hazards: [EtubuRouteHazard]) -> EtubuRouteBriefSummary {
        var s = EtubuRouteBriefSummary()
        for h in hazards {
            switch h.kind {
            case "corridor": s.corridorCount += 1
            case "charge":
                s.chargeCount += 1
                if !h.label.isEmpty, s.chargeNames.count < 4 { s.chargeNames.append(h.label) }
            case "weather":
                s.weatherCount += 1
                if !h.label.isEmpty, s.weatherLabels.count < 4 { s.weatherLabels.append(h.label) }
            case "control": s.controlCount += 1
            default: s.radarCount += 1
            }
        }
        return s
    }

    private static func double(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    /// Patches MiniMap.setRoute / setHazards so Cap can read the same hazard list web places on the route.
    private static let injectScript = """
    (function(){
      if (window.__etubuRouteHook) return;
      window.__etubuRouteHook = true;
      window.__etubuRouteState = window.__etubuRouteState || { hazards: [], coords: [], at: 0 };
      function stashHazards(h) {
        if (!Array.isArray(h)) return;
        window.__etubuRouteState.hazards = h.map(function(x){
          return {
            id: x.id || ((x.kind||'radar') + '-' + x.lat + ',' + x.lng),
            kind: x.kind || 'radar',
            label: x.label || x.name || '',
            lat: +x.lat, lng: +x.lng,
            maxspeed: x.maxspeed != null ? +x.maxspeed : null,
            kw: x.kw != null ? +x.kw : null,
            routeIdx: x.routeIdx != null ? +x.routeIdx : null
          };
        }).filter(function(x){ return Number.isFinite(x.lat) && Number.isFinite(x.lng); });
        window.__etubuRouteState.at = Date.now();
      }
      function stashCoords(c) {
        if (!Array.isArray(c)) return;
        window.__etubuRouteState.coords = c.map(function(p){
          if (Array.isArray(p)) return { lng: +p[0], lat: +p[1] };
          return { lng: +(p.lng != null ? p.lng : p.x), lat: +(p.lat != null ? p.lat : p.y) };
        }).filter(function(x){ return Number.isFinite(x.lat) && Number.isFinite(x.lng); });
      }
      function wrapMiniMap() {
        if (typeof MiniMap === 'undefined' || !MiniMap || MiniMap.__etubuWrapped) return !!MiniMap?.__etubuWrapped;
        var sr = MiniMap.setRoute;
        var sh = MiniMap.setHazards;
        if (typeof sr === 'function') {
          MiniMap.setRoute = function(coords, hazards) {
            stashCoords(coords);
            if (arguments.length > 1) stashHazards(hazards);
            return sr.apply(this, arguments);
          };
        }
        if (typeof sh === 'function') {
          MiniMap.setHazards = function(hazards) {
            stashHazards(hazards);
            return sh.apply(this, arguments);
          };
        }
        MiniMap.__etubuWrapped = true;
        return true;
      }
      wrapMiniMap();
      var n = 0;
      var t = setInterval(function(){
        if (wrapMiniMap() || ++n > 48) clearInterval(t);
      }, 250);
    })();
    """

    private static let readScript = """
    (function(){
      try {
        if (!window.__etubuRouteHook) {
          /* inject may race — no-op flag check */
        }
        var st = window.__etubuRouteState || { hazards: [], coords: [] };
        var hazards = (st.hazards || []).map(function(x){
          return {
            id: x.id || ((x.kind||'radar') + '-' + x.lat + ',' + x.lng),
            kind: x.kind || 'radar',
            label: x.label || x.name || '',
            lat: +x.lat, lng: +x.lng,
            maxspeed: x.maxspeed != null ? +x.maxspeed : null,
            kw: x.kw != null ? +x.kw : null,
            routeIdx: x.routeIdx != null ? +x.routeIdx : null,
            alongKm: x.alongKm != null ? +x.alongKm : null,
            dist: x.dist || ''
          };
        });
        var coords = st.coords || [];

        function nearestIdx(lat, lng) {
          if (!coords.length) return 0;
          var best = 0, bestD = Infinity;
          for (var i = 0; i < coords.length; i++) {
            var dLat = (coords[i].lat - lat) * Math.PI/180;
            var dLon = (coords[i].lng - lng) * Math.PI/180;
            var a = Math.sin(dLat/2)*Math.sin(dLat/2) +
              Math.cos(lat*Math.PI/180)*Math.cos(coords[i].lat*Math.PI/180)*Math.sin(dLon/2)*Math.sin(dLon/2);
            var d = 2*6371000*Math.asin(Math.sqrt(a));
            if (d < bestD) { bestD = d; best = i; }
          }
          return best;
        }
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
        function fmtDist(m) {
          if (!Number.isFinite(m) || m < 0) return '';
          var stepped;
          if (m >= 5000) stepped = Math.max(10000, Math.floor(m / 10000) * 10000);
          else if (m >= 2000) stepped = Math.max(1000, Math.floor(m / 1000) * 1000);
          else if (m >= 300) stepped = Math.max(100, Math.floor(m / 100) * 100);
          else if (m >= 100) stepped = Math.max(50, Math.floor(m / 50) * 50);
          else stepped = Math.max(10, Math.floor(m / 10) * 10);
          if (stepped >= 1000) {
            var km = stepped / 1000;
            return (Number.isInteger(km) ? km : km.toFixed(1)) + ' km';
          }
          return Math.round(stepped) + ' m';
        }

        function warnPri(kind) {
          if (kind === 'corridor' || kind === 'radar') return 0;
          if (kind === 'charge') return 1;
          if (kind === 'weather') return 2;
          return 3;
        }

        // Enrich alongKm for detail lists
        hazards = hazards.map(function(h){
          if (h.alongKm == null && h.routeIdx != null) h.alongKm = alongKmForIdx(h.routeIdx);
          return h;
        });

        function inferKind(title, meta, fallback) {
          var s = ((title||'') + ' ' + (meta||'')).toLocaleLowerCase('tr-TR');
          if (/koridor|corridor|ortalama/.test(s)) return 'corridor';
          if (/şarj|sarj|charge|kwh|\\bkw\\b|ocm|zes|trugo/.test(s)) return 'charge';
          if (/hava|yağmur|yagmur|sis|fırtına|firtina|kar|buz|rüzgar|ruzgar|weather|storm|fog/.test(s)) return 'weather';
          if (/kontrol|control/.test(s)) return 'control';
          return fallback || 'radar';
        }

        var reel = document.getElementById('warnReel');
        var track = document.getElementById('warnReelTrack');
        var stage = (reel && !reel.hidden) ? (reel.dataset.stage || 'far') : 'idle';
        var primaryKind = 'radar';
        if (reel && reel.className) {
          var m = String(reel.className).match(/is-kind-([a-z]+)/);
          if (m) primaryKind = m[1];
        }

        var queue = [];
        if (track && reel && !reel.hidden) {
          var cards = track.querySelectorAll('.warn-reel-item, .warn-reel-card');
          for (var i = 0; i < cards.length && queue.length < 4; i++) {
            var card = cards[i];
            var title = (card.querySelector('.warn-reel-kicker, .warn-reel-title')?.textContent
              || card.getAttribute('data-title') || '').trim();
            var dist = (card.querySelector('.warn-reel-dist')?.textContent
              || card.getAttribute('data-dist') || '').trim();
            var meta = (card.querySelector('.warn-reel-meta')?.textContent || '').trim();
            if (!title && !dist) continue;
            var kind = i === 0 ? primaryKind : inferKind(title, meta, primaryKind);
            queue.push({
              id: card.getAttribute('data-id') || (kind + '-' + title + '-' + dist + '-' + i),
              kind: kind,
              title: title.slice(0, 80),
              dist: dist.slice(0, 24),
              meta: meta.slice(0, 100),
              stage: i === 0 ? stage : 'far'
            });
          }
        }

        // Prefer RouteGuard.listAhead when GPS known — same placement window as web
        var lat = null, lng = null;
        try {
          var loc = JSON.parse(localStorage.getItem('etubu_last_map_location') || '{}');
          if (Number.isFinite(loc.lat) && Number.isFinite(loc.lng)) { lat = loc.lat; lng = loc.lng; }
        } catch (e) {}
        if (lat == null && coords.length) {
          lat = coords[0].lat; lng = coords[0].lng;
        }
        if (window.RouteGuard && typeof RouteGuard.listAhead === 'function' && lat != null) {
          try {
            var ahead = RouteGuard.listAhead(lat, lng, null, 4) || [];
            if (ahead.length) {
              queue = ahead.map(function(it, idx){
                return {
                  id: it.id || ('rg-' + idx),
                  kind: it.kind || 'radar',
                  title: (it.title || '').slice(0, 80),
                  dist: (it.dist || '').slice(0, 24),
                  distM: it.distM != null ? +it.distM : null,
                  meta: (it.meta || '').slice(0, 100),
                  stage: it.stage || (idx === 0 ? stage : 'far'),
                  pri: warnPri(it.kind || 'radar')
                };
              });
              queue.sort(function(a, b){
                return (a.pri - b.pri) || ((a.distM||1e12) - (b.distM||1e12));
              });
              if (queue[0] && stage !== 'idle') queue[0].stage = stage;
            }
          } catch (e2) {}
        }

        // Remaining hazards — drop passed points along the route
        var remaining = hazards.slice();
        if (lat != null && Number.isFinite(lat) && hazards.length) {
          var userIdx = nearestIdx(lat, lng);
          remaining = hazards.filter(function(h){
            if (h.routeIdx != null && Number.isFinite(h.routeIdx)) {
              return h.routeIdx >= userIdx - 1;
            }
            // fallback: still ahead if farther than ~80m behind heading proxy — keep if within 25km
            var dLat = (h.lat - lat) * Math.PI/180;
            var dLon = (h.lng - lng) * Math.PI/180;
            var a = Math.sin(dLat/2)*Math.sin(dLat/2) +
              Math.cos(lat*Math.PI/180)*Math.cos(h.lat*Math.PI/180)*Math.sin(dLon/2)*Math.sin(dLon/2);
            var d = 2*6371000*Math.asin(Math.sqrt(a));
            return d < 25000;
          }).map(function(h){
            var dLat = (h.lat - lat) * Math.PI/180;
            var dLon = (h.lng - lng) * Math.PI/180;
            var a = Math.sin(dLat/2)*Math.sin(dLat/2) +
              Math.cos(lat*Math.PI/180)*Math.cos(h.lat*Math.PI/180)*Math.sin(dLon/2)*Math.sin(dLon/2);
            var d = 2*6371000*Math.asin(Math.sqrt(a));
            h.dist = fmtDist(d);
            if (h.alongKm == null && h.routeIdx != null) h.alongKm = alongKmForIdx(h.routeIdx);
            return h;
          });
          // Prefer RouteGuard.listAhead ids when available for tighter remaining set
          try {
            if (window.RouteGuard && typeof RouteGuard.listAhead === 'function') {
              var aheadAll = RouteGuard.listAhead(lat, lng, null, 80) || [];
              if (aheadAll.length) {
                var ids = {};
                aheadAll.forEach(function(it){ if (it.id) ids[it.id] = it; });
                var filtered = remaining.filter(function(h){ return ids[h.id]; });
                if (filtered.length) {
                  remaining = filtered.map(function(h){
                    var it = ids[h.id];
                    if (it && it.dist) h.dist = it.dist;
                    return h;
                  });
                }
              }
            }
          } catch (e4) {}
        }

        function countBrief(list) {
          var b = { radar: 0, control: 0, corridor: 0, charge: 0, weather: 0, chargeNames: [], weatherLabels: [] };
          (list || []).forEach(function(h){
            if (h.kind === 'corridor') b.corridor++;
            else if (h.kind === 'charge') { b.charge++; if (h.label && b.chargeNames.length < 4) b.chargeNames.push(h.label); }
            else if (h.kind === 'weather') { b.weather++; if (h.label && b.weatherLabels.length < 4) b.weatherLabels.push(h.label); }
            else if (h.kind === 'control') b.control++;
            else b.radar++;
          });
          return b;
        }

        // Brief counts — same cards RouteGuard.renderBrief paints
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
        // Fallback from stashed hazards (official + seed + enrich)
        if (!brief.radar && !brief.corridor && !brief.charge && !brief.weather && hazards.length) {
          brief = countBrief(hazards);
        }
        var remainingBrief = countBrief(remaining);

        var avgP = document.getElementById('avgSpeedPanel');
        var avgV = document.getElementById('avgSpeedValue');
        var avgM = document.getElementById('avgSpeedMeta');
        var avgB = document.getElementById('avgSpeedBadge');
        var corridor = !!(avgP && avgP.classList.contains('is-corridor'));
        var over = !!(avgP && avgP.classList.contains('is-over'));
        var avg = avgV ? parseInt(avgV.textContent, 10) || 0 : 0;
        var limit = null;
        var remain = '';
        var corridorLabel = avgB ? (avgB.textContent || '').trim() : '';
        var metaTxt = avgM ? (avgM.textContent || '') : '';
        var tripMeta = '';
        var lim = metaTxt.match(/(\\d+)\\s*(?:km\\/h|kmh)/i);
        if (lim) limit = parseInt(lim[1], 10);
        var rem = metaTxt.match(/([\\d.]+\\s*km|[\\d]+\\s*m)/i);
        if (rem) remain = rem[1];
        try {
          if (window.RadarAlert && RadarAlert.getCorridorSnapshot) {
            var snap = RadarAlert.getCorridorSnapshot(avg);
            if (snap && snap.active) {
              corridor = true;
              over = !!snap.over;
              avg = Math.round(snap.avg || avg);
              if (snap.limit != null) limit = snap.limit;
              if (snap.remainM != null) {
                remain = snap.remainM >= 1000 ? (Math.round(snap.remainM/100)/10) + ' km' : Math.round(snap.remainM) + ' m';
              }
              if (snap.label) corridorLabel = snap.label;
            }
          }
        } catch (e3) {}
        // Web: outside corridor, avgSpeedValue = tripAvg and meta = trip km
        if (!corridor) {
          tripMeta = metaTxt.trim();
          remain = '';
          limit = null;
          corridorLabel = '';
          over = false;
        }

        var active = !!(window.RouteGuard && RouteGuard.isActive && RouteGuard.isActive());
        var remainKm = null;
        var routeTotalKm = null;
        if (coords.length >= 2) {
          var totalM = 0;
          for (var ri = 1; ri < coords.length; ri++) {
            var ca = coords[ri-1], cb = coords[ri];
            var dLatR = (cb.lat - ca.lat) * Math.PI/180;
            var dLonR = (cb.lng - ca.lng) * Math.PI/180;
            var aaR = Math.sin(dLatR/2)*Math.sin(dLatR/2) +
              Math.cos(ca.lat*Math.PI/180)*Math.cos(cb.lat*Math.PI/180)*Math.sin(dLonR/2)*Math.sin(dLonR/2);
            totalM += 2*6371000*Math.asin(Math.sqrt(aaR));
          }
          routeTotalKm = Math.round(totalM / 100) / 10;
          if (lat != null && Number.isFinite(lat)) {
            var uIdx = nearestIdx(lat, lng);
            var alongM = 0;
            for (var ai = 1; ai <= uIdx && ai < coords.length; ai++) {
              var aa = coords[ai-1], bb = coords[ai];
              var dLatA = (bb.lat - aa.lat) * Math.PI/180;
              var dLonA = (bb.lng - aa.lng) * Math.PI/180;
              var aaa = Math.sin(dLatA/2)*Math.sin(dLatA/2) +
                Math.cos(aa.lat*Math.PI/180)*Math.cos(bb.lat*Math.PI/180)*Math.sin(dLonA/2)*Math.sin(dLonA/2);
              alongM += 2*6371000*Math.asin(Math.sqrt(aaa));
            }
            remainKm = Math.max(0, Math.round((totalM - alongM) / 100) / 10);
          } else {
            remainKm = routeTotalKm;
          }
        }
        return JSON.stringify({
          active: active,
          stage: queue.length ? (queue[0].stage || stage) : 'idle',
          queue: queue,
          hazards: hazards.slice(0, 120),
          remaining: remaining.slice(0, 80),
          coords: coords.length > 400 ? coords.filter(function(_,i){ return i % Math.ceil(coords.length/400) === 0; }) : coords,
          brief: brief,
          remainingBrief: remainingBrief,
          corridor: corridor, over: over, avg: avg, limit: limit,
          remain: remain, corridorLabel: corridorLabel, tripMeta: tripMeta,
          remainKm: remainKm, routeTotalKm: routeTotalKm
        });
      } catch (e) {
        return JSON.stringify({ stage: 'idle', queue: [], hazards: [], remaining: [], coords: [], brief: {}, remainingBrief: {} });
      }
    })();
    """
}
