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

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
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
    @Published var routeCoords: [CLLocationCoordinate2D] = []
    @Published var brief = EtubuRouteBriefSummary()

    @Published var corridorActive = false
    @Published var corridorOver = false
    @Published var corridorAvgKmh: Int = 0
    @Published var corridorLimit: Int?
    @Published var corridorRemainLabel: String = ""
    @Published var corridorLabel: String = ""

    private var timer: Timer?

    private init() {}

    /// Called right after a route is planned — (re)arms hazard polling for the new route.
    static func armRouteHazardHook() {
        shared.startPolling()
    }

    func startPolling() {
        timer?.invalidate()
        EtubuClusterAudioBridge.evalJS(Self.injectScript)
        timer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollOnce() }
        }
        pollOnce()
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func pollOnce() {
        EtubuClusterAudioBridge.evalJSReturning(Self.readScript) { [weak self] raw in
            guard let self, let raw, let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            Task { @MainActor in
                self.apply(json)
            }
        }
    }

    private func apply(_ json: [String: Any]) {
        if let arr = json["queue"] as? [[String: Any]] {
            queue = arr.compactMap { Self.parseWarn($0) }
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
                    kw: Self.int(row["kw"])
                )
            }
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
        var hazards = st.hazards || [];
        var coords = st.coords || [];

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
                  meta: (it.meta || '').slice(0, 100),
                  stage: it.stage || (idx === 0 ? stage : 'far')
                };
              });
              if (queue[0] && stage !== 'idle') queue[0].stage = stage;
            }
          } catch (e2) {}
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
          hazards.forEach(function(h){
            if (h.kind === 'corridor') brief.corridor++;
            else if (h.kind === 'charge') { brief.charge++; if (h.label && brief.chargeNames.length < 4) brief.chargeNames.push(h.label); }
            else if (h.kind === 'weather') { brief.weather++; if (h.label && brief.weatherLabels.length < 4) brief.weatherLabels.push(h.label); }
            else if (h.kind === 'control') brief.control++;
            else brief.radar++;
          });
        }

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

        var active = !!(window.RouteGuard && RouteGuard.isActive && RouteGuard.isActive());
        return JSON.stringify({
          active: active,
          stage: queue.length ? (queue[0].stage || stage) : 'idle',
          queue: queue,
          hazards: hazards.slice(0, 120),
          coords: coords.length > 400 ? coords.filter(function(_,i){ return i % Math.ceil(coords.length/400) === 0; }) : coords,
          brief: brief,
          corridor: corridor, over: over, avg: avg, limit: limit,
          remain: remain, corridorLabel: corridorLabel
        });
      } catch (e) {
        return JSON.stringify({ stage: 'idle', queue: [], hazards: [], coords: [], brief: {} });
      }
    })();
    """
}
