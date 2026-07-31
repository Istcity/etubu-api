import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct EtubuClusterRootView: View {
    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @ObservedObject private var tesla = EtubuTeslaBleSession.shared
    @ObservedObject private var warnings = EtubuDriveWarnings.shared
    @ObservedObject private var demo = EtubuDemoDrive.shared

    @State private var theme: ClusterTheme = ClusterTheme.stored
    @State private var vinDraft: String = ""
    @State private var showVINEditor = false
    @State private var showSettings = false
    @State private var mixMode: String = "blend"
    @State private var soundOn = false
    @State private var selectedVoice: String = EtubuClusterAudioBridge.storedVoice
    @State private var showObdMenu = false
    @State private var showRoutePicker = false
    @State private var now = Date()
    @State private var appLanguage: EtubuAppLanguage = EtubuAppLanguage.current
    @State private var showSim = !EtubuClusterSimView.isDone
    @State private var showLegal = !EtubuLegalAcceptance.isAccepted
    @State private var leftCardPage: LeftCardPage = .tpms
    @State private var l10nTick = 0
    @State private var keyboardInset: CGFloat = 0
    @State private var hotspotFrames: [EtubuClusterHotspotID: CGRect] = [:]
    @FocusState private var vinFocused: Bool
    @AppStorage("etubu.cluster.notchAuraEnabled") private var notchAuraEnabled = true
    @AppStorage("etubu.cluster.mapEnabled") private var mapEnabled = true
    @AppStorage(EtubuMapLocationHelper.locationEnabledKey) private var locationEnabled = true
    @AppStorage("etubu.cluster.alertOverMusic") private var alertOverMusic = true
    @AppStorage("etubu.cluster.alertVolume") private var alertVolume: Double = 0.85

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var criticalAlertsOn: Bool { appLanguage.criticalAlertsEnabled }
    private var shouldShowPairGuide: Bool { tesla.pairStep != .none }

    private enum LeftCardPage: Int, CaseIterable {
        case tpms, telemetry, trip, media
        var title: String {
            switch self {
            case .tpms: return EtubuClusterL10n.tpms
            case .telemetry: return EtubuClusterL10n.telemetry
            case .trip: return EtubuClusterL10n.trip
            case .media: return EtubuClusterL10n.media
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let _ = l10nTick
            let landscape = geo.size.width > geo.size.height
            let _ = Self.applyLayoutBoost(landscape: landscape)
            // Hosting overlay often zeros SwiftUI safeAreaInsets — use window insets.
            let win = Self.windowSafeInsets()
            let insets = EdgeInsets(
                top: max(geo.safeAreaInsets.top, win.top),
                leading: max(geo.safeAreaInsets.leading, win.leading),
                bottom: max(geo.safeAreaInsets.bottom, win.bottom),
                trailing: max(geo.safeAreaInsets.trailing, win.trailing)
            )
            let cutout = notchAuraEnabled
                ? EtubuCameraCutout.resolve(size: geo.size, insets: insets, landscape: landscape)
                : nil

            ZStack {
                theme.canvas.ignoresSafeArea()
                backgroundLayer(landscape: landscape)

                Group {
                    if landscape {
                        landscapeLayout(size: geo.size, insets: insets, cutoutEdge: cutout?.landscapeEdge)
                    } else {
                        portraitLayout(size: geo.size, insets: insets)
                    }
                }
                // Capture all taps in the chrome layer (Map backdrop must not steal Simulator clicks).
                .contentShape(Rectangle())
                // Portrait: content already pads island; avoid double-push on top chrome.
                .padding(.top, landscape ? max(insets.top, 4) : 4)
                .padding(.bottom, max(insets.bottom, 4))
                .padding(.leading, landscape ? 0 : max(insets.leading, 6))
                .padding(.trailing, landscape ? 0 : max(insets.trailing, 6))
                .scaleEffect(x: demo.mirrorEnabled ? -1 : 1, y: 1)

                if let cutout {
                    EtubuNotchAuraView(kmh: telemetry.kmh, theme: theme, cutout: cutout)
                        .frame(width: cutout.aura.width, height: cutout.aura.height)
                        .position(x: cutout.aura.midX, y: cutout.aura.midY)
                        .allowsHitTesting(false)
                        .zIndex(5)
                }

                if demo.isRunning {
                    demoExitChip
                        .padding(.top, landscape ? max(insets.top, 8) + 4 : max(insets.top, 12) + 36)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .zIndex(6)
                }

                // Menzil < 100 km → çevrede kırmızı pulse
                if let range = telemetry.rangeKm, range > 0, range < 100 {
                    lowRangePulseOverlay
                        .allowsHitTesting(false)
                        .zIndex(4)
                }

                if showVINEditor {
                    vinOverlay
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .zIndex(20)
                }

                if shouldShowPairGuide {
                    pairGuideOverlay
                        .transition(.opacity)
                        .zIndex(30)
                }

                if showSim {
                    EtubuClusterSimView(
                        theme: theme,
                        hotspots: hotspotFrames,
                        canvasSize: geo.size
                    ) {
                        withAnimation(.easeOut(duration: 0.28)) {
                            showSim = false
                        }
                        startCoreIfNeeded()
                    }
                    .transition(.opacity)
                    .zIndex(40)
                }

                if showLegal {
                    EtubuLegalAcceptanceView(theme: theme) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showLegal = false
                        }
                        if !showSim {
                            startCoreIfNeeded()
                        }
                    }
                    .transition(.opacity)
                    .zIndex(50)
                }
            }
            .coordinateSpace(name: "etubuCluster")
            .onPreferenceChange(EtubuHotspotFramesKey.self) { hotspotFrames = $0 }
            .frame(width: geo.size.width, height: geo.size.height)
            .environment(\.clusterTheme, theme)
            .tint(theme.accent)
            .sheet(isPresented: $showSettings) {
                settingsSheet
                    .tint(theme.accent)
                    .environment(\.clusterTheme, theme)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showRoutePicker) {
                EtubuRoutePickerView()
            }
            .confirmationDialog("OBD fallback", isPresented: $showObdMenu, titleVisibility: .visible) {
                Button("Connect OBD BLE") { EtubuObdBleManager.shared.connect { _, _ in } }
                Button("Disconnect OBD", role: .destructive) { EtubuObdBleManager.shared.disconnect() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .ignoresSafeArea(.container)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            vinDraft = telemetry.vin.isEmpty ? (EtubuTeslaVinStore.vin ?? "") : telemetry.vin
            theme = ClusterTheme.stored
            EtubuClusterFonts.setTheme(theme)
            EtubuClusterAudioBridge.setLanguage(appLanguage.rawValue)
            EtubuClusterAudioBridge.setTheme(theme.webKey)
            if !showSim && !showLegal {
                startCoreIfNeeded()
            }
        }
        .onDisappear {
            warnings.stopPolling()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(clock) { now = $0 }
        .onChange(of: theme) { _, newValue in
            ClusterTheme.stored = newValue
            EtubuClusterFonts.setTheme(newValue)
            EtubuClusterAudioBridge.setTheme(newValue.webKey)
        }
        .onChange(of: appLanguage) { _, newValue in
            EtubuAppLanguage.current = newValue
            EtubuClusterAudioBridge.setLanguage(newValue.rawValue)
            l10nTick &+= 1
            if !newValue.criticalAlertsEnabled {
                warnings.clearCriticalAlerts()
                warnings.routeCoords = []
                telemetry.routeActive = false
                telemetry.routeFrom = ""
                telemetry.routeTo = ""
                showRoutePicker = false
                EtubuRouteBridge.clear()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
                ?? scenes.flatMap(\.windows).first
            let overlap: CGFloat
            if let window {
                let kb = window.convert(frame, from: nil)
                overlap = max(0, window.bounds.maxY - kb.minY)
            } else {
                overlap = max(0, UIScreen.main.bounds.height - frame.minY)
            }
            withAnimation(.easeOut(duration: 0.2)) {
                // Yatayda VIN kartı klavye üstünde kalsın — yüksekliği fazla kırpma
                let landscape = UIScreen.main.bounds.width > UIScreen.main.bounds.height
                keyboardInset = min(overlap, UIScreen.main.bounds.height * (landscape ? 0.72 : 0.55))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                keyboardInset = 0
            }
        }
    }

    private func startCoreIfNeeded() {
        tesla.bootstrapIfPossible()
        warnings.startPolling()
        EtubuRouteBridge.primeWarningAudio()
        EtubuClusterAudioBridge.armPowerRegenHook()
        EtubuMapLocationHelper.shared.startIfNeeded()
        UIApplication.shared.isIdleTimerDisabled = true
        if !locationEnabled {
            EtubuMapLocationHelper.shared.stop()
        }
        EtubuRouteBridge.status { st in
            telemetry.routeActive = st.active
            telemetry.routeFrom = st.fromLabel
            telemetry.routeTo = st.toLabel
        }
        EtubuRouteBridge.ensureIndex(completion: nil)
        startLiveActivityShell()
        EtubuClusterAudioBridge.setMixMode(mixMode)
        EtubuClusterAudioBridge.setAlertVolume(alertVolume)
        // Her açılışta sessiz — kayıtlı sesi otomatik çalma
        selectedVoice = "silent-mode"
        soundOn = false
        UserDefaults.standard.set("silent-mode", forKey: "etubu.cluster.voice")
        EtubuClusterAudioBridge.setSoundEnabled(false)
        EtubuClusterAudioBridge.setVoice("silent-mode")
    }

    /// Demo sürüşünü ana ekrandan durdur
    private var demoExitChip: some View {
        Button {
            demo.stop()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "stop.fill")
                    .font(.caption.weight(.bold))
                Text(EtubuClusterL10n.t("demoStop"))
                    .font(EtubuClusterFonts.ui(13, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.88))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(EtubuClusterL10n.t("demoStop"))
    }

    private static func applyLayoutBoost(landscape: Bool) {
        EtubuClusterFonts.layoutBoost = landscape ? 1.12 : 0.95
    }

    /// Menzil kritik (<100 km) — ekran kenarında yumuşak kırmızı pulse
    private var lowRangePulseOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.35 + 0.35 * abs(sin(t * 2.2))
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .strokeBorder(
                    Color.red.opacity(pulse),
                    lineWidth: 5 + CGFloat(pulse) * 6
                )
                .blur(radius: 8)
                .ignoresSafeArea()
                .opacity(0.85)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private func backgroundLayer(landscape: Bool) -> some View {
        ZStack {
            ClusterThemeBackdrop(theme: theme, landscape: landscape)

            if landscape {
                HStack(spacing: 0) {
                    Color.clear.frame(maxWidth: .infinity)
                    if mapEnabled {
                        mapBackdrop
                            .frame(maxWidth: .infinity)
                            .colorMultiply(Color(hue: theme.hue / 360, saturation: 0.25, brightness: 1))
                            .overlay(theme.accent.opacity(0.12).allowsHitTesting(false))
                            .mask(
                                LinearGradient(colors: [.clear, .black, .black], startPoint: .leading, endPoint: .trailing)
                            )
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .ignoresSafeArea()
            } else {
                // Portrait: map as ground wash (same idea as landscape half-map)
                if mapEnabled {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        mapBackdrop
                            .frame(maxWidth: .infinity)
                            .frame(height: min(420, UIScreen.main.bounds.height * 0.48))
                            .colorMultiply(Color(hue: theme.hue / 360, saturation: 0.22, brightness: 1))
                            .overlay(theme.accent.opacity(0.10).allowsHitTesting(false))
                            .mask(
                                LinearGradient(colors: [.clear, .black.opacity(0.55), .black], startPoint: .top, endPoint: .bottom)
                            )
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var mapBackdrop: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: .constant(mapCameraPosition), interactionModes: []) {
                if warnings.routeCoords.count >= 2 {
                    MapPolyline(coordinates: warnings.routeCoords)
                        .stroke(theme.accent.opacity(0.8), lineWidth: 3)
                }
                ForEach(criticalAlertsOn ? warnings.hazards.prefix(80) : []) { hazard in
                    Annotation("", coordinate: hazard.coordinate) {
                        EtubuMapHazardMark(kind: hazard.kind, theme: theme, compact: true)
                    }
                }
                if locationEnabled, let lat = telemetry.latitude, let lng = telemetry.longitude {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                        EtubuMapVehicleMark(headingDeg: telemetry.headingDeg)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
            .colorScheme(.dark)
            .saturation(0.2)
            .contrast(1.08)
            .allowsHitTesting(false)
            .overlay {
                Color.black.opacity(0.28).allowsHitTesting(false)
            }

            // OSM ODbL atıfı — harita üzerinde görünür ve tıklanabilir
            EtubuOsmAttributionChip(compact: true, theme: theme)
                .padding(8)
        }
    }

    private var mapCameraPosition: MapCameraPosition {
        if warnings.routeCoords.count >= 2 {
            let lats = warnings.routeCoords.map(\.latitude)
            let lngs = warnings.routeCoords.map(\.longitude)
            let minLat = lats.min() ?? 0
            let maxLat = lats.max() ?? 0
            let minLng = lngs.min() ?? 0
            let maxLng = lngs.max() ?? 0
            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLng + maxLng) / 2
            )
            let span = MKCoordinateSpan(
                latitudeDelta: max(0.04, (maxLat - minLat) * 1.35),
                longitudeDelta: max(0.04, (maxLng - minLng) * 1.35)
            )
            return .region(MKCoordinateRegion(center: center, span: span))
        }
        if let lat = telemetry.latitude, let lng = telemetry.longitude {
            return .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            ))
        }
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.0, longitude: 35.0),
            span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
        ))
    }

    // MARK: - Landscape

    private func landscapeLayout(size: CGSize, insets: EdgeInsets, cutoutEdge: HorizontalAlignment?) -> some View {
        let win = Self.windowSafeInsets()
        let leadIns = max(insets.leading, win.leading, 0)
        let trailIns = max(insets.trailing, win.trailing, 0)
        let topIns = max(insets.top, win.top, 0)
        let botIns = max(insets.bottom, win.bottom, 0)
        let edge: HorizontalAlignment = cutoutEdge ?? (leadIns > trailIns ? .leading : .trailing)
        // Camera gutter: keep chrome clear of island / notch on every phone size
        let camGutter = edge == .leading ? max(leadIns, 40) : max(trailIns, 40)
        let leadPad = edge == .leading ? max(camGutter + 4, 12) : max(leadIns + 6, 10)
        let trailPad: CGFloat = edge == .trailing ? max(camGutter + 4, 12) : max(trailIns + 6, 10)

        let usableW = max(220, size.width - leadPad - trailPad - 4)
        let usableH = max(140, size.height - topIns - botIns - 6)
        // Fit iPhone SE … Pro Max with one proportional scheme
        let layoutScale = min(1.12, max(0.70, min(usableW / 820, usableH / 360)))
        let dialMax = min(310, max(160, min(usableH * 0.74, usableW * 0.36) * layoutScale))
        let boxW = min(178, max(96, min(usableW * 0.17, dialMax * 0.58)))
        let remaining = max(80, usableW - dialMax - boxW - 16)
        let sideW = min(148, max(88, min(remaining * 0.48, usableW * 0.145)))

        return VStack(spacing: 0) {
            landscapeTopBar
                .padding(.horizontal, 2)
                .layoutPriority(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 4) {
                leftCardStack
                    .frame(width: sideW)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .modifier(SidePanelChrome())

                VStack(spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        speedDialWithThemeGesture(compact: true, diameter: dialMax)
                            .layoutPriority(2)

                        // Gidilen yol hız limiti — kadran ile ortalama hız arasında üstte
                        EtubuRoadSpeedLimitSign(size: max(28, min(40, dialMax * 0.14)))
                            .padding(.top, 2)
                            .onAppear {
                                EtubuOsmSpeedLimit.shared.refreshIfNeeded(
                                    lat: telemetry.latitude,
                                    lng: telemetry.longitude
                                )
                            }

                        twinCardsColumn(
                            dialSize: dialMax,
                            boxW: boxW,
                            contentScale: max(0.95, layoutScale * 1.15)
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .onChange(of: telemetry.latitude) { _, _ in
                        EtubuOsmSpeedLimit.shared.refreshIfNeeded(
                            lat: telemetry.latitude,
                            lng: telemetry.longitude
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

                navColumn
                    .frame(width: sideW)
                    .frame(maxHeight: .infinity, alignment: .topTrailing)
                    .modifier(SidePanelChrome(flushTrailing: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            landscapeBottomBar
                .padding(.horizontal, 4)
                .layoutPriority(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.leading, leadPad)
        .padding(.trailing, trailPad)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private struct SidePanelChrome: ViewModifier {
        var flushTrailing: Bool = false
        func body(content: Content) -> some View {
            content
                .padding(.leading, 3)
                .padding(.trailing, flushTrailing ? 0 : 3)
                .padding(.vertical, 3)
        }
    }

    private static func windowSafeInsets() -> EdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        guard let s = window?.safeAreaInsets else { return EdgeInsets() }
        return EdgeInsets(top: s.top, leading: s.left, bottom: s.bottom, trailing: s.right)
    }

    private var leftCardStack: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(leftCardPage.title)
                .font(EtubuClusterFonts.ui(10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(theme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Group {
                switch leftCardPage {
                case .tpms:
                    tpmsGrid
                case .telemetry:
                    VStack(alignment: .leading, spacing: 8) {
                        panelValueRow(telemetry.socPercent.map { "\($0)%" } ?? "—")
                        panelValueRow(telemetry.powerKw.map { "\($0) kW" } ?? "—")
                        panelValueRow({
                            let out = telemetry.outsideC.map { String(format: "%.0f°", $0) } ?? "—"
                            let inn = telemetry.insideC.map { String(format: "%.0f°", $0) } ?? "—"
                            return "\(out) / \(inn)"
                        }())
                        EtubuClosuresChip(telemetry: telemetry)
                    }
                case .trip:
                    VStack(alignment: .leading, spacing: 8) {
                        panelValueRow(telemetry.navRemainKm != nil ? telemetry.navRemainLabel : "—")
                        panelValueRow("\(warnings.corridorAvgKmh) km/h")
                        panelValueRow(telemetry.odometerKm.map { "\($0) km" } ?? "—")
                        EtubuPowerHistorySparkline(samples: telemetry.powerHistory)
                            .frame(height: 28)
                    }
                case .media:
                    VStack(alignment: .leading, spacing: 8) {
                        EtubuMediaNowPlayingView(telemetry: telemetry)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.22)) {
                cycleLeftCard(next: true)
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(EtubuClusterL10n.swipeCards)
        .animation(.easeInOut(duration: 0.22), value: leftCardPage)
    }

    private func cycleLeftCard(next: Bool) {
        let all = LeftCardPage.allCases
        guard let idx = all.firstIndex(of: leftCardPage) else { return }
        let n = next ? (idx + 1) % all.count : (idx - 1 + all.count) % all.count
        leftCardPage = all[n]
    }

    private func panelValueRow(_ value: String) -> some View {
        Text(value)
            .font(EtubuClusterFonts.ui(14, weight: .semibold))
            .foregroundStyle(theme.primaryText.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// Jul 29 twin panels — equal size, shared chrome, never overlap.
    private let twinCardGap: CGFloat = 8

    private func twinCardHeight(dialSize: CGFloat) -> CGFloat {
        max(56, (dialSize - twinCardGap) / 2)
    }

    private func twinCardsColumn(dialSize: CGFloat, boxW: CGFloat, contentScale: CGFloat) -> some View {
        let boxH = twinCardHeight(dialSize: dialSize)
        return VStack(spacing: twinCardGap) {
            avgSpeedCard(width: boxW, height: boxH, contentScale: contentScale)
            if criticalAlertsOn {
                roadWarningCard(width: boxW, height: boxH, contentScale: contentScale)
            } else {
                Color.clear.frame(width: boxW, height: boxH)
            }
        }
        .frame(width: boxW, height: dialSize, alignment: .top)
    }

    /// Jul 29 web-style avg panel (trip avg / corridor avg).
    private func avgSpeedCard(width: CGFloat, height: CGFloat, contentScale: CGFloat = 1) -> some View {
        let _ = l10nTick
        return EtubuCorridorChipView(
            warnings: warnings,
            theme: theme,
            compact: height < 100,
            contentScale: contentScale
        )
        .frame(width: width, height: height)
        .clipped()
    }

    /// Twin of avg — same chrome / size; content only under road-warnings title.
    private func roadWarningCard(width: CGFloat, height: CGFloat, contentScale: CGFloat = 1) -> some View {
        let _ = l10nTick
        return EtubuRoadWarnTwinView(
            warnings: warnings,
            theme: theme,
            compact: height < 100,
            contentScale: contentScale
        )
        .frame(width: width, height: height)
        .clipped()
    }

    private func speedDialWithThemeGesture(compact: Bool, diameter: CGFloat) -> some View {
        EtubuSpeedDialView(
            kmh: telemetry.kmh,
            gear: telemetry.gear,
            theme: theme,
            compact: compact,
            diameter: diameter,
            powerKw: telemetry.powerKw
        )
        .clusterHotspot(.dial)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { v in
                    let dy = v.translation.height
                    guard abs(dy) > 36, abs(dy) > abs(v.translation.width) else { return }
                    cycleTheme(next: dy < 0)
                }
        )
    }

    private func cycleTheme(next: Bool) {
        let all = ClusterTheme.allCases
        guard let idx = all.firstIndex(of: theme) else { return }
        let n = next ? (idx + 1) % all.count : (idx - 1 + all.count) % all.count
        withAnimation(.easeInOut(duration: 0.2)) {
            theme = all[n]
        }
    }

    private var landscapeTopBar: some View {
        HStack(spacing: 12) {
            Text(timeString)
                .font(EtubuClusterFonts.ui(15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.primaryText.opacity(0.9))
            Text(telemetry.outsideC.map { String(format: "%.0f°C", $0) } ?? "--°C")
                .font(EtubuClusterFonts.ui(15, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            if let inside = telemetry.insideC {
                Text(String(format: "iç %.0f°C", inside))
                    .font(EtubuClusterFonts.ui(12, weight: .medium))
                    .foregroundStyle(theme.mutedText)
            }
            Text(telemetry.connectionQualityLabel)
                .font(EtubuClusterFonts.ui(11, weight: .semibold))
                .foregroundStyle(statusColor.opacity(0.9))

            Spacer(minLength: 8)

            Button { showVINEditor = true } label: {
                EtubuPairConnectionBadge(
                    connectionState: telemetry.connectionState,
                    theme: theme,
                    label: pairLabel,
                    compact: true
                )
            }
            .clusterHotspot(.pair)

            if criticalAlertsOn {
                Button {
                    EtubuRouteBridge.primeWarningAudio()
                    showRoutePicker = true
                } label: {
                    Image(systemName: telemetry.routeActive ? "point.topleft.down.to.point.bottomright.curvepath.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(telemetry.routeActive ? theme.accent : theme.secondaryText)
                        .padding(8)
                        .background(Circle().fill(theme.surface))
                }
                .clusterHotspot(.route)
            }

            Text(batteryPhoneLabel)
                .font(EtubuClusterFonts.ui(12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.secondaryText)

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundStyle(theme.mutedText)
            }
            .clusterHotspot(.settings)
        }
    }

    private var navColumn: some View {
        let _ = l10nTick
        return VStack(alignment: .leading, spacing: 12) {
            navRow(EtubuClusterL10n.destination, value: {
                if !telemetry.navDestination.isEmpty { return telemetry.navDestination }
                if !telemetry.routeTo.isEmpty { return telemetry.routeTo }
                return "sadece il ilçe yazınız"
            }())
            navRow(EtubuClusterL10n.arrivalTime, value: telemetry.arrivalTimeLabel)
            navRow(EtubuClusterL10n.energyAtArrival, value: telemetry.energyAtArrivalPercent.map { "\($0)%" } ?? "—")
            navRow(EtubuClusterL10n.distance, value: {
                if telemetry.navRemainKm != nil { return telemetry.navRemainLabel }
                return telemetry.rangeKm.map { "\($0) \(EtubuClusterL10n.rangeKm)" } ?? "—"
            }())
            EtubuClosuresChip(telemetry: telemetry)
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }

    private func navRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(EtubuClusterFonts.ui(10, weight: .medium))
                .foregroundStyle(theme.mutedText)
            Text(value)
                .font(EtubuClusterFonts.ui(15, weight: .semibold))
                .foregroundStyle(theme.primaryText.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var landscapeBottomBar: some View {
        HStack(alignment: .center, spacing: 14) {
            soundControl(compact: true)
            HStack(spacing: 6) {
                Image(systemName: "battery.100")
                    .foregroundStyle(theme.accent)
                Text(batteryRangeLabel)
                    .font(EtubuClusterFonts.ui(15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText.opacity(0.9))
            }
            Spacer(minLength: 0)
            Text(telemetry.odometerKm.map { "ODO \($0) km" } ?? "ODO — km")
                .font(EtubuClusterFonts.ui(14, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.secondaryText)
        }
    }

    // MARK: - Portrait

    private func portraitLayout(size: CGSize, insets: EdgeInsets) -> some View {
        let short = size.height < 720
        let narrow = size.width < 390
        let layoutScale = min(1.08, max(0.78, min(size.width / 402, size.height / 874)))
        let portraitDialSize = min(short ? 220 : 290, size.width * (narrow ? 0.46 : 0.52)) * layoutScale
        let portraitBoxW = min(126, size.width * 0.27) * layoutScale
        let topChrome = max(insets.top + 8, 24)
        let cardScale = max(0.92, layoutScale * 1.02)

        return VStack(spacing: 0) {
            HStack {
                Button { showVINEditor = true } label: {
                    EtubuPairConnectionBadge(
                        connectionState: telemetry.connectionState,
                        theme: theme,
                        label: nil,
                        compact: true
                    )
                }
                .clusterHotspot(.pair)
                Spacer(minLength: 0)
                if criticalAlertsOn {
                    Button {
                        EtubuRouteBridge.primeWarningAudio()
                        showRoutePicker = true
                    } label: {
                        Image(systemName: telemetry.routeActive ? "map.fill" : "map")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(telemetry.routeActive ? theme.accent : theme.mutedText)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .clusterHotspot(.route)
                }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.mutedText)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .clusterHotspot(.settings)
            }
            .padding(.horizontal, 12)
            .padding(.top, topChrome)

            Spacer(minLength: short ? 2 : 6)

            HStack(alignment: .top, spacing: 6) {
                Spacer(minLength: 0)
                speedDialWithThemeGesture(compact: false, diameter: portraitDialSize)
                // Gidilen yol hız limiti — kadran ile ortalama hız arasında üstte (sadece ikon)
                EtubuRoadSpeedLimitSign(size: short ? 30 : 36)
                    .padding(.top, 4)
                    .onAppear {
                        EtubuOsmSpeedLimit.shared.refreshIfNeeded(
                            lat: telemetry.latitude,
                            lng: telemetry.longitude
                        )
                    }
                twinCardsColumn(
                    dialSize: portraitDialSize,
                    boxW: portraitBoxW,
                    contentScale: cardScale
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .onChange(of: telemetry.latitude) { _, _ in
                EtubuOsmSpeedLimit.shared.refreshIfNeeded(
                    lat: telemetry.latitude,
                    lng: telemetry.longitude
                )
            }

            EtubuPowerRegenBarView(powerKw: telemetry.powerKw, compact: short, theme: theme)
                .padding(.horizontal, 28)
                .padding(.top, short ? 4 : 8)
            if !short {
                EtubuPowerHistorySparkline(samples: telemetry.powerHistory)
                    .padding(.horizontal, 28)
            }
            EtubuChargeDetailChip(telemetry: telemetry)
                .padding(.top, 4)
            EtubuMediaNowPlayingView(telemetry: telemetry)
                .padding(.horizontal, 28)
                .padding(.top, 4)

            Spacer(minLength: short ? 6 : 12)

            HStack(alignment: .center, spacing: 12) {
                soundControl(compact: false)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 8)

            HStack(alignment: .bottom) {
                tpmsGrid
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(timeString)
                        .font(EtubuClusterFonts.gauge(short ? 28 : 36))
                        .monospacedDigit()
                        .foregroundStyle(theme.primaryText)
                        .shadow(color: theme.glow, radius: 8)
                    HStack(spacing: 6) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        Text(telemetry.rangeKm.map { "\($0) km" } ?? "— km")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(theme.accent)
                        Text(telemetry.socPercent.map { "\($0)%" } ?? "—")
                        Capsule()
                            .fill(theme.surface)
                            .frame(width: 56, height: 4)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(theme.accent)
                                    .frame(width: 56 * CGFloat(telemetry.socPercent ?? 0) / 100.0, height: 4)
                            }
                    }
                    .font(EtubuClusterFonts.ui(15, weight: .semibold))
                    .foregroundStyle(theme.primaryText.opacity(0.9))
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, max(12, insets.bottom + 8))
        }
        .safeAreaPadding(.top, 2)
    }

    private var tpmsGrid: some View {
        EtubuTPMSGridView(telemetry: telemetry)
    }

    // MARK: - Shared controls

    private func soundControl(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    soundOn.toggle()
                }
                toggleSound(soundOn)
            } label: {
                Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(compact ? .body.weight(.bold) : .title3.weight(.semibold))
                    .foregroundStyle(soundOn ? .black : .white)
                    .frame(width: compact ? 40 : 48, height: compact ? 40 : 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(soundOn ? theme.accent : Color.white.opacity(0.12))
                    )
            }
            .accessibilityLabel(soundOn ? "Ses açık" : "Ses kapalı")

            Button {
                cycleSoundProfile()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentSoundProfileLabel)
                        .font(EtubuClusterFonts.ui(compact ? 13 : 15, weight: .semibold))
                        .foregroundStyle(soundOn ? theme.primaryText : theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(soundOn ? EtubuClusterL10n.t("soundSelect") : "—")
                        .font(EtubuClusterFonts.ui(10, weight: .medium))
                        .foregroundStyle(theme.mutedText)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ses profili")
            .accessibilityHint("Dokunarak değiştir")
        }
        .clusterHotspot(.sound)
    }

    private var currentSoundProfileLabel: String {
        if let voice = EtubuSoundVoice.all.first(where: { $0.key == selectedVoice }) {
            return voice.localizedLabel
        }
        return EtubuClusterL10n.t("voiceSilentMode")
    }

    private func cycleSoundProfile() {
        let list = EtubuSoundVoice.all.filter { $0.key != "silent-mode" }
        guard !list.isEmpty else { return }
        let idx = list.firstIndex(where: { $0.key == selectedVoice }).map { $0 + 1 } ?? 0
        let next = list[idx % list.count]
        selectedVoice = next.key
        soundOn = true
        EtubuClusterAudioBridge.setVoice(next.key)
        EtubuClusterAudioBridge.pushDrive(
            kmh: telemetry.kmh,
            powerKw: telemetry.powerKw,
            source: telemetry.source.rawValue
        )
    }

    private var vinOverlay: some View {
        let kbOpen = keyboardInset > 40
        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    showVINEditor = false
                }

            VStack(spacing: 0) {
                if !kbOpen {
                    Spacer(minLength: 48)
                } else {
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Vehicle VIN")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Button("Close") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            showVINEditor = false
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent)
                    }
                    HStack(spacing: 10) {
                        TextField("5YJ…", text: $vinDraft)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .padding(12)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                            .focused($vinFocused)
                        Button {
                            vinFocused = false
                            Task { await tesla.saveVINAndPair(vinDraft) }
                        } label: {
                            Text("Pair")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(theme.accent, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    if kbOpen, !vinDraft.isEmpty {
                        Text(vinDraft)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }

                    if !kbOpen {
                        HStack(spacing: 10) {
                            Button {
                                Task { await tesla.connectSaved() }
                            } label: {
                                Text("Bağlan")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            }
                            Button {
                                Task { await tesla.repair() }
                            } label: {
                                Text("Yeniden eşleştir")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.orange.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        Text(telemetry.statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                        Text("NFC key card on console · data stays on device · not affiliated with Tesla")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.28))
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, kbOpen ? max(8, keyboardInset - 4) : 24)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                vinFocused = true
            }
        }
        .onDisappear { vinFocused = false }
    }

    private var pairGuideOverlay: some View {
        let pairHole = hotspotFrames[.pair]
        let sending = tesla.pairStep == .sendingRequest
        let waiting = tesla.pairStep == .waitingForCard
        let linking = tesla.pairStep == .connectingAfterCard
        let connected = telemetry.connectionState == .connected
        let step3Active = linking || connected
        let step2Done = linking || connected
        let step1Done = waiting || step2Done
        let ringColor = connected ? Color.green : theme.accent

        return ZStack(alignment: .bottom) {
            // Karartma + Pair kutucuğunda delik (dikey/yatay hotspot)
            GeometryReader { geo in
                let hole: CGRect = {
                    if let h = pairHole, h.width > 4, h.height > 4 {
                        return h.insetBy(dx: -10, dy: -10)
                    }
                    // Fallback: dikey sol üst / yatay sağ üst yaklaşık Pair yeri
                    let landscape = geo.size.width > geo.size.height
                    if landscape {
                        return CGRect(x: geo.size.width - 210, y: 8, width: 120, height: 40)
                    }
                    return CGRect(x: 10, y: 10, width: 48, height: 48)
                }()
                ZStack {
                    EtubuSpotlightHole(hole: hole, cornerRadius: min(22, hole.height * 0.48))
                        .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                        .ignoresSafeArea()
                        .allowsHitTesting(true)

                    // Pulse yalnızca Pair kutucuğunun çevresinde
                    EtubuPairSpotlightPulse(hole: hole, color: ringColor)
                        .allowsHitTesting(false)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    EtubuPairConnectionBadge(
                        connectionState: telemetry.connectionState,
                        theme: theme,
                        label: pairLabel,
                        compact: true,
                        showPulse: false
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Araç bağlantısı")
                            .font(EtubuClusterFonts.ui(18, weight: .bold))
                            .foregroundStyle(.white)
                        Text(pairGuideHeadline)
                            .font(EtubuClusterFonts.ui(12, weight: .medium))
                            .foregroundStyle(theme.mutedText)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 10) {
                    pairGuideStep(
                        n: 1,
                        title: "İstek gönderiliyor",
                        body: "Uygulama Tesla’ya BLE anahtar isteği yolluyor. Telefonda Bluetooth açık olsun; araca birkaç metre yaklaş.",
                        active: sending,
                        done: step1Done
                    )
                    pairGuideStep(
                        n: 2,
                        title: "Anahtar kartı",
                        body: "NFC key card’ı orta konsola dokundur. Araç ekranında anahtar onayı çıkınca onayla. Bu adım olmadan oturum açılmaz.",
                        active: waiting,
                        done: step2Done
                    )
                    pairGuideStep(
                        n: 3,
                        title: "Bağlandı",
                        body: "Üstteki Pair rozeti yeşile döner. Hız, vites, SoC ve rota verileri cluster’da canlı akar. Koparsa rozete tekrar dokun.",
                        active: step3Active,
                        done: connected
                    )
                }

                if !telemetry.statusMessage.isEmpty {
                    Text(telemetry.statusMessage)
                        .font(EtubuClusterFonts.ui(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if waiting {
                    Button {
                        Task { await tesla.confirmCardTapped() }
                    } label: {
                        Text("Kartı dokundum — bağlan")
                            .font(EtubuClusterFonts.ui(15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await tesla.retryPair() }
                    } label: {
                        Text("Yeniden dene")
                            .font(EtubuClusterFonts.ui(13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    Button {
                        Task { await tesla.disconnect() }
                    } label: {
                        Text("İptal")
                            .font(EtubuClusterFonts.ui(13, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.95))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                    Spacer()
                }

                Text("Veriler cihazda kalır · Tesla ile resmi bağlantı değildir")
                    .font(EtubuClusterFonts.ui(10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        (connected ? Color.green : theme.accent).opacity(0.55),
                                        theme.stroke.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: (connected ? Color.green : theme.accent).opacity(0.25), radius: 20, y: 8)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.35), value: tesla.pairStep)
        .animation(.easeInOut(duration: 0.35), value: telemetry.connectionState)
    }

    private var pairGuideHeadline: String {
        switch tesla.pairStep {
        case .sendingRequest: return "Anahtar isteği yolda…"
        case .waitingForCard: return "Kartı konsola dokundur"
        case .connectingAfterCard: return "Kart onaylandı — bağlanıyor"
        case .failed: return "Bağlantı kurulamadı — yeniden dene"
        case .none:
            if telemetry.connectionState == .connected { return "Oturum açık" }
            return "Pair akışı"
        }
    }

    private func pairGuideStep(n: Int, title: String, body: String, active: Bool, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green.opacity(0.9) : (active ? theme.accent : Color.white.opacity(0.12)))
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(n)")
                        .font(EtubuClusterFonts.ui(13, weight: .bold))
                        .foregroundStyle(active ? .black : .white.opacity(0.7))
                }
            }
            .shadow(color: (done ? Color.green : theme.accent).opacity(active || done ? 0.55 : 0), radius: active ? 10 : 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(EtubuClusterFonts.ui(14, weight: .bold))
                    .foregroundStyle(active || done ? .white : .white.opacity(0.55))
                Text(body)
                    .font(EtubuClusterFonts.ui(12, weight: .medium))
                    .foregroundStyle(active ? theme.secondaryText : .white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(active ? theme.accent.opacity(0.12) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(active ? theme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
                )
        )
    }

    private var settingsSheet: some View {
        let _ = l10nTick
        return NavigationStack {
            List {
                Section {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(EtubuAppSummary.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            EtubuOnboardScreenshotStrip(theme: theme, highlight: nil)
                            Divider()
                            EtubuOsmAttributionBlock()
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Label("Uygulama hakkında", systemImage: "info.circle")
                            .font(.body.weight(.semibold))
                    }
                }

                Section(EtubuClusterL10n.language) {
                    Picker(EtubuClusterL10n.language, selection: $appLanguage) {
                        ForEach(EtubuAppLanguage.allCases) { lang in
                            Text(lang.title).tag(lang)
                        }
                    }
                }
                Section(EtubuClusterL10n.theme) {
                    Picker(EtubuClusterL10n.theme, selection: $theme) {
                        ForEach(ClusterTheme.allCases) { t in
                            Text("\(t.title) · \(EtubuCutoutFX.forTheme(t).title)")
                                .tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section(EtubuClusterL10n.t("cameraEffect")) {
                    Toggle(EtubuClusterL10n.t("notchAuraToggle"), isOn: $notchAuraEnabled)
                    Text("\(theme.title) · \(EtubuCutoutFX.forTheme(theme).title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section(EtubuClusterL10n.t("mapFeatures")) {
                    Toggle(EtubuClusterL10n.t("mapEnabled"), isOn: $mapEnabled)
                    Text(EtubuClusterL10n.t("mapEnabledHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(EtubuClusterL10n.t("locationEnabled"), isOn: $locationEnabled)
                        .onChange(of: locationEnabled) { _, enabled in
                            EtubuMapLocationHelper.shared.setLocationEnabled(enabled)
                        }
                    Text(EtubuClusterL10n.t("locationEnabledHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    EtubuOsmAttributionBlock()
                        .padding(.top, 4)
                }
                Section(EtubuClusterL10n.t("soundSelect")) {
                    Picker(EtubuClusterL10n.t("soundSelect"), selection: $selectedVoice) {
                        ForEach(EtubuSoundVoice.groups, id: \.group) { group in
                            ForEach(group.voices) { voice in
                                Text("\(EtubuClusterL10n.t(group.labelKey)) — \(voice.localizedLabel)")
                                    .tag(voice.key)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedVoice) { _, key in
                        soundOn = key != "silent-mode"
                        EtubuClusterAudioBridge.setVoice(key)
                        if key != "silent-mode" {
                            EtubuClusterAudioBridge.setSoundEnabled(true, voice: key)
                            EtubuClusterAudioBridge.startDrive(
                                kmh: max(telemetry.kmh, 0),
                                gear: telemetry.gear,
                                source: telemetry.source.rawValue,
                                powerKw: telemetry.powerKw
                            )
                        } else {
                            EtubuClusterAudioBridge.setSoundEnabled(false, voice: "silent-mode")
                        }
                    }
                }
                Section(EtubuClusterL10n.audioMix) {
                    Picker(EtubuClusterL10n.audioMix, selection: $mixMode) {
                        Text(EtubuClusterL10n.t("mixBlend")).tag("blend")
                        Text(EtubuClusterL10n.t("mixUnder")).tag("under")
                        Text(EtubuClusterL10n.t("mixSolo")).tag("solo")
                    }
                    .onChange(of: mixMode) { _, v in EtubuClusterAudioBridge.setMixMode(v) }
                    Toggle(EtubuClusterL10n.alertsOverMusic, isOn: $alertOverMusic)
                        .onChange(of: alertOverMusic) { _, on in
                            // blend = müzik üstüne yaz; solo = yalnız uyarı
                            let mode = on ? "blend" : mixMode
                            mixMode = on ? "blend" : mixMode
                            EtubuClusterAudioBridge.setMixMode(on ? "blend" : mode)
                            AppDelegate.activateDriveAudioSession()
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(EtubuClusterL10n.alertDuck)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $alertVolume, in: 0.2...1.0, step: 0.05)
                            .tint(theme.accent)
                            .onChange(of: alertVolume) { _, v in
                                EtubuClusterAudioBridge.setAlertVolume(v)
                            }
                    }
                }
                Section("Demo") {
                    Toggle("Demo sürüşü", isOn: Binding(
                        get: { demo.isRunning },
                        set: { on in if on { demo.start() } else { demo.stop() } }
                    ))
                    Toggle("Aynalama (ters yansıtma)", isOn: $demo.mirrorEnabled)
                    Text("Hızlanma, yavaşlama, radar/koridor/şarj/hava/kontrol uyarıları simüle edilir.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if criticalAlertsOn {
                    EtubuRadarSettingsView()
                }
                Section(EtubuClusterL10n.connection) {
                    LabeledContent(EtubuClusterL10n.quality, value: telemetry.connectionQualityLabel)
                    LabeledContent(EtubuClusterL10n.source, value: telemetry.source.rawValue)
                }
                Section(EtubuClusterL10n.vehicle) {
                    Button(EtubuClusterL10n.pairVin) { showSettings = false; showVINEditor = true }
                    if criticalAlertsOn {
                        Button(EtubuClusterL10n.pickRoute) {
                            showSettings = false
                            EtubuRouteBridge.primeWarningAudio()
                            showRoutePicker = true
                        }
                    }
                    Button(EtubuClusterL10n.reconnectTesla) { Task { await tesla.connectSaved() } }
                    Button(EtubuClusterL10n.disconnectTesla) { Task { await tesla.disconnect() } }
                    Button(EtubuClusterL10n.forgetVehicle, role: .destructive) {
                        Task { await tesla.clearVehicle() }
                        showVINEditor = true
                    }
                    Button(EtubuClusterL10n.obdFallback) { showObdMenu = true }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    EtubuBrandMark(size: 28, showGlow: true)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(EtubuClusterL10n.done) { showSettings = false }
                }
            }
        }
    }

    // MARK: - Helpers

    private var connectionDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 7, height: 7)
    }

    private var statusColor: Color {
        switch telemetry.connectionState {
        case .connected: return .green
        case .connecting, .pairing, .reconnecting, .waitingForCard: return .orange
        case .failed: return .red
        default: return .gray
        }
    }

    private var pairLabel: String {
        switch telemetry.connectionState {
        case .connected: return telemetry.deviceLabel
        case .pairing, .waitingForCard: return EtubuClusterL10n.pairing
        case .reconnecting: return EtubuClusterL10n.reconnecting
        default: return EtubuClusterL10n.pairVehicle
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: now)
    }

    private var batteryRangeLabel: String {
        let soc = telemetry.socPercent.map { "\($0)%" } ?? "--%"
        let range = telemetry.rangeKm.map { "\($0) km" } ?? "--km"
        return "\(soc) / \(range)"
    }

    private var batteryPhoneLabel: String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level < 0 { return "" }
        return "\(Int(level * 100))"
    }

    private func toggleSound(_ on: Bool) {
        if on {
            let voice = selectedVoice == "silent-mode" ? "asphalt-roar" : selectedVoice
            if selectedVoice == "silent-mode" {
                selectedVoice = voice
            }
            EtubuClusterAudioBridge.setSoundEnabled(true, voice: voice)
            EtubuClusterAudioBridge.pushDrive(
                kmh: telemetry.kmh,
                powerKw: telemetry.powerKw,
                source: telemetry.source.rawValue
            )
        } else {
            EtubuClusterAudioBridge.setSoundEnabled(false)
        }
    }

    private func startLiveActivityShell() {
        // Dynamic Island / Live Activity yalnızca AppDelegate arka planında başlar.
        // Ön planda başlatma → uygulama kapanınca da kalıyordu.
    }
}
