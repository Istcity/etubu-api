import SwiftUI
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
    @ObservedObject private var mapLocation = EtubuMapLocationHelper.shared

    @State private var theme: ClusterTheme = ClusterTheme.stored
    @State private var wallpaper: EtubuWallpaperStyle = EtubuWallpaperStyle.stored
    @State private var vinDraft: String = ""
    @State private var showVINEditor = false
    @State private var showSettings = false
    @State private var showExitConfirm = false
    @State private var showPremiumPaywall = false
    @State private var premiumPaywallHint: String? = nil
    @AppStorage("etubu.cluster.mixMode") private var mixMode = "blend"
    @AppStorage("etubu.cluster.alertOverMusic") private var alertOverMusic = true
    @State private var soundOn = false
    @State private var selectedVoice: String = EtubuClusterAudioBridge.storedVoice
    @State private var showEvSoundTip = false
    @State private var showDiscoverTip = false
    @State private var showObdMenu = false
    @State private var commandToast = ""
    @State private var commandToastToken = UUID()
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
    @AppStorage("etubu.cluster.rightDialMode") private var storedRightDialModeRaw = RightDialMode.battery.rawValue
    @AppStorage("etubu.cluster.layoutStyle") private var storedLayoutStyleRaw = EtubuClusterLayoutStyle.dualDial.rawValue
    private var layoutStyle: EtubuClusterLayoutStyle {
        EtubuClusterLayoutStyle(rawValue: storedLayoutStyleRaw) ?? .dualDial
    }
    @State private var l10nTick = 0
    @State private var keyboardInset: CGFloat = 0
    @State private var hotspotFrames: [EtubuClusterHotspotID: CGRect] = [:]
    @FocusState private var vinFocused: Bool
    @AppStorage("etubu.cluster.notchAuraEnabled") private var notchAuraEnabled = true
    @AppStorage("etubu.cluster.mapEnabled") private var mapEnabled = true
    @AppStorage(EtubuMapLocationHelper.locationEnabledKey) private var locationEnabled = true
    @AppStorage("etubu.cluster.alertVolume") private var alertVolume: Double = 0.85
    @AppStorage("etubu.cluster.stealthMode") private var stealthMode = true
    @AppStorage("etubu.cluster.stealthAnalog") private var stealthAnalog = false
    /// Güç tasarrufu: yalnız hız + regen; diğer paneller ve extras poll durur.
    @AppStorage("etubu.cluster.powerSave") private var powerSaveMode = false
    /// Üst chrome butonları açık mı; kapalıysa tek genişlet butonu (+ uzaktan kumanda).
    @AppStorage("etubu.cluster.chromeExpanded") private var chromeExpanded = true
    @AppStorage(EtubuRemotePinStore.enabledKey) private var remotePinUnderWarn = false
    @State private var stealthWakeUntil = Date.distantPast
    @State private var stealthTick = Date()
    @AppStorage("etubu.demo.running") private var demoRunningUD = false
    @AppStorage("etubu.demo.kmh") private var demoKmhUD = 0
    /// Cached outside AttributeGraph — reading `UIWindow.safeAreaInsets` inside
    /// `GeometryReader` re-enters layout (status-bar / safe-area query) and can
    /// stack-overflow on iOS 26/27 (see docs/crash-Etubu-2026-08-11.md).
    @State private var cachedWinInsets = EdgeInsets()
    @AppStorage("etubu.demo.gear") private var demoGearUD = "P"
    @AppStorage("etubu.demo.power") private var demoPowerUD = 0

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let stealthClock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var criticalAlertsOn: Bool { appLanguage.criticalAlertsEnabled }
    private var mapBackdropEnabled: Bool { premium.isPremium && mapEnabled }
    private var shouldShowPairGuide: Bool { tesla.pairStep != .none }

    /// Tesla D/R and moving — keep the full cluster, not the OLED cover.
    private var isTeslaDriving: Bool {
        let g = telemetry.gear.uppercased()
        let teslaOn = telemetry.connectionState == .connected
            || telemetry.connectionState == .reconnecting
        return teslaOn && (g.hasPrefix("D") || g.hasPrefix("R")) && telemetry.kmh >= 3
    }

    /// OLED speed-only cover. Maestro / legal / sheets stay on the full dashboard.
    private var stealthCovering: Bool {
        let _ = stealthTick
        guard stealthMode, !EtubuMaestroLaunch.isActive else { return false }
        if showLegal || showSim || showSettings || showExitConfirm || showVINEditor
            || showRoutePicker || showRemoteCommands || showPremiumPaywall || shouldShowPairGuide
            || showObdMenu {
            return false
        }
        if isTeslaDriving { return false }
        let parked = (telemetry.connectionState == .connected || telemetry.connectionState == .reconnecting)
            && telemetry.gear.uppercased().hasPrefix("P")
            && telemetry.kmh < 3
        let idle: TimeInterval = parked ? 2.5 : 10
        return Date().timeIntervalSince(stealthWakeUntil) >= idle
    }

    private func noteClusterInteraction() {
        stealthWakeUntil = Date()
    }

    /// Wake the cluster in Drive; start EV sound only if the user already enabled it.
    private func applyDriveWakePolicy() {
        if isTeslaDriving, EtubuClusterAudioBridge.isSoundWanted {
            EtubuClusterAudioBridge.ensureLiveDriveSound(
                kmh: telemetry.kmh,
                powerKw: telemetry.powerKw,
                gear: telemetry.gear
            )
        }
    }

    private func openPremium(hintKey: String? = nil) {
        guard !EtubuPremiumManager.isPaidAppModel else { return }
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
        // P/N yalnız gerçekten dururken 0; hareketliyken dialGear ile aynı (D).
        if (g.hasPrefix("P") || g.hasPrefix("N")), telemetry.kmh < 3 { return 0 }
        // Tesla araç hızı birincil — creep’i gizleme (<5 floor kaldırıldı).
        return max(0, telemetry.kmh)
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
        let g = telemetry.gear.uppercased()
        if (g.isEmpty || g.hasPrefix("P") || g.hasPrefix("N")), telemetry.kmh >= 3 { return "D" }
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

    var body: some View {
        GeometryReader { geo in
            let _ = l10nTick
            let landscape = geo.size.width > geo.size.height
            // Hosting overlay often zeros SwiftUI safeAreaInsets — use cached window insets
            // (never call UIWindow.safeAreaInsets synchronously here; see cachedWinInsets).
            let win = cachedWinInsets
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
                    // Güç tasarrufunda harita yok — yalnız tema zemini + kadran.
                    if powerSaveMode {
                        ClusterThemeBackdrop(theme: theme, landscape: landscape, wallpaper: wallpaper)
                    } else {
                        backgroundLayer(
                            landscape: landscape,
                            mapWashHeight: layout.mapWashHeight,
                            mapLegalLead: layout.mapLegalLead
                        )
                    }
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
                .clipped()
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

                // SoC < %10 → çevrede ince kırmızı pulse
                if let soc = telemetry.displaySocPercent, soc < 10 {
                    lowSocPulseOverlay
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

                if !commandToast.isEmpty, !stealthCovering {
                    Text(commandToast)
                        .font(EtubuClusterFonts.ui(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.82))
                        )
                        .padding(.bottom, 88)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .zIndex(36)
                }

                if stealthCovering && !showLegal && !showSim {
                    EtubuStealthSpeedView(
                        kmh: dialKmh,
                        kmhFine: telemetry.kmhFine,
                        analog: stealthAnalog
                    ) {
                        withAnimation(.easeOut(duration: 0.28)) {
                            noteClusterInteraction()
                        }
                    }
                    .transition(.opacity)
                    .zIndex(40)
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
                        withAnimation(.easeInOut(duration: 0.45)) {
                            simDone = true
                            simDoneStored = true
                        }
                        startCoreIfNeeded()
                    }
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
                    .zIndex(45)
                }
            }
            .coordinateSpace(name: "etubuCluster")
            .animation(.easeInOut(duration: 0.45), value: showSim)
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
                // Defer past the current AttributeGraph transaction.
                DispatchQueue.main.async { refreshCachedWinInsets() }
            }
            .onChange(of: layout.fontScale) { _, _ in
                layout.applyFontScale()
            }
            .onChange(of: landscape) { _, _ in
                layout.applyFontScale()
                DispatchQueue.main.async { refreshCachedWinInsets() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .etubuClusterGeometryDidChange)) { _ in
                DispatchQueue.main.async { refreshCachedWinInsets() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                DispatchQueue.main.async { refreshCachedWinInsets() }
            }
            .onReceive(stealthClock) { stealthTick = $0 }
            .simultaneousGesture(TapGesture().onEnded { noteClusterInteraction() })
            .sheet(isPresented: $showSettings) {
                SettingsHost(
                    snap: SettingsHost.Snap(
                        lang: appLanguage,
                        l10nTick: l10nTick,
                        theme: theme,
                        wallpaper: wallpaper,
                        demoRunning: demo.isRunning,
                        conn: telemetry.connectionQualityLabel,
                        src: telemetry.speedSourceLabel,
                        needsCharge: telemetry.needsChargeStop,
                        chargeN: telemetry.suggestedChargeCount,
                        soundOn: soundOn,
                        voice: selectedVoice,
                        mix: mixMode,
                        stealth: stealthMode,
                        stealthA: stealthAnalog,
                        map: mapEnabled,
                        loc: locationEnabled,
                        premium: premium.isPremium,
                        soc: evPlan.targetArrivalSoc,
                        remoteLim: remoteChargeLimit,
                        alertVol: alertVolume,
                        alertOver: alertOverMusic,
                        notch: notchAuraEnabled,
                        obd: showObdMenu
                    ),
                    theme: $theme,
                    wallpaper: $wallpaper,
                    appLanguage: $appLanguage,
                    showSettings: $showSettings,
                    showExitConfirm: $showExitConfirm,
                    showVINEditor: $showVINEditor,
                    showObdMenu: $showObdMenu,
                    showPremiumPaywall: $showPremiumPaywall,
                    showRoutePicker: $showRoutePicker,
                    premiumPaywallHint: $premiumPaywallHint,
                    soundOn: $soundOn,
                    selectedVoice: $selectedVoice,
                    mixMode: $mixMode,
                    alertOverMusic: $alertOverMusic,
                    alertVolume: $alertVolume,
                    stealthMode: $stealthMode,
                    stealthAnalog: $stealthAnalog,
                    mapEnabled: $mapEnabled,
                    locationEnabled: $locationEnabled,
                    notchAuraEnabled: $notchAuraEnabled,
                    remoteChargeLimit: $remoteChargeLimit
                )
                .equatable()
                    .tint(theme.accent)
                    .environment(\.clusterTheme, theme)
                    .id(appLanguage)
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPremiumPaywall) {
                EtubuPremiumPaywallView(accent: theme.accent, highlight: premiumPaywallHint)
                    .environment(\.clusterTheme, theme)
                    .tint(theme.accent)
                    .preferredColorScheme(.dark)
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showRoutePicker) {
                EtubuRoutePickerView()
                    .environment(\.clusterTheme, theme)
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showRemoteCommands) {
                NavigationStack {
                    List {
                        Section {
                            EtubuRemoteCommandCards(tesla: tesla)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(EtubuClusterL10n.t("cmdChargeLimit"))
                                    Spacer()
                                    Text("\(Int(remoteChargeLimit))%")
                                        .font(EtubuClusterFonts.gauge(16))
                                }
                                Slider(value: $remoteChargeLimit, in: 50...100, step: 5)
                                Button(EtubuClusterL10n.t("cmdApplyLimit")) {
                                    Task { await tesla.setChargeLimit(Int(remoteChargeLimit)) }
                                }
                            }
                        } header: {
                            EtubuSheetSectionTitle(title: EtubuClusterL10n.t("remoteCmdSection"), theme: theme, motion: .remote)
                        }
                        .etubuSheetSection(theme)
                    }
                    .etubuSheetList(theme)
                    .environment(\.locale, appLanguage.locale)
                    .navigationTitle(EtubuClusterL10n.t("remoteCmdSection"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(EtubuClusterL10n.done) { showRemoteCommands = false }
                                .foregroundStyle(theme.accent)
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
            .alert(EtubuClusterL10n.t("exitConfirmTitle"), isPresented: $showExitConfirm) {
                Button(EtubuClusterL10n.t("cancel"), role: .cancel) {}
                Button(EtubuClusterL10n.t("exitConfirmQuit"), role: .destructive) {
                    EtubuAppExit.quitFully()
                }
            } message: {
                Text(EtubuClusterL10n.t("exitConfirmBody"))
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
            if !showSim && !showLegal {
                startCoreIfNeeded()
            }
            EtubuTeslaBleSession.shared.setPowerSave(powerSaveMode)
        }
        .onChange(of: premium.isPremium) { _, on in
            EtubuClusterAudioBridge.setPremium(on)
            if !on {
                premium.enforceFreeThemeIfNeeded()
                theme = EtubuPremiumManager.freeTheme
                wallpaper = .atmospheric
            }
        }
        .onChange(of: telemetry.gear) { _, gear in
            let g = gear.uppercased()
            if g.hasPrefix("D") || g.hasPrefix("R") { noteClusterInteraction() }
            applyDriveWakePolicy()
        }
        .onChange(of: telemetry.kmh) { _, _ in applyDriveWakePolicy() }
        .onChange(of: telemetry.connectionState) { _, state in
            if state == .connected { noteClusterInteraction() }
            applyDriveWakePolicy()
            if !showLegal && !showSim {
                EtubuMapLocationHelper.shared.syncWithVehicleSession()
            }
        }
        .onChange(of: tesla.lastCommandMessage) { _, msg in
            let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            commandToast = trimmed
            let token = UUID()
            commandToastToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                guard commandToastToken == token else { return }
                withAnimation(.easeOut(duration: 0.2)) { commandToast = "" }
            }
        }
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
            withAnimation(.easeInOut(duration: 0.45)) {
                simDone = true
                simDoneStored = true
            }
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
                keyboardInset = min(overlap, Self.keyboardCap(overlapHint: overlap))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                keyboardInset = 0
            }
        }
    }

    private static func keyboardCap(overlapHint: CGFloat) -> CGFloat {
        _ = overlapHint
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let bounds = (scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first)?
            .coordinateSpace.bounds
            ?? UIScreen.main.bounds
        let landscape = bounds.width > bounds.height
        return bounds.height * (landscape ? 0.72 : 0.55)
    }

    private func startCoreIfNeeded() {
        // Process-lifetime once — double legal accept / sim finish must not re-arm Cap.
        guard !Self.didStartCore else { return }
        Self.didStartCore = true
        EtubuVehicleTelemetry.shared.scrubDemoChargeResidueIfNeeded()
        EtubuClusterPresenter.shared.armCapGeolocation()
        EtubuCapBridgeViewController.armWebContent()
        // Konum + Bluetooth izinlerini hemen iste; Tesla bağlanmayı BT diyaloguna bağlama.
        EtubuMapLocationHelper.shared.syncWithVehicleSession()
        Task { @MainActor in
            _ = await EtubuBluetoothGate.shared.waitUntilReady(timeoutSeconds: 14)
        }
        tesla.bootstrapIfPossible(reason: .autoLaunch)
        warnings.startPolling()
        EtubuTrCorridorStore.refreshIfNeeded()
        EtubuRouteBridge.primeWarningAudio()
        EtubuClusterAudioBridge.armPowerRegenHook()
        UIApplication.shared.isIdleTimerDisabled = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                EtubuTeslaBleSession.shared.resumeAutoConnectIfNeeded()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIScene.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                EtubuTeslaBleSession.shared.resumeAutoConnectIfNeeded()
            }
        }
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
        // Maestro: pin bar under road warning
        let launchArgs = ProcessInfo.processInfo.arguments
        if launchArgs.contains("etubuForceRemotePin") || launchArgs.contains("-etubuForceRemotePin") {
            UserDefaults.standard.set(true, forKey: EtubuRemotePinStore.enabledKey)
            remotePinUnderWarn = true
        }
    }

    private static var didStartCore = false

    private static func applyLayoutBoost(landscape: Bool) {
        // Legacy path — prefer EtubuClusterLayoutMetrics.applyFontScale().
        let next: CGFloat = landscape ? 1.12 : 0.95
        EtubuClusterFonts.setContentScale(next)
    }

    /// SoC < %10 — ekran kenarında ince kırmızı pulse
    private var lowSocPulseOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.40 + 0.45 * abs(sin(t * 2.4))
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .strokeBorder(
                    Color.red.opacity(pulse),
                    lineWidth: 1.5 + CGFloat(pulse) * 1.2
                )
                .ignoresSafeArea()
                .opacity(0.95)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private func backgroundLayer(landscape: Bool, mapWashHeight: CGFloat, mapLegalLead: CGFloat) -> some View {
        ZStack {
            if theme == .stealthOled {
                // Saf Siyah Çift Kadran: Tamamen zifiri siyah OLED zemin
                Color.black
                    .ignoresSafeArea()
            } else if theme == .mapFocus || theme == .map3D {
                // Haritanın tüm ekranı kapladığı tam zemin görünüm (2D / 3D Kokpit)
                mapBackdrop(legalLead: 0)
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(theme == .map3D ? 0.12 : 0.18).allowsHitTesting(false))
            } else {
                ClusterThemeBackdrop(theme: theme, landscape: landscape, wallpaper: wallpaper)

                if landscape {
                    HStack(spacing: 0) {
                        Color.clear.frame(maxWidth: .infinity)
                        if mapBackdropEnabled {
                            mapBackdrop()
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
                            mapBackdrop(legalLead: mapLegalLead)
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
    }

    private func mapBackdrop(legalLead: CGFloat = 0) -> some View {
        EtubuClusterMapBackdrop(
            theme: theme,
            legalLead: legalLead,
            criticalAlertsOn: criticalAlertsOn,
            locationEnabled: locationEnabled
        )
        .equatable()
    }

    // MARK: - Landscape

    private func landscapeLayout(_ layout: EtubuClusterLayoutMetrics) -> some View {
        let dialMax = layout.dialSize
        let dialBase = layout.dialChrome
        let boxW = layout.boxW
        let sideW = layout.sideW
        let layoutScale = layout.scale

        return VStack(spacing: 0) {
            landscapeTopBar(layout)
                .padding(.horizontal, 2)
                .layoutPriority(3)

            if powerSaveMode {
                VStack(spacing: 10) {
                    speedDialWithThemeGesture(
                        compact: true,
                        diameter: dialMax,
                        chromeDiameter: dialBase
                    )
                    EtubuPowerRegenBarView(powerKw: telemetry.powerKw, compact: true, theme: theme)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if layoutStyle == .dualDial {
                // 1. TAM SİMETRİK ÇİFT KADRAN (Sol Hız + Ortada Bütünleşik Bilgi Modülü + Sağ Çok Fonksiyonlu Kadran)
                HStack(alignment: .center, spacing: layout.isCompactWidth ? 6 : 10) {
                    // 1. SOL: Hız Kadranı
                    speedDialWithThemeGesture(
                        compact: true,
                        diameter: dialMax,
                        chromeDiameter: dialBase
                    )
                    .frame(width: dialMax, height: dialMax)
                    .layoutPriority(2)

                    // 2. ORTA: Bütünleşik Bilgi Modülü (Sol Lastikler + Yol Uyarıları & Koridor + Sağ Lastikler)
                    EtubuClusterCenterInfoModule(
                        theme: theme,
                        width: max(160, boxW + sideW * 2 + 10),
                        height: dialBase,
                        contentScale: max(0.88, layoutScale * 1.05),
                        criticalAlertsOn: criticalAlertsOn,
                        remotePinUnderWarn: remotePinUnderWarn,
                        tesla: tesla
                    )
                    .frame(width: max(160, boxW + sideW * 2 + 10), height: dialBase)
                    .layoutPriority(2)

                    // 3. SAĞ: Soldaki Hız Kadranı ile TAM AYNI ÖLÇÜDE Dairesel Çok Fonksiyonlu Gösterge
                    EtubuRightMultiDialView(
                        theme: theme,
                        diameter: dialMax,
                        chromeDiameter: dialBase,
                        hasActiveRoute: hasActiveRouteChrome,
                        routeDestinationText: routeDestinationText
                    )
                    .frame(width: dialMax, height: dialMax)
                    .layoutPriority(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                landscapeBottomBar
                    .padding(.horizontal, 4)
                    .layoutPriority(2)
            } else {
                // 2. KLASİK / TEK KARTLI DÜZEN:
                // - Sol: Saate doğru yukarı alınmış araç silüeti ve lastik basınçları (şeffaf zemin)
                // - Orta-Sol: Dikeyde tam ortada Hız Kadranı
                // - Sağ Taraf: Sağ tarafa yaklaştırılmış, dikeyde tam ortada Yol Uyarıları & Ortalama Hız (şeffaf, çerçevesiz) ve Rota Menüsü
                let singleDialSize = min(dialMax * 1.12, layout.canvas.height * 0.82)
                let cardBoxW = min(boxW, 136)
                let routeBoxW = min(boxW, 140)

                HStack(alignment: .center, spacing: layout.isCompactWidth ? 8 : 12) {
                    // 1. Sol: Saate Doğru Yukarı Alınmış Araç Grafiği & Lastik Basınçları (Şeffaf Zemin)
                    VStack(alignment: .leading, spacing: 2) {
                        EtubuTPMSGridView(
                            telemetry: telemetry,
                            noseUp: true,
                            compact: true,
                            maxWidth: min(126, boxW * 0.95),
                            maxHeight: min(126, dialBase * 0.82)
                        )
                        Spacer(minLength: 0)
                    }
                    .frame(width: boxW, height: singleDialSize, alignment: .topLeading)
                    .layoutPriority(1)

                    Spacer(minLength: 4)

                    // 2. Orta-Sol: Dikeyde Tam Ortada, Büyütülmüş Hız Kadranı
                    speedDialWithThemeGesture(
                        compact: true,
                        diameter: singleDialSize,
                        chromeDiameter: dialBase * 1.10
                    )
                    .frame(width: singleDialSize, height: singleDialSize)
                    .layoutPriority(3)

                    Spacer(minLength: 6)

                    // 3. Sağ Taraf: Sağ Tarafa Yaklaştırılmış, Dikeyde Tam Ortada Yol Uyarıları & Hız Koridoru (Şeffaf, Çerçevesiz)
                    twinCardsColumn(
                        dialSize: singleDialSize * 0.90,
                        boxW: cardBoxW,
                        contentScale: max(0.85, layoutScale * 1.0)
                    )
                    .frame(width: cardBoxW, height: singleDialSize * 0.90, alignment: .center)
                    .layoutPriority(2)

                    // 4. En Sağ: Dikeyde Tam Ortada Rota Bilgisi Menüsü (Şeffaf)
                    landscapeRouteColumn(
                        dialSize: singleDialSize * 0.90,
                        boxW: routeBoxW,
                        contentScale: max(0.85, layoutScale * 1.0)
                    )
                    .frame(width: routeBoxW, alignment: .center)
                    .layoutPriority(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                landscapeBottomBar
                    .padding(.horizontal, 4)
                    .layoutPriority(2)
            } // !powerSaveMode
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

    private func refreshCachedWinInsets() {
        let next = Self.windowSafeInsets()
        guard next != cachedWinInsets else { return }
        cachedWinInsets = next
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

    private func panelValueRow(_ value: String) -> some View {
        Text(value)
            .font(EtubuClusterFonts.ui(14, weight: .semibold))
            .foregroundStyle(theme.primaryText.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Jul 29 twin panels — equal size, shared chrome, never overlap.
    private let twinCardGap: CGFloat = 8

    private func twinCardHeight(dialSize: CGFloat) -> CGFloat {
        max(56, (dialSize - twinCardGap) / 2)
    }

    /// Landscape right column: Route information strip (destination, arrival SoC, distance, map links, charge suggestions).
    @ViewBuilder
    private func landscapeRouteColumn(dialSize: CGFloat, boxW: CGFloat, contentScale: CGFloat) -> some View {
        let routeW = max(boxW, 148)
        VStack(alignment: .leading, spacing: 6) {
            if hasActiveRouteChrome, !routeDestinationText.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routeDestinationText)
                        .font(EtubuClusterFonts.ui(12, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    EtubuArrivalWeatherIsolated(theme: theme, compact: true)
                }
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(EtubuClusterL10n.energyAtArrival)
                        .font(EtubuClusterFonts.ui(9, weight: .medium))
                        .foregroundStyle(theme.mutedText)
                    HStack(spacing: 3) {
                        Text(telemetry.energyAtArrivalPercent.map { "\($0)%" } ?? (hasActiveRouteChrome ? "—" : "—"))
                            .font(EtubuClusterFonts.ui(13, weight: .bold))
                            .foregroundStyle(arrivalSocTint)
                            .accessibilityIdentifier("etubu.ev.landscapeArrivalSoc")
                        Text("→\(evPlan.targetArrivalSoc)%")
                            .font(EtubuClusterFonts.ui(9, weight: .medium))
                            .foregroundStyle(theme.mutedText)
                    }
                }
                if let _ = telemetry.effectiveRemainKm {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(EtubuClusterL10n.distance)
                            .font(EtubuClusterFonts.ui(9, weight: .medium))
                            .foregroundStyle(theme.mutedText)
                        Text(telemetry.navRemainLabel)
                            .font(EtubuClusterFonts.ui(13, weight: .semibold))
                            .foregroundStyle(theme.primaryText.opacity(0.9))
                    }
                }
                Spacer(minLength: 0)
            }

            routeMapLinkButtons(compact: true)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(hasActiveRouteChrome ? 1 : 0.85)

            chargeSuggestionBlock(compact: true)
        }
        .padding(4)
        .background(Color.clear)
        .frame(width: routeW, alignment: .center)
    }

    private func twinCardsColumn(dialSize: CGFloat, boxW: CGFloat, contentScale: CGFloat) -> some View {
        let boxH = twinCardHeight(dialSize: dialSize)
        let pinH: CGFloat = remotePinUnderWarn ? max(30, min(38, boxW * 0.24)) : 0
        let gapExtra: CGFloat = remotePinUnderWarn ? 4 : 0
        return VStack(spacing: 4) {
            if criticalAlertsOn {
                roadWarningCard(width: boxW, height: boxH, contentScale: contentScale)
                    .frame(width: boxW, height: boxH)
                    .clipped()
            }
            avgSpeedCard(width: boxW, height: boxH, contentScale: contentScale)
                .frame(width: boxW, height: boxH)
                .clipped()
            if remotePinUnderWarn, criticalAlertsOn {
                EtubuRemotePinnedBar(width: boxW, theme: theme, tesla: tesla)
                    .frame(width: boxW, height: pinH)
            }
        }
        .frame(width: boxW, height: dialSize + (remotePinUnderWarn && criticalAlertsOn ? pinH + gapExtra : 0), alignment: .center)
    }

    /// Jul 29 web-style avg panel (trip avg / corridor avg).
    private func avgSpeedCard(width: CGFloat, height: CGFloat, contentScale: CGFloat = 1) -> some View {
        let _ = l10nTick
        return EtubuCorridorChipIsolated(
            theme: theme,
            compact: height < 100,
            contentScale: contentScale
        )
        .equatable()
        .frame(width: width, height: height, alignment: .top)
        .clipped()
    }

    /// Twin of avg — identical outer size; content clipped inside frame.
    private func roadWarningCard(width: CGFloat, height: CGFloat, contentScale: CGFloat = 1) -> some View {
        let _ = l10nTick
        return EtubuRoadWarnTwinIsolated(
            theme: theme,
            compact: height < 100,
            contentScale: contentScale
        )
        .equatable()
        .frame(width: width, height: height, alignment: .top)
        .clipped()
    }

    private func speedDialWithThemeGesture(
        compact: Bool,
        diameter: CGFloat,
        chromeDiameter: CGFloat? = nil
    ) -> some View {
        EtubuClusterSpeedDialHost(
            compact: compact,
            diameter: diameter,
            chromeDiameter: chromeDiameter,
            theme: theme,
            onCycleTheme: { next in cycleTheme(next: next) }
        )
        .equatable()
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

    private func landscapeTopBar(_ layout: EtubuClusterLayoutMetrics) -> some View {
        let _ = telemetry.climateEpoch
        let _ = telemetry.chargeEpoch
        return HStack(spacing: layout.chromeGap) {
            if !powerSaveMode {
                Text(timeString)
                    .font(EtubuClusterFonts.ui(layout.isCompactHeight ? 13 : 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let out = telemetry.outsideC {
                    Text(String(format: "%.0f°C", out))
                        .font(EtubuClusterFonts.ui(layout.isCompactHeight ? 13 : 15, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                } else if telemetry.isAwaitingClimate {
                    Text(EtubuClusterL10n.t("awaitingClimate"))
                        .font(EtubuClusterFonts.ui(11, weight: .medium))
                        .foregroundStyle(theme.mutedText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("--°C")
                        .font(EtubuClusterFonts.ui(layout.isCompactHeight ? 13 : 15, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                }
                if let inside = telemetry.insideC {
                    Text(String(format: EtubuClusterL10n.t("insideTempFmt"), inside))
                        .font(EtubuClusterFonts.ui(12, weight: .medium))
                        .foregroundStyle(theme.mutedText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                speedSourceChip
                gpsStatusChip
                Text(telemetry.connectionQualityLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
                    .frame(maxWidth: layout.isCompactWidth ? 72 : 96, alignment: .leading)
            } else {
                Text(timeString)
                    .font(EtubuClusterFonts.ui(15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText.opacity(0.9))
            }

            Spacer(minLength: 6)

            topChromeControls(layout: layout, compact: true, hit: layout.iconHit)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .onChange(of: powerSaveMode) { _, on in
            EtubuTeslaBleSession.shared.setPowerSave(on)
        }
    }

    /// Üst sağ kontroller: tek butona toplanır / açılır; uzaktan kumanda her zaman görünür.
    @ViewBuilder
    private func topChromeControls(layout: EtubuClusterLayoutMetrics, compact: Bool, hit: CGFloat?) -> some View {
        HStack(spacing: layout.chromeGap) {
        if !chromeExpanded {
            remoteChromeButton(compact: compact, hit: hit)
            if powerSaveMode {
                powerSaveChromeButton(compact: compact, hit: hit)
            }
            Button {
                withAnimation(.easeOut(duration: 0.18)) { chromeExpanded = true }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(compact ? .system(size: 18, weight: .semibold) : .title3.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: hit, height: hit)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(EtubuClusterL10n.t("chromeExpand"))
            .accessibilityIdentifier("etubu.chrome.expand")
        } else {
            if !powerSaveMode {
                Button { showVINEditor = true } label: {
                    EtubuPairConnectionBadge(
                        connectionState: telemetry.connectionState,
                        theme: theme,
                        label: nil,
                        compact: compact,
                        showPulse: false
                    )
                    .frame(width: hit, height: hit, alignment: .center)
                }
                .clusterHotspot(.pair)

                if criticalAlertsOn {
                    Button {
                        EtubuRouteBridge.primeWarningAudio()
                        openRouteOrPaywall()
                    } label: {
                        Image(systemName: telemetry.routeActive
                              ? (compact ? "point.topleft.down.to.point.bottomright.curvepath.fill" : "map.fill")
                              : (compact ? "point.topleft.down.to.point.bottomright.curvepath" : "map"))
                            .font(compact ? .body.weight(.semibold) : .title3.weight(.semibold))
                            .foregroundStyle(telemetry.routeActive ? theme.accent : (compact ? theme.secondaryText : theme.mutedText))
                            .frame(width: hit, height: hit)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(EtubuClusterL10n.route)
                    .accessibilityIdentifier("etubu.route.open")
                    .clusterHotspot(.route)
                }

                powerSaveChromeButton(compact: compact, hit: hit)

                chromeExitButton(compact: compact, hit: hit)
            }

            remoteChromeButton(compact: compact, hit: hit)

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(compact ? .system(size: 14, weight: .semibold) : .title3.weight(.semibold))
                    .foregroundStyle(theme.primaryText.opacity(0.85))
                    .frame(width: hit, height: hit)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(EtubuClusterL10n.settings)
            .accessibilityIdentifier("etubu.settings.open")
            .clusterHotspot(.settings)

            if powerSaveMode {
                powerSaveChromeButton(compact: compact, hit: hit)
            }

            Button {
                withAnimation(.easeOut(duration: 0.18)) { chromeExpanded = false }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(compact ? .system(size: 16, weight: .semibold) : .title3.weight(.semibold))
                    .foregroundStyle(theme.mutedText)
                    .frame(width: hit, height: hit)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(EtubuClusterL10n.t("chromeCollapse"))
            .accessibilityIdentifier("etubu.chrome.collapse")
        }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.65))
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    theme.stroke.opacity(0.6),
                                    theme.accent.opacity(0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                )
                .shadow(color: Color.black.opacity(0.65), radius: 5, x: 0, y: 1)
        )
        .layoutPriority(1)
    }

    @ViewBuilder
    private func remoteChromeButton(compact: Bool, hit: CGFloat?) -> some View {
        Button { showRemoteCommands = true } label: {
            Image(systemName: "car.side.front.open")
                .font(compact ? .body.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(telemetry.connectionState == .connected
                                 ? theme.accent
                                 : (compact ? theme.secondaryText : theme.mutedText))
                .frame(width: hit, height: hit)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(EtubuClusterL10n.t("remoteCmdSection"))
        .accessibilityIdentifier("etubu.remote.open")
        .clusterHotspot(.remote)
    }

    @ViewBuilder
    private func powerSaveChromeButton(compact: Bool, hit: CGFloat?) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                powerSaveMode.toggle()
            }
            EtubuTeslaBleSession.shared.setPowerSave(powerSaveMode)
        } label: {
            Image(systemName: powerSaveMode ? "leaf.circle.fill" : "leaf.circle")
                .font(compact ? .system(size: 16, weight: .semibold) : .title3.weight(.semibold))
                .foregroundStyle(powerSaveMode ? theme.accent : theme.mutedText)
                .frame(width: hit, height: hit, alignment: .center)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(EtubuClusterL10n.t("powerSaveMode"))
        .accessibilityValue(powerSaveMode ? EtubuClusterL10n.t("powerSaveOn") : EtubuClusterL10n.t("powerSaveOff"))
        .accessibilityIdentifier("etubu.powerSave")
    }

    /// Settings sağında tam uygulama çıkışı (BLE disconnect değil).
    @ViewBuilder
    private func chromeExitButton(compact: Bool, hit: CGFloat? = nil) -> some View {
        Button {
            showExitConfirm = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(compact ? .system(size: 14, weight: .semibold) : .title3.weight(.semibold))
                .foregroundStyle(theme.mutedText)
                .frame(width: hit, height: hit)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(EtubuClusterL10n.appExit)
        .accessibilityIdentifier("etubu.exit")
    }

    /// Settings sağında varış enerji (araç SoC / menzil / kalan rota).
    @ViewBuilder
    private func arrivalEnergyChip(compact: Bool) -> some View {
        let _ = telemetry.chargeEpoch
        let _ = telemetry.demoUIEpoch
        let label = telemetry.energyAtArrivalPercent.map { "\($0)%" } ?? "—"
        HStack(spacing: compact ? 3 : 4) {
            Image(systemName: "bolt.car.fill")
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
            Text(label)
                .font(EtubuClusterFonts.ui(compact ? 11 : 12, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(arrivalSocTint)
        .padding(.horizontal, compact ? 7 : 8)
        .padding(.vertical, compact ? 5 : 6)
        .background(Capsule().fill(theme.surface.opacity(0.9)))
        .accessibilityLabel(EtubuClusterL10n.energyAtArrival)
        .accessibilityValue(label)
        .accessibilityIdentifier("etubu.ev.arrivalSoc.chrome")
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

    @ViewBuilder
    private func routeMapLinkButtons(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            Button {
                EtubuRouteBridge.openInMaps(
                    destinationName: routeDestinationText.isEmpty ? "Etubu rota" : routeDestinationText
                )
            } label: {
                Label(EtubuClusterL10n.t("openInMaps"), systemImage: "map")
                    .font(EtubuClusterFonts.ui(compact ? 11 : 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.mapHudText)
            .shadow(color: .black.opacity(0.75), radius: 1.2, y: 1)
            .accessibilityIdentifier("etubu.route.openMaps")

            Button {
                EtubuRouteBridge.openNearestChargeInMaps()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Label(EtubuClusterL10n.t("nearestCharge"), systemImage: "bolt.car.fill")
                        .font(EtubuClusterFonts.ui(compact ? 11 : 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let cap = warnings.nearestChargeCaption {
                        Text(cap)
                            .font(EtubuClusterFonts.ui(compact ? 9 : 10, weight: .medium))
                            .foregroundStyle(theme.mutedText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.mapHudMuted)
            .shadow(color: .black.opacity(0.75), radius: 1.2, y: 1)
            .accessibilityIdentifier("etubu.route.nearestCharge")
        }
    }

    /// Portrait: kompakt EV / rota şeridi (varış SoC, şarj, Maps).
    private var portraitEvStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasActiveRouteChrome, !routeDestinationText.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routeDestinationText)
                        .font(EtubuClusterFonts.ui(12, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    EtubuArrivalWeatherIsolated(theme: theme, compact: true)
                }
            }
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
            }
            routeMapLinkButtons(compact: true)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.clear)
            .opacity(hasActiveRouteChrome ? 1 : 0.85)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("etubu.ev.portraitStrip")
        }
    }

    @ViewBuilder
    private func chargeSuggestionBlock(compact: Bool) -> some View {
        if let plan = evPlan.plan, hasActiveRouteChrome || plan.needsCharge || !plan.legs.isEmpty {
            EtubuEnergyPlanCard(
                plan: plan,
                compact: compact,
                accent: theme.accent,
                muted: compact ? theme.mutedText : theme.mapHudMuted,
                primary: compact ? theme.primaryText : theme.mapHudText,
                onStop: { EtubuRouteBridge.openChargeStop($0.hazard) }
            )
        } else {
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
    }

    @ViewBuilder
    private func navRow(_ title: String, value: String) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(EtubuClusterFonts.ui(10, weight: .semibold))
                    .foregroundStyle(theme.mapHudMuted)
                Text(trimmed)
                    .font(EtubuClusterFonts.ui(15, weight: .bold))
                    .foregroundStyle(theme.mapHudText)
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var landscapeBottomBar: some View {
        HStack(alignment: .center, spacing: 10) {
            soundControl(compact: true)
            // Sağ dairesel gösterge şarj modunda değilken veya klasik kartlar düzenindeyken sol altta bataryayı göster.
            // Şarj göstergesi sağ kadrana geçtiğinde sol alttaki gösterge kaldırılır.
            if layoutStyle == .classicCards || storedRightDialModeRaw != RightDialMode.battery.rawValue {
                HStack(spacing: 6) {
                    Image(systemName: "battery.100")
                        .foregroundStyle(theme.accent)
                    Text(batteryRangeLabel)
                        .font(EtubuClusterFonts.ui(14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.primaryText.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            Spacer(minLength: 4)
            Text(telemetry.odometerKm.map { "ODO \($0) km" } ?? "ODO — km")
                .font(EtubuClusterFonts.ui(13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.mapHudText)
                .shadow(color: .black.opacity(0.8), radius: 1.2, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .clipped()
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
            HStack(spacing: 4) {
                if !powerSaveMode {
                    speedSourceChip
                    gpsStatusChip
                }
                Spacer(minLength: 4)
                topChromeControls(layout: layout, compact: layout.chromeCompact, hit: hit)
            }
            .padding(.horizontal, hPad)
            .padding(.top, topChrome)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity)
            .onChange(of: powerSaveMode) { _, on in
                EtubuTeslaBleSession.shared.setPowerSave(on)
            }

            Spacer(minLength: layout.contentVGap)

            if powerSaveMode {
                // Yalnız hız kadranı + regen — tüm temalarda aynı sade pano.
                VStack(spacing: short ? 8 : 12) {
                    speedDialWithThemeGesture(compact: false, diameter: portraitDialSize)
                    EtubuPowerRegenBarView(powerKw: telemetry.powerKw, compact: short, theme: theme)
                        .padding(.horizontal, short ? 18 : 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            VStack(spacing: 0) {
            HStack(alignment: .center, spacing: layout.isCompactWidth ? 6 : 10) {
                Spacer(minLength: 0)
                speedDialWithThemeGesture(compact: false, diameter: portraitDialSize)
                twinCardsColumn(
                    dialSize: portraitDialSize,
                    boxW: portraitBoxW,
                    contentScale: cardScale
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, hPad)
            .layoutPriority(5)

            EtubuPowerRegenBarView(powerKw: telemetry.powerKw, compact: short, theme: theme)
                .padding(.horizontal, short ? 18 : 28)
                .padding(.top, short ? 4 : 8)
                .layoutPriority(4)

            Spacer(minLength: short ? 2 : 8)

            portraitEvStrip
                .padding(.horizontal, short ? 12 : 22)
                .layoutPriority(2)

            if !short {
                EtubuChargeDetailChip(telemetry: telemetry)
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
                EtubuMediaNowPlayingView(telemetry: telemetry)
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
            }

            Spacer(minLength: short ? 2 : 6)

            HStack(alignment: .center, spacing: 12) {
                soundControl(compact: short)
                Spacer()
            }
            .padding(.horizontal, short ? 16 : 22)
            .padding(.bottom, short ? 2 : 6)

            Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()

            portraitBottomTelemetry(layout, short: short)
            } // end !powerSaveMode
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .safeAreaPadding(.top, layout.cutoutStyle == .none ? 0 : 2)
    }

    private func portraitBottomTelemetry(_ layout: EtubuClusterLayoutMetrics, short: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            tpmsGrid(layout: layout, portrait: true)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                let _ = telemetry.chargeEpoch
                Text(timeString)
                    .font(EtubuClusterFonts.gauge(short ? 26 : 36))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
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
        .padding(.leading, layout.bottomClusterLead)
        .padding(.trailing, layout.bottomClusterTrail)
        .padding(.bottom, layout.bottomClusterPad)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .clipped()
    }

    private func tpmsGrid(layout: EtubuClusterLayoutMetrics, portrait: Bool) -> some View {
        EtubuTPMSGridView(
            telemetry: telemetry,
            noseUp: true,
            compact: portrait || layout.isCompactWidth || layout.isCompactHeight,
            maxWidth: layout.tpmsMaxW,
            maxHeight: layout.tpmsMaxH
        )
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
                            .font(EtubuClusterFonts.ui(11, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(theme.mutedText)
                            .textCase(.uppercase)
                        Spacer()
                        Button(EtubuClusterL10n.close) {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            showVINEditor = false
                        }
                        .font(EtubuClusterFonts.ui(14, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    }
                    HStack(spacing: 10) {
                        TextField("5YJ…", text: $vinDraft)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .padding(12)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(theme.stroke, lineWidth: 1)
                            )
                            .foregroundStyle(theme.primaryText)
                            .focused($vinFocused)
                        Button {
                            vinFocused = false
                            Task { await tesla.saveVINAndPair(vinDraft) }
                        } label: {
                            Text(tesla.pairStep == .sendingRequest || tesla.pairStep == .connectingAfterCard
                                 ? "…" : EtubuClusterL10n.t("pairAction"))
                                .font(EtubuClusterFonts.ui(14, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

                    let otherVins = EtubuTeslaVinStore.recents.filter { $0 != EtubuTeslaVinStore.normalize(vinDraft) }
                    if !kbOpen, !otherVins.isEmpty {
                        Text(EtubuClusterL10n.t("recentVins"))
                            .font(EtubuClusterFonts.ui(11, weight: .heavy))
                            .foregroundStyle(theme.mutedText)
                            .textCase(.uppercase)
                        ForEach(otherVins, id: \.self) { vin in
                            Button {
                                vinDraft = vin
                                vinFocused = false
                                Task {
                                    await tesla.switchToVIN(vin)
                                }
                            } label: {
                                HStack {
                                    Text(vin)
                                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                                        .foregroundStyle(theme.primaryText)
                                    Spacer()
                                    Text(EtubuClusterL10n.t("switchVin"))
                                        .font(EtubuClusterFonts.ui(12, weight: .bold))
                                        .foregroundStyle(theme.accent)
                                }
                                .padding(10)
                                .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(theme.stroke, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !kbOpen {
                        HStack(spacing: 10) {
                            Button {
                                Task { await tesla.connectSaved() }
                            } label: {
                                Text(EtubuClusterL10n.t("connect"))
                                    .font(EtubuClusterFonts.ui(12, weight: .bold))
                                    .foregroundStyle(theme.primaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(theme.stroke, lineWidth: 1)
                                    )
                            }
                            Button {
                                Task { await tesla.repair() }
                            } label: {
                                Text(EtubuClusterL10n.t("rePair"))
                                    .font(EtubuClusterFonts.ui(12, weight: .bold))
                                    .foregroundStyle(theme.primaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(theme.accent.opacity(0.45), lineWidth: 1)
                                    )
                            }
                        }
                        Text(telemetry.statusMessage)
                            .font(EtubuClusterFonts.ui(12, weight: .medium))
                            .foregroundStyle(theme.mutedText)
                        Text(EtubuClusterL10n.t("pairNfcHint"))
                            .font(EtubuClusterFonts.ui(11, weight: .medium))
                            .foregroundStyle(theme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .etubuSheetCard(theme)
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
                        Text(tesla.needsRePairing
                             ? EtubuClusterL10n.t("bleNeedsRePairAction")
                             : EtubuClusterL10n.t("retry"))
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
        case .failed:
            return tesla.needsRePairing
                ? EtubuClusterL10n.t("bleNeedsRePairTitle")
                : EtubuClusterL10n.t("pairGuideFailed")
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

    private struct SettingsHost: View, Equatable {
        struct Snap: Equatable {
            var lang: EtubuAppLanguage
            var l10nTick: Int
            var theme: ClusterTheme
            var wallpaper: EtubuWallpaperStyle
            var demoRunning: Bool
            var conn: String
            var src: String
            var needsCharge: Bool
            var chargeN: Int
            var soundOn: Bool
            var voice: String
            var mix: String
            var stealth: Bool
            var stealthA: Bool
            var map: Bool
            var loc: Bool
            var premium: Bool
            var soc: Int
            var remoteLim: Double
            var alertVol: Double
            var alertOver: Bool
            var notch: Bool
            var obd: Bool
        }

        let snap: Snap
        @Binding var theme: ClusterTheme
        @Binding var wallpaper: EtubuWallpaperStyle
        @Binding var appLanguage: EtubuAppLanguage
        @Binding var showSettings: Bool
        @Binding var showExitConfirm: Bool
        @Binding var showVINEditor: Bool
        @Binding var showObdMenu: Bool
        @Binding var showPremiumPaywall: Bool
        @Binding var showRoutePicker: Bool
        @Binding var premiumPaywallHint: String?
        @Binding var soundOn: Bool
        @Binding var selectedVoice: String
        @Binding var mixMode: String
        @Binding var alertOverMusic: Bool
        @Binding var alertVolume: Double
        @Binding var stealthMode: Bool
        @Binding var stealthAnalog: Bool
        @Binding var mapEnabled: Bool
        @Binding var locationEnabled: Bool
        @Binding var notchAuraEnabled: Bool
        @Binding var remoteChargeLimit: Double

        @ObservedObject private var demo = EtubuDemoDrive.shared
        @ObservedObject private var tesla = EtubuTeslaBleSession.shared
        @ObservedObject private var evPlan = EtubuEvRoutePlanner.shared
        @ObservedObject private var trips = EtubuTripHistoryStore.shared
        @ObservedObject private var premium = EtubuPremiumManager.shared

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.snap == rhs.snap }

        private var criticalAlertsOn: Bool { appLanguage.criticalAlertsEnabled }

        private func openPremium(hintKey: String? = nil) {
            guard !EtubuPremiumManager.isPaidAppModel else { return }
            premiumPaywallHint = hintKey.map { EtubuClusterL10n.t($0) }
            showPremiumPaywall = true
        }

        private func openRouteOrPaywall() {
            if premium.isPremium {
                showSettings = false
                showRoutePicker = true
                return
            }
            if !premium.entitlementReady {
                Task { @MainActor in
                    await premium.ensureEntitlementChecked()
                    openRouteOrPaywall()
                }
                return
            }
            showSettings = false
            openPremium(hintKey: "premiumLockedRoute")
        }

        var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(EtubuAppLanguage.allCases) { lang in
                        Button {
                            appLanguage = lang
                            EtubuAppLanguage.setManual(lang)
                        } label: {
                            HStack {
                                Text(lang.title)
                                    .font(EtubuClusterFonts.ui(16, weight: .medium))
                                    .foregroundStyle(theme.primaryText)
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
                } header: {
                    EtubuSheetSectionTitle(title: EtubuClusterL10n.language, theme: theme, motion: .language)
                }
                .etubuSheetSection(theme)

                Section {
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
                        .font(EtubuClusterFonts.ui(16, weight: .semibold))
                    }
                    .accessibilityIdentifier("etubu.demo.toggle")
                    Toggle(EtubuClusterL10n.t("demoMirror"), isOn: $demo.mirrorEnabled)
                    EtubuSheetHint(text: EtubuClusterL10n.t("demoHint"), theme: theme)
                    Button(role: .destructive) {
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showExitConfirm = true
                        }
                    } label: {
                        Label(EtubuClusterL10n.appExit, systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("etubu.app.exit")
                    .accessibilityLabel(EtubuClusterL10n.appExit)
                } header: {
                    EtubuSheetSectionTitle(title: EtubuClusterL10n.t("settingsGroupApp"), theme: theme, motion: .app)
                }
                .etubuSheetSection(theme)

                Section {
                    Button(EtubuClusterL10n.pairVin) { showSettings = false; showVINEditor = true }
                    Button(EtubuClusterL10n.reconnectTesla) { Task { await tesla.connectSaved() } }
                    Button(EtubuClusterL10n.disconnectTesla) { Task { await tesla.disconnect() } }
                    Button(EtubuClusterL10n.forgetVehicle, role: .destructive) {
                        Task { await tesla.clearVehicle() }
                        showVINEditor = true
                    }
                    Button(EtubuClusterL10n.obdFallback) { showObdMenu = true }
                    LabeledContent(EtubuClusterL10n.quality, value: snap.conn)
                    LabeledContent(EtubuClusterL10n.source, value: snap.src)
                    Toggle(EtubuClusterL10n.t("vehicleNotifyToggle"), isOn: Binding(
                        get: { EtubuVehicleLaunchNotifier.isEnabled },
                        set: { newValue in
                            EtubuVehicleLaunchNotifier.isEnabled = newValue
                            if newValue {
                                EtubuVehicleLaunchNotifier.shared.requestAuthorizationIfNeeded()
                            }
                        }
                    ))
                    EtubuSheetHint(text: EtubuClusterL10n.t("vehicleNotifyHint"), theme: theme)
                } header: {
                    EtubuSheetSectionTitle(title: EtubuClusterL10n.t("settingsGroupVehicle"), theme: theme, motion: .vehicle)
                }
                .etubuSheetSection(theme)

                Section {
                    if criticalAlertsOn {
                        Button {
                            showSettings = false
                            EtubuRouteBridge.primeWarningAudio()
                            openRouteOrPaywall()
                        } label: {
                            Label(EtubuClusterL10n.pickRoute, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(EtubuClusterL10n.t("targetArrivalSoc"))
                            Spacer()
                            Text("\(evPlan.targetArrivalSoc)%")
                                .font(EtubuClusterFonts.gauge(18))
                                .foregroundStyle(theme.accent)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("etubu.settings.evRoutePlan")
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
                        EtubuSheetHint(text: EtubuClusterL10n.t("evPlanHint"), theme: theme)
                        if let plan = evPlan.plan {
                            EtubuEnergyPlanCard(
                                plan: plan,
                                compact: false,
                                accent: theme.accent,
                                muted: theme.mutedText,
                                primary: theme.primaryText,
                                onStop: { EtubuRouteBridge.openChargeStop($0.hazard) }
                            )
                            .padding(.top, 4)
                        } else if snap.needsCharge {
                            Text(String(format: EtubuClusterL10n.t("chargeSuggestFmt"), max(snap.chargeN, 1)))
                                .font(EtubuClusterFonts.ui(13, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                    if premium.isPremium {
                        Toggle(EtubuClusterL10n.t("mapEnabled"), isOn: $mapEnabled)
                    } else {
                        Button {
                            showSettings = false
                            openPremium(hintKey: "premiumLockedMap")
                        } label: {
                            HStack {
                                Text(EtubuClusterL10n.t("mapEnabled"))
                                Spacer()
                                EtubuPremiumBadge(compact: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    EtubuSheetHint(text: EtubuClusterL10n.t("mapEnabledHint"), theme: theme)
                    Toggle(EtubuClusterL10n.t("locationEnabled"), isOn: $locationEnabled)
                        .onChange(of: locationEnabled) { _, enabled in
                            EtubuMapLocationHelper.shared.setLocationEnabled(enabled)
                        }
                    EtubuSheetHint(text: EtubuClusterL10n.t("locationEnabledHint"), theme: theme)
                } header: {
                    EtubuSheetSectionTitle(title: EtubuClusterL10n.t("settingsGroupRoute"), theme: theme, motion: .route)
                }
                .etubuSheetSection(theme)

                Section {
                    EtubuTripAnalyticsView(store: trips, accent: theme.accent)
                    if let url = trips.exportCSV() {
                        ShareLink(item: url) {
                            Label(EtubuClusterL10n.t("tripExportCSV"), systemImage: "square.and.arrow.up")
                        }
                    }
                    if let gpx = trips.exportGPX() {
                        ShareLink(item: gpx) {
                            Label(EtubuClusterL10n.t("tripExportGpx"), systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                        }
                    }
                    Button(EtubuClusterL10n.t("tripClearHistory"), role: .destructive) {
                        trips.clearAll()
                    }
                } header: {
                    EtubuSheetSectionTitle(title: EtubuClusterL10n.t("settingsGroupTrip"), theme: theme, motion: .trip)
                }
                .etubuSheetSection(theme)

                Section {
                    DisclosureGroup {
                        EtubuRemoteCommandCards(tesla: tesla)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(EtubuClusterL10n.t("cmdChargeLimit"))
                                Spacer()
                                Text("\(Int(remoteChargeLimit))%")
                                    .font(EtubuClusterFonts.gauge(16))
                            }
                            Slider(value: $remoteChargeLimit, in: 50...100, step: 5)
                            Button(EtubuClusterL10n.t("cmdApplyLimit")) {
                                Task { await tesla.setChargeLimit(Int(remoteChargeLimit)) }
                            }
                        }
                    } label: {
                        Label(EtubuClusterL10n.t("remoteCmdSection"), systemImage: "car.side.front.open")
                            .font(EtubuClusterFonts.ui(16, weight: .semibold))
                    }
                    EtubuRemotePinSettingsSection()
                } header: {
                    EtubuSheetSectionTitle(title: EtubuClusterL10n.t("settingsGroupRemote"), theme: theme, motion: .remote)
                }
                .etubuSheetSection(theme)

                Section {
                    EtubuThemeStoreView(theme: $theme, wallpaper: $wallpaper) {
                        showSettings = false
                        openPremium(hintKey: "premiumLockedTheme")
                    }
                    Toggle(EtubuClusterL10n.t("notchAuraToggle"), isOn: $notchAuraEnabled)
                    EtubuSheetHint(text: theme.pickerTitle, theme: theme)
                    Toggle(EtubuClusterL10n.t("stealthMode"), isOn: $stealthMode)
                    if stealthMode {
                        Toggle(EtubuClusterL10n.t("stealthAnalog"), isOn: $stealthAnalog)
                    }
                    EtubuSheetHint(text: EtubuClusterL10n.t("stealthHint"), theme: theme)
                } header: {
                    EtubuSheetSectionTitle(title: EtubuClusterL10n.t("settingsGroupLook"), theme: theme, motion: .look)
                }
                .etubuSheetSection(theme)

                speedAndAlertsSections

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
                                let t = EtubuVehicleTelemetry.shared
                                EtubuClusterAudioBridge.startDrive(
                                    kmh: max(t.kmh, 0),
                                    gear: t.gear,
                                    source: t.source.rawValue,
                                    powerKw: t.powerKw
                                )
                            } else {
                                selectedVoice = "silent-mode"
                                EtubuClusterAudioBridge.setSoundEnabled(false, voice: "silent-mode")
                            }
                        }
                    ))
                    EtubuSheetHint(text: EtubuClusterL10n.t("voicePackShared"), theme: theme)
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
                            let t = EtubuVehicleTelemetry.shared
                            EtubuClusterAudioBridge.startDrive(
                                kmh: max(t.kmh, 0),
                                gear: t.gear,
                                source: t.source.rawValue,
                                powerKw: t.powerKw
                            )
                        } else {
                            EtubuClusterAudioBridge.setSoundEnabled(false, voice: "silent-mode")
                        }
                    }
                    Picker(EtubuClusterL10n.audioMix, selection: $mixMode) {
                        Text(EtubuClusterL10n.t("mixBlend")).tag("blend")
                        Text(EtubuClusterL10n.t("mixUnder")).tag("under")
                        Text(EtubuClusterL10n.t("mixSolo")).tag("solo")
                    }
                    .onChange(of: mixMode) { _, v in EtubuClusterAudioBridge.setMixMode(v) }
                    EtubuSheetHint(text: EtubuClusterL10n.t("mixCarHint"), theme: theme)
                    Toggle(EtubuClusterL10n.alertsOverMusic, isOn: $alertOverMusic)
                        .onChange(of: alertOverMusic) { _, on in
                            let mode = on ? "blend" : mixMode
                            mixMode = on ? "blend" : mixMode
                            EtubuClusterAudioBridge.setMixMode(on ? "blend" : mode)
                            AppDelegate.activateDriveAudioSession()
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(EtubuClusterL10n.alertDuck)
                            .font(EtubuClusterFonts.ui(12, weight: .medium))
                            .foregroundStyle(theme.mutedText)
                        Slider(value: $alertVolume, in: 0.2...1.0, step: 0.05)
                            .tint(theme.accent)
                            .onChange(of: alertVolume) { _, v in
                                EtubuClusterAudioBridge.setAlertVolume(v)
                            }
                    }
                } header: {
                    EtubuSheetSectionTitle(title: EtubuClusterL10n.t("settingsGroupSound"), theme: theme, motion: .sound)
                }
                .etubuSheetSection(theme)

                if criticalAlertsOn {
                    EtubuRadarSettingsView()
                }

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
                                .font(EtubuClusterFonts.ui(14, weight: .medium))
                                .foregroundStyle(theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            EtubuOnboardScreenshotStrip(theme: theme, highlight: nil)
                            Divider().overlay(theme.stroke.opacity(0.4))
                            EtubuOsmAttributionBlock()
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Label(EtubuClusterL10n.t("aboutApp"), systemImage: "info.circle")
                            .font(EtubuClusterFonts.ui(16, weight: .semibold))
                    }
                } header: {
                    EtubuSheetSectionTitle(title: EtubuClusterL10n.t("aboutApp"), theme: theme, motion: .about)
                }
                .etubuSheetSection(theme)
            }
            .etubuSheetList(theme)
            .environment(\.locale, appLanguage.locale)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    EtubuBrandMark(size: 28, showGlow: false)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(EtubuClusterL10n.done) { showSettings = false }
                        .font(EtubuClusterFonts.ui(16, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .accessibilityIdentifier("etubu.settings.done")
                }
            }
            .sheet(isPresented: $showObdMenu) {
                EtubuObdDevicePickerView(
                    telemetry: EtubuObdTelemetry.shared,
                    onSelect: { id in
                        EtubuObdBleManager.shared.connect(to: id) { _, _ in }
                        showObdMenu = false
                    },
                    onClose: { showObdMenu = false }
                )
                .preferredColorScheme(.dark)
            }
        }
        }

        @ViewBuilder
        private var speedAndAlertsSections: some View {
            Section {
                Picker(EtubuClusterL10n.t("speedUnitTitle"), selection: Binding(
                    get: { EtubuSpeedUnit.stored },
                    set: { EtubuSpeedUnit.stored = $0 }
                )) {
                    ForEach(EtubuSpeedUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                EtubuSheetHint(text: EtubuSpeedUnit.stored.isMph ? "Aktif: MPH" : "Aktif: KM/H", theme: theme)
            } header: {
                EtubuSheetSectionTitle(title: EtubuClusterL10n.t("speedUnitTitle"), theme: theme, motion: .look)
            }
            .etubuSheetSection(theme)

            Section {
                Toggle(EtubuClusterL10n.t("toggleHazards"), isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: "etubu.alert.hazards") as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: "etubu.alert.hazards") }
                ))
                Toggle(EtubuClusterL10n.t("toggleCorridor"), isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: "etubu.alert.corridor") as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: "etubu.alert.corridor") }
                ))
                Toggle(EtubuClusterL10n.t("toggleVoiceAlerts"), isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: "etubu.alert.voice") as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: "etubu.alert.voice") }
                ))
                Toggle(EtubuClusterL10n.t("toggleOverspeed"), isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: "etubu.alert.overspeed") as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: "etubu.alert.overspeed") }
                ))
            } header: {
                EtubuSheetSectionTitle(title: EtubuClusterL10n.t("roadAlertsTitle"), theme: theme, motion: .route)
            }
            .etubuSheetSection(theme)
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
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0)
            .foregroundStyle(theme.canvas)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .allowsTightening(true)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(minWidth: 28, maxWidth: 64)
            .background(Capsule().fill(sourceChipFill))
            .clipped()
            .accessibilityLabel(telemetry.speedSourceLabel)
            .accessibilityIdentifier("etubu.source.chip")
    }

    private var gpsStatusChip: some View {
        let ind = mapLocation.gpsIndicator
        let fill: Color = {
            switch ind {
            case .ok: return Color.green.opacity(0.9)
            case .denied: return Color.red.opacity(0.9)
            case .sim: return Color.orange.opacity(0.9)
            }
        }()
        let mark: String = {
            switch ind {
            case .ok: return "OK"
            case .denied: return "!"
            case .sim: return "SIM"
            }
        }()
        return HStack(spacing: 2) {
            Image(systemName: "location.fill")
                .font(.system(size: 8, weight: .bold))
            Text(mark)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(minWidth: 36, maxWidth: 58)
        .background(Capsule().fill(fill))
        .clipped()
        .accessibilityLabel(ind.label)
        .accessibilityIdentifier(ind.accessibilityId)
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
