import SwiftUI
import MapKit
import CoreLocation
import UIKit
import StoreKit

struct EtubuClusterRootView: View {
    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @ObservedObject private var tesla = EtubuTeslaBleSession.shared
    @ObservedObject private var warnings = EtubuDriveWarnings.shared
    @ObservedObject private var demo = EtubuDemoDrive.shared
    @ObservedObject private var evPlan = EtubuEvRoutePlanner.shared
    @ObservedObject private var trips = EtubuTripHistoryStore.shared
    @ObservedObject private var premium = EtubuPremiumManager.shared

    @State private var theme: ClusterTheme = ClusterTheme.stored
    @State private var wallpaper: EtubuWallpaperStyle = EtubuWallpaperStyle.stored
    @State private var vinDraft: String = ""
    @State private var showVINEditor = false
    @State private var showSettings = false
    @State private var showPremiumPaywall = false
    @State private var premiumPaywallHint: String? = nil
    @State private var mixMode: String = "blend"
    @State private var soundOn = false
    @State private var selectedVoice: String = EtubuClusterAudioBridge.storedVoice
    @State private var showEvSoundTip = false
    @State private var showDiscoverTip = false
    @State private var showObdMenu = false
    @State private var showRoutePicker = false
    @State private var showRemoteCommands = false
    @State private var now = Date()
    @State private var appLanguage: EtubuAppLanguage = EtubuAppLanguage.current
    @ObservedObject private var legalGate = EtubuLegalGate.shared
    @State private var showLegalOverlay = !EtubuLegalAcceptance.isAccepted
    private var showLegal: Bool { showLegalOverlay && !legalGate.accepted }
    @State private var simDone = {
        if EtubuClusterSimView.isDone { return true }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-etubuSkipOnboarding") || args.contains("etubuSkipOnboarding") { return true }
        if UserDefaults.standard.object(forKey: "etubuSkipOnboarding") != nil {
            return UserDefaults.standard.bool(forKey: "etubuSkipOnboarding")
        }
        return false
    }()
    /// AppStorage mirror — finish() UserDefaults yazınca SwiftUI mutlaka yeniden çizsin (Maestro tap).
    @AppStorage(EtubuClusterSimView.doneKey) private var simDoneStored = false
    private var showSim: Bool { !simDone && !simDoneStored }
    @State private var remoteChargeLimit: Double = 80
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
    @AppStorage("etubu.demo.running") private var demoRunningUD = false
    @AppStorage("etubu.demo.kmh") private var demoKmhUD = 0
    /// MapKit thrash önleme — kamera yalnızca anlamlı konum/rota değişiminde güncellenir.
    @State private var throttledMapCamera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.0, longitude: 35.0),
            span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
        )
    )
    @State private var lastMapCenter: CLLocationCoordinate2D?
    @State private var lastMapRouteCount: Int = 0
    @State private var lastMapHeading: Double = 0
    @AppStorage("etubu.demo.gear") private var demoGearUD = "P"
    @AppStorage("etubu.demo.power") private var demoPowerUD = 0

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var criticalAlertsOn: Bool { appLanguage.criticalAlertsEnabled }
    private var mapBackdropEnabled: Bool { premium.isPremium && mapEnabled }
    private var shouldShowPairGuide: Bool { tesla.pairStep != .none }

    private func openPremium(hintKey: String? = nil) {
        premiumPaywallHint = hintKey.map { EtubuClusterL10n.t($0) }
        showPremiumPaywall = true
    }

    private func openRouteOrPaywall() {
        if premium.isPremium {
            showRoutePicker = true
            return
        }
        // Cold start: wait for StoreKit probe before flashing paywall (cached unlock already set isPremium).
        if !premium.entitlementReady {
            Task { @MainActor in
                await premium.ensureEntitlementChecked()
                openRouteOrPaywall()
            }
            return
        }
        openPremium(hintKey: "premiumLockedRoute")
    }

    private var dialKmh: Int {
        if warnings.demoActive { return warnings.demoKmh < 5 ? 0 : warnings.demoKmh }
        let _ = telemetry.demoUIEpoch
        if EtubuDemoDrive.isActive || UserDefaults.standard.bool(forKey: "etubu.demo.running") {
            let v = UserDefaults.standard.integer(forKey: "etubu.demo.kmh")
            let raw = v > 0 ? v : max(demo.displayKmh, demoKmhUD)
            return raw < 5 ? 0 : raw
        }
        let g = telemetry.gear.uppercased()
        if g.hasPrefix("P") || g.hasPrefix("N") { return 0 }
        return telemetry.kmh < 5 ? 0 : telemetry.kmh
    }
    private var dialGear: String {
        if warnings.demoActive {
            let g = warnings.demoGear
            if (g.isEmpty || g == "P"), warnings.demoKmh >= 3 { return "D" }
            return g.isEmpty ? "D" : g
        }
        let _ = telemetry.demoUIEpoch
        if EtubuDemoDrive.isActive || UserDefaults.standard.bool(forKey: "etubu.demo.running") {
            let g = UserDefaults.standard.string(forKey: "etubu.demo.gear") ?? demo.displayGear
            let kmh = UserDefaults.standard.integer(forKey: "etubu.demo.kmh")
            if (g.isEmpty || g == "P"), kmh >= 3 { return "D" }
            return g.isEmpty ? "D" : g
        }
        return telemetry.gear
    }
    private var dialPowerKw: Int? {
        if warnings.demoActive { return warnings.demoPowerKw }
        let _ = telemetry.demoUIEpoch
        if EtubuDemoDrive.isActive || UserDefaults.standard.bool(forKey: "etubu.demo.running") {
            return UserDefaults.standard.integer(forKey: "etubu.demo.power")
        }
        return telemetry.powerKw
    }

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
            // Hosting overlay often zeros SwiftUI safeAreaInsets — use window insets.
            let win = Self.windowSafeInsets()
            let insets = EdgeInsets(
                top: max(geo.safeAreaInsets.top, win.top),
                leading: max(geo.safeAreaInsets.leading, win.leading),
                bottom: max(geo.safeAreaInsets.bottom, win.bottom),
                trailing: max(geo.safeAreaInsets.trailing, win.trailing)
            )
            // Portrait: çentik / DI aura kapalı — yalnızca yatayda.
            let cutout = notchAuraEnabled && landscape && !showLegal && !showSim
                ? EtubuCameraCutout.resolve(size: geo.size, insets: insets, landscape: landscape)
                : nil
            let layout = EtubuClusterLayoutMetrics.make(
                size: geo.size,
                insets: insets,
                landscape: landscape,
                cutout: cutout
            )

            ZStack {
                theme.canvas.ignoresSafeArea()
                // Hard fallback so a failed layout never reads as an empty black Cap shell.
                if geo.size.width < 40 || geo.size.height < 40 {
                    VStack(spacing: 10) {
                        Text("Etubu")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(theme.accent)
                        ProgressView()
                            .tint(theme.accent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // Map / heavy chrome only after legal + sim gates — avoids black MapKit tiles
                // and location-prompt stacking over an empty dark shell.
                if !showLegal && !showSim {
                    backgroundLayer(landscape: landscape, mapWashHeight: layout.mapWashHeight)
                } else {
                    ClusterThemeBackdrop(theme: theme, landscape: landscape, wallpaper: wallpaper)
                }

                Group {
                    if !showLegal && !showSim {
                        if landscape {
                            landscapeLayout(layout)
                        } else {
                            portraitLayout(layout)
                        }
                    }
                }
                // Capture all taps in the chrome layer (Map backdrop must not steal Simulator clicks).
                .contentShape(Rectangle())
                // Portrait: content already pads island; avoid double-push on top chrome.
                .padding(.top, landscape ? max(insets.top, 4) : (cutout?.anchor == .bottom ? max(insets.top, 4) : 4))
                .padding(.bottom, max(insets.bottom, cutout?.anchor == .bottom ? 4 : 4))
                .padding(.leading, landscape ? 0 : layout.leadPad)
                .padding(.trailing, landscape ? 0 : layout.trailPad)
                .scaleEffect(x: demo.mirrorEnabled ? -1 : 1, y: 1)

                if let cutout {
                    EtubuNotchAuraView(kmh: telemetry.kmh, theme: theme, cutout: cutout)
                        .frame(width: cutout.aura.width, height: cutout.aura.height)
                        // Aura rect is built around the hardware pill; mid matches pill mid
                        // when spill is symmetric (portrait DI + landscape).
                        .position(x: cutout.aura.midX, y: cutout.aura.midY)
                        .allowsHitTesting(false)
                        .zIndex(5)
                }

                // Demo stop chip lives in top chrome (portrait/landscape) — Map overlay
                // accessibility often hides a free-floating ZStack button.

                // Menzil < 100 km → çevrede kırmızı pulse
                if let range = telemetry.rangeKm, range > 0, range < 100 {
                    lowRangePulseOverlay
                        .allowsHitTesting(false)
                        .zIndex(4)
                }

                if showEvSoundTip && !soundOn && !showLegal && !showSim {
                    VStack {
                        Spacer()
                            .allowsHitTesting(false)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(theme.accent)
                            Text(EtubuClusterL10n.t("evSoundTip"))
                                .font(EtubuClusterFonts.ui(12, weight: .semibold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button {
                                withAnimation { showEvSoundTip = false }
                                UserDefaults.standard.set(true, forKey: "etubu.evSound.tipSeen")
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(6)
                            }
                            .accessibilityIdentifier("etubu.sound.tip.dismiss")
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.78))
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 72)
                        .accessibilityIdentifier("etubu.sound.tip")
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(12)
                }

                if showDiscoverTip && !showEvSoundTip && !showLegal && !showSim && !shouldShowPairGuide {
                    VStack {
                        Spacer()
                            .allowsHitTesting(false)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "hand.tap.fill")
                                .foregroundStyle(theme.accent)
                            Text(EtubuClusterL10n.t("discoverPairRouteTip"))
                                .font(EtubuClusterFonts.ui(12, weight: .semibold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button {
                                withAnimation { showDiscoverTip = false }
                                UserDefaults.standard.set(true, forKey: "etubu.discover.pairRouteSeen")
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(6)
                            }
                            .accessibilityIdentifier("etubu.discover.tip.dismiss")
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.78))
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 72)
                        .accessibilityIdentifier("etubu.discover.tip")
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(11)
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

                if showLegal {
                    EtubuLegalAcceptanceView(theme: theme) {
                        // Sim henüz bitmediyse core’u sim bitince başlat.
                        if simDone { startCoreIfNeeded() }
                    }
                    .zIndex(50)
                }

                if !showLegal && showSim {
                    EtubuClusterSimView(theme: theme) {
                        simDone = true
                        simDoneStored = true
                        startCoreIfNeeded()
                    }
                    .zIndex(45)
                }
            }
            .coordinateSpace(name: "etubuCluster")
            .onPreferenceChange(EtubuHotspotFramesKey.self) { next in
                guard next != hotspotFrames else { return }
                hotspotFrames = next
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .frame(width: max(geo.size.width, 1), height: max(geo.size.height, 1))
            .ignoresSafeArea()
            .environment(\.clusterTheme, theme)
            .tint(theme.accent)
            .onAppear {
                layout.applyFontScale()
            }
            .onChange(of: layout.fontScale) { _, _ in
                layout.applyFontScale()
            }
            .onChange(of: landscape) { _, _ in
                layout.applyFontScale()
            }
            .sheet(isPresented: $showSettings) {
                settingsSheet
                    .tint(theme.accent)
                    .environment(\.clusterTheme, theme)
                    .id(appLanguage)
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPremiumPaywall) {
                EtubuPremiumPaywallView(accent: theme.accent, highlight: premiumPaywallHint)
                    .tint(theme.accent)
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showRoutePicker) {
                EtubuRoutePickerView()
            }
            .sheet(isPresented: $showRemoteCommands) {
                NavigationStack {
                    List {
                        Section(EtubuClusterL10n.t("remoteCmdSection")) {
                            EtubuRemoteCommandCards(tesla: tesla)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(EtubuClusterL10n.t("cmdChargeLimit"))
                                    Spacer()
                                    Text("\(Int(remoteChargeLimit))%")
                                        .monospacedDigit()
                                }
                                Slider(value: $remoteChargeLimit, in: 50...100, step: 5)
                                Button(EtubuClusterL10n.t("cmdApplyLimit")) {
                                    Task { await tesla.setChargeLimit(Int(remoteChargeLimit)) }
                                }
                            }
                        }
                    }
                    .navigationTitle(EtubuClusterL10n.t("remoteCmdSection"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(EtubuClusterL10n.done) { showRemoteCommands = false }
                        }
                    }
                }
                .tint(theme.accent)
                .environment(\.clusterTheme, theme)
                .id(appLanguage)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .accessibilityIdentifier("etubu.remote.sheet")
            }
            .offerCodeRedemption(isPresented: Binding(
                get: { premium.offerCodeRedeemPresented },
                set: { premium.offerCodeRedeemPresented = $0 }
            )) { result in
                premium.handleOfferCodeRedeemResult(result)
            }
            .onChange(of: premium.isPremium) { _, isPrem in
                if isPrem { premium.offerCodeRedeemPresented = false }
            }
            .confirmationDialog(EtubuClusterL10n.t("obdDialogTitle"), isPresented: $showObdMenu, titleVisibility: .visible) {
                Button(EtubuClusterL10n.t("obdConnect")) { EtubuObdBleManager.shared.connect { _, _ in } }
                Button(EtubuClusterL10n.t("obdDisconnect"), role: .destructive) { EtubuObdBleManager.shared.disconnect() }
                Button(EtubuClusterL10n.t("cancel"), role: .cancel) {}
            }
        }
        .ignoresSafeArea(.container)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            if EtubuLegalAcceptance.isAccepted {
                legalGate.accepted = true
                showLegalOverlay = false
            }
            vinDraft = telemetry.vin.isEmpty ? (EtubuTeslaVinStore.vin ?? "") : telemetry.vin
            premium.enforceFreeThemeIfNeeded()
            theme = ClusterTheme.stored
            wallpaper = EtubuWallpaperStyle.stored
            EtubuClusterFonts.setTheme(theme)
            EtubuClusterAudioBridge.setLanguage(appLanguage.rawValue)
            EtubuClusterAudioBridge.setTheme(theme.webKey)
            EtubuClusterAudioBridge.setPremium(premium.isPremium)
            syncThrottledMapCamera(force: true)
            if !showSim && !showLegal {
                startCoreIfNeeded()
            }
        }
        .onChange(of: premium.isPremium) { _, on in
            EtubuClusterAudioBridge.setPremium(on)
            if !on {
                premium.enforceFreeThemeIfNeeded()
                theme = EtubuPremiumManager.freeTheme
                wallpaper = .atmospheric
            }
        }
        .onChange(of: telemetry.latitude) { _, _ in syncThrottledMapCamera() }
        .onChange(of: telemetry.longitude) { _, _ in syncThrottledMapCamera() }
        .onChange(of: telemetry.headingDeg) { _, _ in syncThrottledMapCamera() }
        .onChange(of: warnings.routeCoords.count) { _, _ in syncThrottledMapCamera(force: true) }
        .onChange(of: demo.isRunning) { _, running in
            if running {
                selectedVoice = EtubuClusterAudioBridge.defaultDriveVoice
                soundOn = true
            } else {
                syncSoundUIFromPreference()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .etubuDemoSoundArmed)) { _ in
            selectedVoice = EtubuClusterAudioBridge.defaultDriveVoice
            soundOn = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .etubuDemoSoundDisarmed)) { _ in
            syncSoundUIFromPreference()
        }
        .onReceive(NotificationCenter.default.publisher(for: .etubuSimFinished)) { _ in
            simDone = true
            simDoneStored = true
            if !showLegal { startCoreIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .etubuLegalAccepted)) { _ in
            legalGate.accepted = true
            showLegalOverlay = false
            if simDone { startCoreIfNeeded() }
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
            // Tema = ses paketi (RevHeadz: karakter seçimi görsel temaya bağlı)
            if soundOn {
                let pack = newValue.driveVoiceKey
                selectedVoice = pack
                EtubuClusterAudioBridge.setVoice(pack)
                EtubuClusterAudioBridge.setSoundEnabled(true, voice: pack)
            }
        }
        .onChange(of: wallpaper) { _, newValue in
            EtubuWallpaperStyle.stored = newValue
        }
        .onChange(of: appLanguage) { _, newValue in
            // Manuel dil: Picker Binding → setManual. Otomatik dil: GPS → notification.
            if EtubuAppLanguage.current != newValue {
                EtubuAppLanguage.current = newValue
            }
            EtubuClusterAudioBridge.setLanguage(newValue.rawValue)
            if !newValue.warnTtsEnabled {
                EtubuWarnVoice.stopAll()
            }
            EtubuDriveWarnings.shared.relocalizeVisibleTitles()
            l10nTick &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .etubuLanguageDidChange)) { _ in
            let lang = EtubuAppLanguage.current
            if appLanguage != lang {
                appLanguage = lang
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
                let scenes2 = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                let bounds = (scenes2.first(where: { $0.activationState == .foregroundActive }) ?? scenes2.first)?
                    .coordinateSpace.bounds
                    ?? UIScreen.main.bounds
                let landscape = bounds.width > bounds.height
                keyboardInset = min(overlap, bounds.height * (landscape ? 0.72 : 0.55))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                keyboardInset = 0
            }
        }
    }

    private func startCoreIfNeeded() {
        // Process-lifetime once — double legal accept / sim finish must not re-arm Cap.
        guard !Self.didStartCore else { return }
        Self.didStartCore = true
        EtubuVehicleTelemetry.shared.scrubDemoChargeResidueIfNeeded()
        EtubuClusterPresenter.shared.armCapGeolocation()
        EtubuCapBridgeViewController.armWebContent()
        // Konum + Bluetooth izinlerini hemen iste; Tesla bağlanmayı BT diyaloguna bağlama.
        EtubuMapLocationHelper.shared.startIfNeeded()
        Task { @MainActor in
            _ = await EtubuBluetoothGate.shared.waitUntilReady(timeoutSeconds: 14)
        }
        tesla.bootstrapIfPossible(reason: .autoLaunch)
        warnings.startPolling()
        EtubuRouteBridge.primeWarningAudio()
        EtubuClusterAudioBridge.armPowerRegenHook()
        UIApplication.shared.isIdleTimerDisabled = true
        if !locationEnabled {
            EtubuMapLocationHelper.shared.stop()
        }
        EtubuRouteBridge.pushNativeLocationToWeb()
        EtubuRouteBridge.status { st in
            telemetry.routeActive = st.active
            telemetry.routeFrom = st.fromLabel
            telemetry.routeTo = st.toLabel
            telemetry.navDestination = st.toLabel
        }
        EtubuRouteBridge.ensureIndex(completion: nil)
        startLiveActivityShell()
        EtubuClusterAudioBridge.setMixMode(mixMode)
        EtubuClusterAudioBridge.setAlertVolume(alertVolume)
        // Bildirim izni ana ekranı engellemesin — yalnızca Ayarlar’da açılınca veya
        // arka planda araç bağlanınca (EtubuVehicleLaunchNotifier) istenir.
        // Ses tercihi korunur — her açılışta zorla sessize alma.
        if EtubuClusterAudioBridge.isSoundWanted {
            let voice = EtubuClusterAudioBridge.storedVoice
            selectedVoice = (voice.isEmpty || voice == "silent-mode")
                ? EtubuClusterAudioBridge.defaultDriveVoice : voice
            soundOn = true
        } else {
            selectedVoice = "silent-mode"
            soundOn = false
            EtubuClusterAudioBridge.setSoundEnabled(false)
            EtubuClusterAudioBridge.setVoice("silent-mode")
            // One-shot discoverability — EV sound defaults off (skip under Maestro).
            let args = ProcessInfo.processInfo.arguments
            let maestro = args.contains("etubuSkipOnboarding") || args.contains("-etubuSkipOnboarding")
                || args.contains("etubuForcePremium") || args.contains("-etubuForcePremium")
            if !maestro, !UserDefaults.standard.bool(forKey: "etubu.evSound.tipSeen") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    guard !EtubuClusterAudioBridge.isSoundWanted else { return }
                    guard !UserDefaults.standard.bool(forKey: "etubu.evSound.tipSeen") else { return }
                    withAnimation(.easeOut(duration: 0.25)) { showEvSoundTip = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                        guard showEvSoundTip else { return }
                        withAnimation { showEvSoundTip = false }
                        UserDefaults.standard.set(true, forKey: "etubu.evSound.tipSeen")
                    }
                }
            }
            // One-shot Pair/Route discoverability (after sound tip window).
            if !maestro, !UserDefaults.standard.bool(forKey: "etubu.discover.pairRouteSeen") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.5) {
                    guard !UserDefaults.standard.bool(forKey: "etubu.discover.pairRouteSeen") else { return }
                    guard !showEvSoundTip, !shouldShowPairGuide else { return }
                    withAnimation(.easeOut(duration: 0.25)) { showDiscoverTip = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                        guard showDiscoverTip else { return }
                        withAnimation { showDiscoverTip = false }
                        UserDefaults.standard.set(true, forKey: "etubu.discover.pairRouteSeen")
                    }
                }
            }
        }
        // Stale demo flag (crash / kill) — temiz başla
        if !EtubuDemoDrive.shared.isRunning {
            UserDefaults.standard.set(false, forKey: "etubu.demo.running")
            UserDefaults.standard.set(0, forKey: "etubu.demo.kmh")
            UserDefaults.standard.set("P", forKey: "etubu.demo.gear")
            UserDefaults.standard.set(0, forKey: "etubu.demo.power")
        }
    }

    private static var didStartCore = false

    private static func applyLayoutBoost(landscape: Bool) {
        // Legacy path — prefer EtubuClusterLayoutMetrics.applyFontScale().
        let next: CGFloat = landscape ? 1.12 : 0.95
        EtubuClusterFonts.setContentScale(next)
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
    private func backgroundLayer(landscape: Bool, mapWashHeight: CGFloat) -> some View {
        ZStack {
            ClusterThemeBackdrop(theme: theme, landscape: landscape, wallpaper: wallpaper)

            if landscape {
                HStack(spacing: 0) {
                    Color.clear.frame(maxWidth: .infinity)
                    if mapBackdropEnabled {
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
                if mapBackdropEnabled {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        mapBackdrop
                            .frame(maxWidth: .infinity)
                            .frame(height: mapWashHeight)
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
            Map(position: $throttledMapCamera, interactionModes: []) {
                if warnings.routeCoords.count >= 2 {
                    MapPolyline(coordinates: Self.decimateRoute(warnings.routeCoords, maxPoints: 180))
                        .stroke(theme.accent.opacity(0.8), lineWidth: 3)
                }
                ForEach(
                    criticalAlertsOn
                        ? Array((warnings.remainingHazards.isEmpty ? warnings.hazards : warnings.remainingHazards)
                            .prefix(EtubuRuntimeProfile.isSimulator ? 8 : 16))
                        : []
                ) { hazard in
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
        computeDesiredMapCamera()
    }

    private func computeDesiredMapCamera() -> MapCameraPosition {
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

    /// ~40 m / 18° heading / rota değişiminde kamera güncelle — MapKit thrash azaltır.
    private func syncThrottledMapCamera(force: Bool = false) {
        let desired = computeDesiredMapCamera()
        let routeCount = warnings.routeCoords.count
        if routeCount >= 2 {
            if force || routeCount != lastMapRouteCount {
                lastMapRouteCount = routeCount
                throttledMapCamera = desired
                if let lat = telemetry.latitude, let lng = telemetry.longitude {
                    lastMapCenter = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
            }
            return
        }
        lastMapRouteCount = 0
        guard let lat = telemetry.latitude, let lng = telemetry.longitude else {
            if force { throttledMapCamera = desired }
            return
        }
        let next = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let heading = telemetry.headingDeg ?? lastMapHeading
        let movedM: Double = {
            guard let prev = lastMapCenter else { return 9999 }
            let a = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            let b = CLLocation(latitude: next.latitude, longitude: next.longitude)
            return a.distance(from: b)
        }()
        let headingDelta = abs(heading - lastMapHeading)
        if force || movedM >= 40 || headingDelta >= 18 {
            lastMapCenter = next
            lastMapHeading = heading
            throttledMapCamera = desired
        }
    }

    /// Harita çizimi için rota noktalarını seyrelt (MapKit thrash azaltır).
    private static func decimateRoute(_ coords: [CLLocationCoordinate2D], maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard coords.count > maxPoints, maxPoints > 2 else { return coords }
        let step = Double(coords.count - 1) / Double(maxPoints - 1)
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(maxPoints)
        for i in 0..<maxPoints {
            let idx = min(coords.count - 1, Int((Double(i) * step).rounded()))
            out.append(coords[idx])
        }
        return out
    }

    // MARK: - Landscape

    private func landscapeLayout(_ layout: EtubuClusterLayoutMetrics) -> some View {
        let dialMax = layout.dialSize
        let dialBase = layout.dialChrome
        let boxW = layout.boxW
        let sideW = layout.sideW
        let layoutScale = layout.scale

        return VStack(spacing: 0) {
            landscapeTopBar
                .padding(.horizontal, 2)
                .layoutPriority(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: layout.isCompactWidth ? 2 : 4) {
                leftCardStack
                    .frame(width: sideW)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .modifier(SidePanelChrome())

                VStack(spacing: layout.contentVGap) {
                    HStack(alignment: .top, spacing: layout.isCompactWidth ? 4 : 8) {
                        speedDialWithThemeGesture(
                            compact: true,
                            diameter: dialMax,
                            chromeDiameter: dialBase
                        )
                            .layoutPriority(2)

                        // Gidilen yol hız limiti — kadran ile ortalama hız arasında üstte
                        EtubuRoadSpeedLimitSign(size: layout.signSize)
                            .padding(.top, 2)
                            .onAppear {
                                EtubuOsmSpeedLimit.shared.refreshIfNeeded(
                                    lat: telemetry.latitude,
                                    lng: telemetry.longitude,
                                    speedKmh: telemetry.kmh
                                )
                            }

                        twinCardsColumn(
                            dialSize: dialBase,
                            boxW: boxW,
                            contentScale: max(0.88, layoutScale * 1.12)
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .onChange(of: telemetry.latitude) { _, _ in
                        EtubuOsmSpeedLimit.shared.refreshIfNeeded(
                            lat: telemetry.latitude,
                            lng: telemetry.longitude,
                            speedKmh: telemetry.kmh
                        )
                    }
                    .onChange(of: telemetry.kmh) { _, kmh in
                        EtubuOsmSpeedLimit.shared.refreshIfNeeded(
                            lat: telemetry.latitude,
                            lng: telemetry.longitude,
                            speedKmh: kmh
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
        .padding(.leading, layout.leadPad)
        .padding(.trailing, layout.trailPad)
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
        let windows = scenes.flatMap(\.windows)
        let overlay = windows.first(where: { $0 is EtubuOverlayWindow })
        let key = windows.first(where: \.isKeyWindow)
        let ranked = [overlay, key].compactMap { $0 } + windows
        let window = ranked.first(where: {
            max($0.safeAreaInsets.top, $0.safeAreaInsets.left, $0.safeAreaInsets.right) > 20
        }) ?? ranked.first
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
                    tpmsGridLandscape
                case .telemetry:
                    VStack(alignment: .leading, spacing: 8) {
                        EtubuChargeDetailChip(telemetry: telemetry)
                        panelValueRow(telemetry.powerKw.map { "\($0) kW" } ?? "—")
                        panelValueRow({
                            if telemetry.isAwaitingClimate {
                                return EtubuClusterL10n.t("awaitingClimate")
                            }
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
                        EtubuPowerRegenBarView(powerKw: telemetry.powerKw, compact: true, theme: theme)
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
                .frame(width: boxW, height: boxH)
                .clipped()
            if criticalAlertsOn {
                roadWarningCard(width: boxW, height: boxH, contentScale: contentScale)
                    .frame(width: boxW, height: boxH)
                    .clipped()
            } else {
                Color.clear.frame(width: boxW, height: boxH)
            }
        }
        .frame(width: boxW, height: dialSize, alignment: .top)
        .clipped()
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
        .frame(width: width, height: height, alignment: .top)
        .clipped()
    }

    /// Twin of avg — identical outer size; content clipped inside frame.
    private func roadWarningCard(width: CGFloat, height: CGFloat, contentScale: CGFloat = 1) -> some View {
        let _ = l10nTick
        return EtubuRoadWarnTwinView(
            warnings: warnings,
            theme: theme,
            compact: height < 100,
            contentScale: contentScale
        )
        .frame(width: width, height: height, alignment: .top)
        .clipped()
    }

    private func speedDialWithThemeGesture(
        compact: Bool,
        diameter: CGFloat,
        chromeDiameter: CGFloat? = nil
    ) -> some View {
        EtubuSpeedDialView(
            kmh: dialKmh,
            gear: dialGear,
            theme: theme,
            compact: compact,
            diameter: diameter,
            chromeDiameter: chromeDiameter,
            powerKw: dialPowerKw,
            powerHistory: telemetry.powerHistory,
            socPercent: telemetry.displaySocPercent
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etubu.dial")
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
        if !premium.isPremium {
            openPremium(hintKey: "premiumLockedTheme")
            return
        }
        let all = ClusterTheme.allCases
        guard let idx = all.firstIndex(of: theme) else { return }
        let n = next ? (idx + 1) % all.count : (idx - 1 + all.count) % all.count
        withAnimation(.easeInOut(duration: 0.2)) {
            theme = all[n]
            ClusterTheme.stored = all[n]
        }
    }

    private var landscapeTopBar: some View {
        HStack(spacing: 12) {
            Text(timeString)
                .font(EtubuClusterFonts.ui(15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.primaryText.opacity(0.9))
            if let out = telemetry.outsideC {
                Text(String(format: "%.0f°C", out))
                    .font(EtubuClusterFonts.ui(15, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            } else if telemetry.isAwaitingClimate {
                Text(EtubuClusterL10n.t("awaitingClimate"))
                    .font(EtubuClusterFonts.ui(11, weight: .medium))
                    .foregroundStyle(theme.mutedText)
            } else {
                Text("--°C")
                    .font(EtubuClusterFonts.ui(15, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
            if let inside = telemetry.insideC {
                Text(String(format: EtubuClusterL10n.t("insideTempFmt"), inside))
                    .font(EtubuClusterFonts.ui(12, weight: .medium))
                    .foregroundStyle(theme.mutedText)
            }
            speedSourceChip
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
                    openRouteOrPaywall()
                } label: {
                    Image(systemName: telemetry.routeActive ? "point.topleft.down.to.point.bottomright.curvepath.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(telemetry.routeActive ? theme.accent : theme.secondaryText)
                        .padding(8)
                        .background(Circle().fill(theme.surface))
                }
                .accessibilityLabel(EtubuClusterL10n.route)
                .accessibilityIdentifier("etubu.route.open")
                .clusterHotspot(.route)
            }

            Button { showRemoteCommands = true } label: {
                Image(systemName: "car.side.front.open")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(telemetry.connectionState == .connected ? theme.accent : theme.secondaryText)
                    .padding(8)
                    .background(Circle().fill(theme.surface))
            }
            .accessibilityLabel(EtubuClusterL10n.t("remoteCmdSection"))
            .accessibilityIdentifier("etubu.remote.open")
            .clusterHotspot(.remote)

            Text(batteryPhoneLabel)
                .font(EtubuClusterFonts.ui(12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.secondaryText)

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.mutedText)
            }
            .accessibilityLabel(EtubuClusterL10n.settings)
            .accessibilityIdentifier("etubu.settings.open")
            .clusterHotspot(.settings)
        }
    }

    private var routeDestinationText: String {
        // App rotası (kullanıcı veya araç-nav uyarlaması) öncelikli.
        if telemetry.routeActive,
           !telemetry.routeTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return telemetry.routeTo
        }
        if !telemetry.navDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return telemetry.navDestination
        }
        if !telemetry.routeTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return telemetry.routeTo
        }
        return ""
    }

    private var hasActiveRouteChrome: Bool {
        warnings.demoActive
            || demo.isRunning
            || telemetry.routeActive
            || !routeDestinationText.isEmpty
            || telemetry.effectiveRemainKm != nil
    }

    private var arrivalSocTint: Color {
        if telemetry.needsChargeStop { return .orange }
        if let e = telemetry.energyAtArrivalPercent, e < evPlan.targetArrivalSoc { return .orange }
        return theme.primaryText.opacity(0.9)
    }

    private var navColumn: some View {
        let _ = l10nTick
        return VStack(alignment: .leading, spacing: 12) {
            if hasActiveRouteChrome {
                navRow(EtubuClusterL10n.destination, value: routeDestinationText)
                navRow(
                    EtubuClusterL10n.arrivalTime,
                    value: telemetry.navEtaMinutes != nil ? telemetry.arrivalTimeLabel : ""
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(EtubuClusterL10n.energyAtArrival)
                        .font(EtubuClusterFonts.ui(10, weight: .medium))
                        .foregroundStyle(theme.mutedText)
                    HStack(spacing: 6) {
                        Text(telemetry.energyAtArrivalPercent.map { "\($0)%" } ?? "—")
                            .font(EtubuClusterFonts.ui(15, weight: .semibold))
                            .foregroundStyle(arrivalSocTint)
                            .accessibilityIdentifier("etubu.ev.arrivalSoc")
                        Text(String(format: EtubuClusterL10n.t("targetSocFmt"), evPlan.targetArrivalSoc))
                            .font(EtubuClusterFonts.ui(10, weight: .medium))
                            .foregroundStyle(theme.mutedText)
                    }
                }
                navRow(EtubuClusterL10n.distance, value: {
                    if telemetry.effectiveRemainKm != nil { return telemetry.navRemainLabel }
                    return ""
                }())
                chargeSuggestionBlock(compact: false)
                if telemetry.routeActive {
                    Button {
                        if telemetry.needsChargeStop || !evPlan.suggestedStops.isEmpty {
                            EtubuRouteBridge.openNearestChargeInMaps()
                        } else {
                            EtubuRouteBridge.openInMaps(destinationName: routeDestinationText)
                        }
                    } label: {
                        Label(
                            telemetry.needsChargeStop || !evPlan.suggestedStops.isEmpty
                                ? EtubuClusterL10n.t("nearestCharge")
                                : EtubuClusterL10n.t("openInMaps"),
                            systemImage: "arrow.up.right.square"
                        )
                        .font(EtubuClusterFonts.ui(12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accent)
                    .accessibilityIdentifier("etubu.route.openMaps")
                }
            }
            EtubuClosuresChip(telemetry: telemetry)
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }

    /// Portrait: kompakt EV / rota şeridi (varış SoC, şarj, Maps).
    private var portraitEvStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(EtubuClusterL10n.energyAtArrival)
                        .font(EtubuClusterFonts.ui(9, weight: .medium))
                        .foregroundStyle(theme.mutedText)
                    HStack(spacing: 4) {
                        Text(telemetry.energyAtArrivalPercent.map { "\($0)%" } ?? (hasActiveRouteChrome ? "—" : "—"))
                            .font(EtubuClusterFonts.ui(14, weight: .bold))
                            .foregroundStyle(arrivalSocTint)
                            .accessibilityIdentifier("etubu.ev.arrivalSoc")
                        Text("→\(evPlan.targetArrivalSoc)%")
                            .font(EtubuClusterFonts.ui(10, weight: .medium))
                            .foregroundStyle(theme.mutedText)
                    }
                }
                if let _ = telemetry.effectiveRemainKm {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(EtubuClusterL10n.distance)
                            .font(EtubuClusterFonts.ui(9, weight: .medium))
                            .foregroundStyle(theme.mutedText)
                        Text(telemetry.navRemainLabel)
                            .font(EtubuClusterFonts.ui(14, weight: .semibold))
                            .foregroundStyle(theme.primaryText.opacity(0.9))
                    }
                }
                Spacer(minLength: 0)
                Button {
                    if telemetry.needsChargeStop || !evPlan.suggestedStops.isEmpty || warnings.demoActive || demo.isRunning {
                        EtubuRouteBridge.openNearestChargeInMaps()
                    } else {
                        EtubuRouteBridge.openInMaps(destinationName: routeDestinationText.isEmpty ? "Etubu rota" : routeDestinationText)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(
                    telemetry.needsChargeStop || !evPlan.suggestedStops.isEmpty
                        ? EtubuClusterL10n.t("nearestCharge")
                        : EtubuClusterL10n.t("openInMaps")
                )
                .accessibilityIdentifier("etubu.route.openMaps")
            }
            chargeSuggestionBlock(compact: true)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .opacity(hasActiveRouteChrome ? 1 : 0.85)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etubu.ev.portraitStrip")
    }

    @ViewBuilder
    private func chargeSuggestionBlock(compact: Bool) -> some View {
        let show = telemetry.needsChargeStop || !evPlan.suggestedStops.isEmpty || warnings.demoActive || demo.isRunning
        if show {
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                Text(telemetry.needsChargeStop || !evPlan.suggestedStops.isEmpty
                     ? EtubuClusterL10n.t("chargeSuggestion")
                     : EtubuClusterL10n.t("chargeStops"))
                    .font(EtubuClusterFonts.ui(compact ? 9 : 10, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.9))
                    .accessibilityIdentifier("etubu.ev.chargeSuggest")
                ForEach(evPlan.suggestedStops.prefix(compact ? 2 : 3), id: \.id) { stop in
                    Button {
                        EtubuRouteBridge.openChargeStop(stop)
                    } label: {
                        Text({
                            let name = stop.label.isEmpty ? EtubuClusterL10n.t("chargeShort") : stop.label
                            let along = stop.alongKm.map { String(format: "%.0f km", $0) } ?? stop.distanceLabel
                            return "· \(name)\(along.isEmpty ? "" : " · \(along)")"
                        }())
                        .font(EtubuClusterFonts.ui(compact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(theme.primaryText.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(EtubuClusterL10n.t("openInMaps"))
                }
                if evPlan.suggestedStops.isEmpty {
                    if let km = telemetry.nextChargeAlongKm {
                        Button {
                            EtubuRouteBridge.openNearestChargeInMaps()
                        } label: {
                            Text(String(format: EtubuClusterL10n.t("afterKmFmt"), km))
                                .font(EtubuClusterFonts.ui(compact ? 11 : 12, weight: .semibold))
                                .foregroundStyle(.orange.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else if warnings.demoActive || demo.isRunning {
                        Button {
                            EtubuRouteBridge.openNearestChargeInMaps()
                        } label: {
                            Text("· Gebze istasyon · 40 km")
                                .font(EtubuClusterFonts.ui(compact ? 11 : 12, weight: .semibold))
                                .foregroundStyle(theme.primaryText.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func navRow(_ title: String, value: String) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(EtubuClusterFonts.ui(10, weight: .medium))
                    .foregroundStyle(theme.mutedText)
                Text(trimmed)
                    .font(EtubuClusterFonts.ui(15, weight: .semibold))
                    .foregroundStyle(theme.primaryText.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
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

    private func portraitLayout(_ layout: EtubuClusterLayoutMetrics) -> some View {
        let short = layout.isCompactHeight
        let portraitDialSize = layout.dialSize
        let portraitBoxW = layout.boxW
        let topChrome = layout.topChrome
        let cardScale = max(0.88, layout.scale * 1.02)
        let hPad = layout.contentHPad
        let hit = layout.iconHit

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
                speedSourceChip
                Spacer(minLength: 0)
                if criticalAlertsOn {
                    Button {
                        EtubuRouteBridge.primeWarningAudio()
                        openRouteOrPaywall()
                    } label: {
                        Image(systemName: telemetry.routeActive ? "map.fill" : "map")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(telemetry.routeActive ? theme.accent : theme.mutedText)
                            .frame(width: hit, height: hit)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(EtubuClusterL10n.route)
                    .accessibilityIdentifier("etubu.route.open")
                    .clusterHotspot(.route)
                }
                Button { showRemoteCommands = true } label: {
                    Image(systemName: "car.side.front.open")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(telemetry.connectionState == .connected ? theme.accent : theme.mutedText)
                        .frame(width: hit, height: hit)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(EtubuClusterL10n.t("remoteCmdSection"))
                .accessibilityIdentifier("etubu.remote.open")
                .clusterHotspot(.remote)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.mutedText)
                        .frame(width: hit, height: hit)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(EtubuClusterL10n.settings)
                .accessibilityIdentifier("etubu.settings.open")
                .clusterHotspot(.settings)
            }
            .padding(.horizontal, hPad)
            .padding(.top, topChrome)

            Spacer(minLength: layout.contentVGap)

            HStack(alignment: .top, spacing: layout.isCompactWidth ? 4 : 6) {
                Spacer(minLength: 0)
                speedDialWithThemeGesture(compact: false, diameter: portraitDialSize)
                // Gidilen yol hız limiti — kadran ile ortalama hız arasında üstte (sadece ikon)
                EtubuRoadSpeedLimitSign(size: layout.signSize)
                    .padding(.top, 4)
                    .onAppear {
                        EtubuOsmSpeedLimit.shared.refreshIfNeeded(
                            lat: telemetry.latitude,
                            lng: telemetry.longitude,
                            speedKmh: telemetry.kmh
                        )
                    }
                twinCardsColumn(
                    dialSize: portraitDialSize,
                    boxW: portraitBoxW,
                    contentScale: cardScale
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, hPad)
            .onChange(of: telemetry.latitude) { _, _ in
                EtubuOsmSpeedLimit.shared.refreshIfNeeded(
                    lat: telemetry.latitude,
                    lng: telemetry.longitude,
                    speedKmh: telemetry.kmh
                )
            }
            .onChange(of: telemetry.kmh) { _, kmh in
                EtubuOsmSpeedLimit.shared.refreshIfNeeded(
                    lat: telemetry.latitude,
                    lng: telemetry.longitude,
                    speedKmh: kmh
                )
            }

            // Portrait: regen sabit (kadranın hemen altında), özet/şarj şeffaf ve biraz aşağı.
            EtubuPowerRegenBarView(powerKw: telemetry.powerKw, compact: short, theme: theme)
                .padding(.horizontal, short ? 18 : 28)
                .padding(.top, short ? 6 : 10)
                .layoutPriority(4)

            Spacer(minLength: short ? 10 : 16)

            portraitEvStrip
                .padding(.horizontal, short ? 16 : 22)
                .fixedSize(horizontal: false, vertical: true)

            EtubuChargeDetailChip(telemetry: telemetry)
                .padding(.horizontal, short ? 16 : 22)
                .padding(.top, 6)
            EtubuMediaNowPlayingView(telemetry: telemetry)
                .padding(.horizontal, short ? 18 : 28)
                .padding(.top, 4)

            Spacer(minLength: short ? 6 : 12)

            HStack(alignment: .center, spacing: 12) {
                soundControl(compact: short)
                Spacer()
            }
            .padding(.horizontal, short ? 16 : 22)
            .padding(.bottom, 8)

            HStack(alignment: .bottom, spacing: 10) {
                // Dik: lastik + üstten araç çizimi en solda
                tpmsGridPortrait
                    .frame(maxWidth: short ? 132 : 156, alignment: .leading)
                    .layoutPriority(2)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(timeString)
                        .font(EtubuClusterFonts.gauge(short ? 26 : 36))
                        .monospacedDigit()
                        .foregroundStyle(theme.primaryText)
                        .shadow(color: theme.glow, radius: 8)
                    HStack(spacing: 6) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        Text(telemetry.displayRangeKm.map { "\($0) km" } ?? "— km")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(theme.accent)
                        Text(telemetry.displaySocPercent.map { "\($0)%" } ?? "—")
                        if let age = telemetry.chargeAgeShortLabel {
                            Text(age)
                                .font(EtubuClusterFonts.ui(10, weight: .medium))
                                .foregroundStyle(theme.mutedText)
                        }
                        Capsule()
                            .fill(theme.surface)
                            .frame(width: 56, height: 4)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(theme.accent)
                                    .frame(width: 56 * CGFloat(telemetry.displaySocPercent ?? 0) / 100.0, height: 4)
                            }
                    }
                    .font(EtubuClusterFonts.ui(15, weight: .semibold))
                    .foregroundStyle(theme.primaryText.opacity(0.9))
                }
            }
            .padding(.leading, short ? 10 : 14)
            .padding(.trailing, short ? 16 : 22)
            .padding(.bottom, max(10, layout.insets.bottom + 8))
        }
        .safeAreaPadding(.top, layout.cutoutStyle == .none ? 0 : 2)
    }

    private var tpmsGridPortrait: some View {
        EtubuTPMSGridView(telemetry: telemetry, noseUp: true, compact: true)
    }

    private var tpmsGridLandscape: some View {
        EtubuTPMSGridView(telemetry: telemetry, noseUp: true, compact: false)
    }

    // MARK: - Shared controls

    private func soundControl(compact: Bool) -> some View {
        EtubuSoundIconControl(
            compact: compact,
            theme: theme,
            soundOn: $soundOn,
            selectedVoice: $selectedVoice,
            toggleSound: toggleSound,
            cycleSoundProfile: cycleSoundProfile
        )
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
                        Text(EtubuClusterL10n.t("vehicleVin"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Button(EtubuClusterL10n.close) {
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
                            Text(tesla.pairStep == .sendingRequest || tesla.pairStep == .connectingAfterCard
                                 ? "…" : EtubuClusterL10n.t("pairAction"))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(theme.accent, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(
                            tesla.pairStep == .sendingRequest
                                || tesla.pairStep == .connectingAfterCard
                        )
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
                                Text(EtubuClusterL10n.t("connect"))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            }
                            Button {
                                Task { await tesla.repair() }
                            } label: {
                                Text(EtubuClusterL10n.t("rePair"))
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
                        Text(EtubuClusterL10n.t("pairNfcHint"))
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
                        Text(EtubuClusterL10n.t("pairGuideTitle"))
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
                        title: EtubuClusterL10n.t("pairStepRequest"),
                        body: EtubuClusterL10n.t("pairStepRequestBody"),
                        active: sending,
                        done: step1Done
                    )
                    pairGuideStep(
                        n: 2,
                        title: EtubuClusterL10n.t("pairStepKeycard"),
                        body: EtubuClusterL10n.t("pairStepKeycardBody"),
                        active: waiting,
                        done: step2Done
                    )
                    pairGuideStep(
                        n: 3,
                        title: EtubuClusterL10n.t("pairStepConnected"),
                        body: EtubuClusterL10n.t("pairStepConnectedBody"),
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
                        Text(tesla.pairStep == .connectingAfterCard
                             ? EtubuClusterL10n.t("connecting")
                             : EtubuClusterL10n.t("cardTappedConnect"))
                            .font(EtubuClusterFonts.ui(15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(tesla.pairStep == .connectingAfterCard)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await tesla.retryPair() }
                    } label: {
                        Text(EtubuClusterL10n.t("retry"))
                            .font(EtubuClusterFonts.ui(13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .disabled(
                        tesla.pairStep == .sendingRequest
                            || tesla.pairStep == .connectingAfterCard
                    )
                    Button {
                        Task { await tesla.disconnect() }
                    } label: {
                        Text(EtubuClusterL10n.t("cancel"))
                            .font(EtubuClusterFonts.ui(13, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.95))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                    Spacer()
                }

                Text(EtubuClusterL10n.t("dataStaysOnDevice"))
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
        case .sendingRequest: return EtubuClusterL10n.t("pairGuideSending")
        case .waitingForCard: return EtubuClusterL10n.t("pairGuideWaitingCard")
        case .connectingAfterCard: return EtubuClusterL10n.t("pairGuideConnecting")
        case .failed: return EtubuClusterL10n.t("pairGuideFailed")
        case .none:
            if telemetry.connectionState == .connected { return EtubuClusterL10n.t("pairGuideConnected") }
            return EtubuClusterL10n.t("pairGuideFlow")
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
                EtubuPremiumSettingsSection(showPaywall: Binding(
                    get: { showPremiumPaywall },
                    set: { want in
                        if want {
                            showSettings = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                openPremium()
                            }
                        } else {
                            showPremiumPaywall = false
                        }
                    }
                ), accent: theme.accent, onRequestRedeemCode: {
                    showSettings = false
                    showPremiumPaywall = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        premium.presentOfferCodeRedeem()
                    }
                })

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
                        Label(EtubuClusterL10n.t("aboutApp"), systemImage: "info.circle")
                            .font(.body.weight(.semibold))
                    }
                }

                Section(EtubuClusterL10n.language) {
                    ForEach(EtubuAppLanguage.allCases) { lang in
                        Button {
                            appLanguage = lang
                            EtubuAppLanguage.setManual(lang)
                        } label: {
                            HStack {
                                Text(lang.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if appLanguage == lang {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("etubu.language.\(lang.rawValue)")
                        .accessibilityLabel(lang.title)
                        .accessibilityAddTraits(appLanguage == lang ? [.isButton, .isSelected] : .isButton)
                    }
                }

                Section(EtubuClusterL10n.t("evRoutePlan")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(EtubuClusterL10n.t("targetArrivalSoc"))
                            Spacer()
                            Text("\(evPlan.targetArrivalSoc)%")
                                .font(.body.monospacedDigit().weight(.semibold))
                                .foregroundStyle(theme.accent)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(evPlan.targetArrivalSoc) },
                                set: { evPlan.targetArrivalSoc = Int($0.rounded()) }
                            ),
                            in: 5...50,
                            step: 5
                        )
                        .tint(theme.accent)
                        .onChange(of: evPlan.targetArrivalSoc) { _, _ in
                            evPlan.refreshFromLiveState()
                        }
                        Text(EtubuClusterL10n.t("evPlanHint"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if telemetry.needsChargeStop {
                            Text(String(format: EtubuClusterL10n.t("chargeSuggestFmt"), max(telemetry.suggestedChargeCount, 1)))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(EtubuClusterL10n.t("tripAnalyticsSection")) {
                    EtubuTripAnalyticsView(store: trips, accent: theme.accent)
                    if let url = trips.exportCSV() {
                        ShareLink(item: url) {
                            Label(EtubuClusterL10n.t("tripExportCSV"), systemImage: "square.and.arrow.up")
                        }
                    }
                    Button(EtubuClusterL10n.t("tripClearHistory"), role: .destructive) {
                        trips.clearAll()
                    }
                }

                Section(EtubuClusterL10n.t("remoteCmdSection")) {
                    EtubuRemoteCommandCards(tesla: tesla)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(EtubuClusterL10n.t("cmdChargeLimit"))
                            Spacer()
                            Text("\(Int(remoteChargeLimit))%")
                                .monospacedDigit()
                        }
                        Slider(value: $remoteChargeLimit, in: 50...100, step: 5)
                        Button(EtubuClusterL10n.t("cmdApplyLimit")) {
                            Task { await tesla.setChargeLimit(Int(remoteChargeLimit)) }
                        }
                    }
                }

                Section(EtubuClusterL10n.t("demoSection")) {
                    Button {
                        if demo.isRunning {
                            demo.stop()
                        } else {
                            demo.start()
                            selectedVoice = EtubuClusterAudioBridge.defaultDriveVoice
                            soundOn = true
                            DispatchQueue.main.async {
                                showSettings = false
                            }
                        }
                    } label: {
                        Label(
                            demo.isRunning ? EtubuClusterL10n.t("demoStopBtn") : EtubuClusterL10n.t("demoStart"),
                            systemImage: demo.isRunning ? "stop.fill" : "play.fill"
                        )
                    }
                    .accessibilityIdentifier("etubu.demo.toggle")
                    Toggle(EtubuClusterL10n.t("demoMirror"), isOn: $demo.mirrorEnabled)
                    Text(EtubuClusterL10n.t("demoHint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section(EtubuClusterL10n.t("vehicleNotifySection")) {
                    Toggle(EtubuClusterL10n.t("vehicleNotifyToggle"), isOn: Binding(
                        get: { EtubuVehicleLaunchNotifier.isEnabled },
                        set: { newValue in
                            EtubuVehicleLaunchNotifier.isEnabled = newValue
                            if newValue {
                                EtubuVehicleLaunchNotifier.shared.requestAuthorizationIfNeeded()
                            }
                        }
                    ))
                    Text(EtubuClusterL10n.t("vehicleNotifyHint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section(EtubuClusterL10n.t("themeStoreSection")) {
                    EtubuThemeStoreView(theme: $theme, wallpaper: $wallpaper) {
                        showSettings = false
                        openPremium(hintKey: "premiumLockedTheme")
                    }
                }
                Section(EtubuClusterL10n.t("cameraEffect")) {
                    Toggle(EtubuClusterL10n.t("notchAuraToggle"), isOn: $notchAuraEnabled)
                    Text("\(theme.title) · \(EtubuCutoutFX.forTheme(theme).title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    if premium.isPremium {
                        Toggle(EtubuClusterL10n.t("mapEnabled"), isOn: $mapEnabled)
                    } else {
                        Button {
                            showSettings = false
                            openPremium(hintKey: "premiumLockedMap")
                        } label: {
                            Text(EtubuClusterL10n.t("mapEnabled"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Text(EtubuClusterL10n.t("premiumLockedMap"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                } header: {
                    HStack(alignment: .center, spacing: 8) {
                        Text(EtubuClusterL10n.t("mapFeatures"))
                        Spacer(minLength: 0)
                        if !premium.isPremium {
                            // Üst köşe logo — satır ikonlarını kaplamaz
                            EtubuPremiumBadge(compact: true)
                        }
                    }
                }
                Section {
                    Toggle(EtubuClusterL10n.t("soundOn"), isOn: Binding(
                        get: { soundOn },
                        set: { on in
                            soundOn = on
                            if on {
                                let v = selectedVoice == "silent-mode"
                                    ? theme.driveVoiceKey
                                    : selectedVoice
                                selectedVoice = v
                                EtubuClusterAudioBridge.setVoice(v)
                                EtubuClusterAudioBridge.setSoundEnabled(true, voice: v)
                                EtubuClusterAudioBridge.startDrive(
                                    kmh: max(telemetry.kmh, 0),
                                    gear: telemetry.gear,
                                    source: telemetry.source.rawValue,
                                    powerKw: telemetry.powerKw
                                )
                            } else {
                                selectedVoice = "silent-mode"
                                EtubuClusterAudioBridge.setSoundEnabled(false, voice: "silent-mode")
                            }
                        }
                    ))
                    Text(EtubuClusterL10n.t("voicePackShared"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(EtubuClusterL10n.t("voiceGroupTheme"), selection: $selectedVoice) {
                        ForEach(EtubuSoundVoice.groups, id: \.group) { group in
                            ForEach(group.voices) { voice in
                                Text(voice.localizedLabel)
                                    .tag(voice.key)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!soundOn && selectedVoice == "silent-mode")
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
                } header: {
                    Text(EtubuClusterL10n.t("soundSelect"))
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
                if criticalAlertsOn {
                    EtubuRadarSettingsView()
                }
                Section(EtubuClusterL10n.connection) {
                    LabeledContent(EtubuClusterL10n.quality, value: telemetry.connectionQualityLabel)
                    LabeledContent(EtubuClusterL10n.source, value: telemetry.speedSourceLabel)
                }
                Section(EtubuClusterL10n.vehicle) {
                    Button(EtubuClusterL10n.pairVin) { showSettings = false; showVINEditor = true }
                    if criticalAlertsOn {
                        Button {
                            showSettings = false
                            EtubuRouteBridge.primeWarningAudio()
                            openRouteOrPaywall()
                        } label: {
                            Text(EtubuClusterL10n.pickRoute)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                        .accessibilityIdentifier("etubu.settings.done")
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
        let soc = telemetry.displaySocPercent.map { "\($0)%" } ?? "--%"
        let range = telemetry.displayRangeKm.map { "\($0) km" } ?? "--km"
        if let age = telemetry.chargeAgeShortLabel {
            return "\(soc) / \(range) · \(age)"
        }
        return "\(soc) / \(range)"
    }

    private var speedSourceChip: some View {
        Text(telemetry.speedSourceLabel)
            .font(EtubuClusterFonts.ui(10, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(theme.canvas)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(sourceChipFill)
            )
            .accessibilityLabel(telemetry.speedSourceLabel)
            .accessibilityIdentifier("etubu.source.chip")
    }

    private var sourceChipFill: Color {
        if EtubuDemoDrive.isActive || telemetry.source == .demo {
            return Color.orange.opacity(0.95)
        }
        switch telemetry.source {
        case .tesla: return theme.accent
        case .obd: return Color.cyan.opacity(0.9)
        case .gps: return Color.white.opacity(0.35)
        case .demo: return Color.orange.opacity(0.95)
        case .none: return Color.white.opacity(0.2)
        }
    }

    private var batteryPhoneLabel: String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level < 0 { return "" }
        return "\(Int(level * 100))"
    }

    private func toggleSound(_ on: Bool) {
        if on {
            let voice = selectedVoice == "silent-mode" ? EtubuClusterAudioBridge.defaultDriveVoice : selectedVoice
            if selectedVoice == "silent-mode" {
                selectedVoice = voice
            }
            EtubuClusterAudioBridge.setSoundEnabled(true, voice: voice)
            EtubuClusterAudioBridge.pushDrive(
                kmh: telemetry.kmh,
                powerKw: telemetry.powerKw,
                source: telemetry.source.rawValue
            )
            UserDefaults.standard.set(true, forKey: "etubu.evSound.tipSeen")
        } else {
            EtubuClusterAudioBridge.setSoundEnabled(false)
        }
    }

    /// After demo stop — keep mute/on preference (do not force silent-mode).
    private func syncSoundUIFromPreference() {
        if EtubuClusterAudioBridge.isSoundWanted {
            let voice = EtubuClusterAudioBridge.storedVoice
            selectedVoice = (voice.isEmpty || voice == "silent-mode")
                ? EtubuClusterAudioBridge.defaultDriveVoice : voice
            soundOn = true
        } else {
            soundOn = false
            selectedVoice = "silent-mode"
        }
    }

    private func startLiveActivityShell() {
        guard #available(iOS 16.2, *) else { return }
        Task { await EtubuLiveActivityController.publishCurrent() }
    }
}

/// Ana ekran EV ses ikonu — tek dokunuşla aç/kapa. Uyarı seslerine dokunmaz (ayarlar).
private struct EtubuSoundIconControl: View {
    var compact: Bool
    var theme: ClusterTheme
    @Binding var soundOn: Bool
    @Binding var selectedVoice: String
    var toggleSound: (Bool) -> Void
    var cycleSoundProfile: () -> Void

    private var profileLabel: String {
        if let voice = EtubuSoundVoice.all.first(where: { $0.key == selectedVoice }) {
            return voice.localizedLabel
        }
        return EtubuClusterL10n.t("voiceSilentMode")
    }

    var body: some View {
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
            .accessibilityLabel(soundOn ? EtubuClusterL10n.t("soundA11yOn") : EtubuClusterL10n.t("soundA11yOff"))
            .accessibilityIdentifier(soundOn ? "etubu.sound.on" : "etubu.sound.off")

            Button {
                cycleSoundProfile()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(soundOn ? profileLabel : EtubuClusterL10n.t("soundMuted"))
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
            .accessibilityIdentifier("etubu.sound.profile")
            .accessibilityLabel(EtubuClusterL10n.t("soundProfile"))
            .accessibilityHint(EtubuClusterL10n.t("tapToChange"))
        }
    }
}
