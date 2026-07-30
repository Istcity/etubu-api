import SwiftUI
import MapKit

struct EtubuClusterRootView: View {
    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @ObservedObject private var tesla = EtubuTeslaBleSession.shared
    @ObservedObject private var warnings = EtubuDriveWarnings.shared

    @State private var theme: ClusterTheme = ClusterTheme.stored
    @State private var vinDraft: String = ""
    @State private var showVINEditor = false
    @State private var showSettings = false
    @State private var mixMode: String = "blend"
    @State private var soundOn = false
    @State private var showObdMenu = false
    @State private var now = Date()

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                backgroundLayer(landscape: landscape)

                if landscape {
                    landscapeLayout(size: geo.size)
                } else {
                    portraitLayout(size: geo.size)
                }

                if showVINEditor || telemetry.connectionState == .needsVIN {
                    vinOverlay
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if shouldShowPairGuide {
                    pairGuideOverlay
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onAppear {
            vinDraft = telemetry.vin
            theme = ClusterTheme.stored
            tesla.bootstrapIfPossible()
            warnings.startPolling()
            startLiveActivityShell()
        }
        .onDisappear { warnings.stopPolling() }
        .onReceive(clock) { now = $0 }
        .onChange(of: theme) { _, newValue in
            ClusterTheme.stored = newValue
            EtubuClusterAudioBridge.setTheme(newValue == .midnight ? "aurora" : newValue.rawValue == "cyberLime" ? "cyber-lime" : newValue.rawValue == "electricIce" ? "electric-ice" : newValue.rawValue == "solarFlare" ? "solar-flare" : newValue.rawValue == "violetStorm" ? "violet-storm" : newValue.rawValue == "deepOcean" ? "deep-ocean" : newValue.rawValue)
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .confirmationDialog("OBD fallback", isPresented: $showObdMenu, titleVisibility: .visible) {
            Button("Connect OBD BLE") { EtubuObdBleManager.shared.connect { _, _ in } }
            Button("Disconnect OBD", role: .destructive) { EtubuObdBleManager.shared.disconnect() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Background

    @ViewBuilder
    private func backgroundLayer(landscape: Bool) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if landscape {
                HStack(spacing: 0) {
                    Color.black.frame(maxWidth: .infinity)
                    mapBackdrop
                        .frame(maxWidth: .infinity)
                        .mask(
                            LinearGradient(colors: [.clear, .black, .black], startPoint: .leading, endPoint: .trailing)
                        )
                }
                .ignoresSafeArea()
            } else {
                VStack(spacing: 0) {
                    Color.black.frame(maxHeight: .infinity)
                    LinearGradient(colors: theme.washColors, startPoint: .top, endPoint: .bottom)
                        .frame(height: 280)
                        .blur(radius: 0.5)
                }
                .ignoresSafeArea()
                RadialGradient(colors: [theme.accent.opacity(0.2), .clear], center: .bottom, startRadius: 10, endRadius: 320)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    private var mapBackdrop: some View {
        Map(interactionModes: [])
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
            .colorScheme(.dark)
            .saturation(0.15)
            .contrast(1.1)
            .overlay {
                ZStack {
                    Color.black.opacity(0.35)
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.red)
                        .rotationEffect(.degrees(-8))
                        .offset(y: 40)
                        .shadow(color: .red.opacity(0.5), radius: 8)
                }
                .allowsHitTesting(false)
            }
    }

    // MARK: - Landscape (Dashla-like)

    private func landscapeLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {
            landscapeTopBar
                .padding(.horizontal, 18)
                // Keep clear of Dynamic Island / notch in landscape
                .padding(.top, 10)
                .padding(.bottom, 6)

            HStack(alignment: .center, spacing: 8) {
                navColumn
                    .frame(width: min(160, size.width * 0.18), alignment: .leading)

                VStack(spacing: 10) {
                    if let item = warnings.primary {
                        EtubuWarnBannerView(item: item, theme: theme)
                            .padding(.horizontal, 8)
                    }
                    EtubuCorridorChipView(warnings: warnings)
                    EtubuSpeedDialView(kmh: telemetry.kmh, gear: telemetry.gear, theme: theme, compact: size.height < 380)
                }
                .frame(maxWidth: .infinity)

                // Right map already in background — keep compass/controls in safe inset
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            compassBadge
                            Button { showSettings = true } label: {
                                Image(systemName: "location.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .padding(.trailing, 10)
                        .padding(.bottom, 8)
                    }
                }
                .frame(width: min(72, size.width * 0.1))
            }
            .frame(maxHeight: .infinity)

            landscapeBottomBar
                .padding(.horizontal, 20)
                // Lift off home indicator / bottom edge
                .padding(.top, 4)
                .padding(.bottom, 18)
        }
        .safeAreaPadding(.top, 4)
        .safeAreaPadding(.horizontal, 6)
    }

    private var landscapeTopBar: some View {
        HStack(spacing: 12) {
            Text(timeString)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
            Text(telemetry.outsideC.map { String(format: "%.0f°C", $0) } ?? "--°C")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.45))

            Spacer(minLength: 8)

            // Pair pill — trailing so Dynamic Island (center-top) stays clear
            Button {
                showVINEditor = true
            } label: {
                HStack(spacing: 6) {
                    connectionDot
                    Text(pairLabel)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }

            Text(batteryPhoneLabel)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var navColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            navRow("Destination", value: "—")
            navRow("Arrival Time", value: "—")
            navRow("Energy at Arrival", value: telemetry.socPercent.map { "\($0)%" } ?? "—")
            navRow("Distance", value: telemetry.rangeKm.map { "\($0) km" } ?? "—")
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }

    private func navRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
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
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer(minLength: 0)

            EtubuCorridorChipView(warnings: warnings)

            Text("ODO — km")
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var compassBadge: some View {
        ZStack {
            Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1).frame(width: 36, height: 36)
            Text("N")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Portrait (reference gradient cluster)

    private func portraitLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { showVINEditor = true } label: {
                    ZStack {
                        Circle().fill(telemetry.connectionState == .connected ? Color.green.opacity(0.85) : Color.red.opacity(0.85))
                            .frame(width: 34, height: 34)
                        Image(systemName: telemetry.connectionState == .connected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 8)

            if let item = warnings.primary {
                EtubuWarnBannerView(item: item, theme: theme)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            EtubuCorridorChipView(warnings: warnings)
                .padding(.bottom, 6)

            EtubuSpeedDialView(kmh: telemetry.kmh, gear: telemetry.gear, theme: theme)
                .frame(maxWidth: min(300, size.width * 0.78))

            powerSparkline
                .padding(.horizontal, 28)
                .padding(.top, 18)

            Spacer(minLength: 12)

            // Lifted mid-bottom row (EV sound was too low)
            HStack(alignment: .center, spacing: 12) {
                soundControl(compact: false)
                Text(soundOn ? "EV Sound" : "—")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)

            HStack(alignment: .bottom) {
                tpmsGrid
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(timeString)
                        .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        Text(telemetry.rangeKm.map { "\($0) km" } ?? "— km")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(theme.accent)
                        Text(telemetry.socPercent.map { "\($0)%" } ?? "—")
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 56, height: 4)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(theme.accent)
                                    .frame(width: 56 * CGFloat(telemetry.socPercent ?? 0) / 100.0, height: 4)
                            }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 22)
            // Keep above home indicator — not glued to bottom
            .padding(.bottom, 28)
        }
        .safeAreaPadding(.top, 2)
    }

    private var powerSparkline: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
            Text("\(telemetry.powerKw ?? 0) kW")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .padding(.leading, 8)
        }
        .overlay(alignment: .bottomTrailing) {
            Text("20s")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .offset(y: 14)
        }
    }

    private var tpmsGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([("FL", "FR"), ("RL", "RR")], id: \.0) { row in
                HStack(spacing: 14) {
                    Text("\(row.0)  — psi")
                    Text("\(row.1)  — psi")
                }
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white.opacity(0.45))
    }

    // MARK: - Shared controls

    private func soundControl(compact: Bool) -> some View {
        Button {
            soundOn.toggle()
            toggleSound(soundOn)
        } label: {
            Image(systemName: soundOn ? "speaker.wave.2.fill" : "music.note")
                .font(compact ? .body.weight(.bold) : .title3.weight(.semibold))
                .foregroundStyle(soundOn ? .black : .white)
                .frame(width: compact ? 40 : 48, height: compact ? 40 : 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(soundOn ? theme.accent : Color.white.opacity(0.12))
                )
        }
        .accessibilityLabel("EV Sound")
    }

    private var vinOverlay: some View {
        VStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Vehicle VIN")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button("Close") { showVINEditor = false }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
                HStack(spacing: 10) {
                    TextField("5YJ…", text: $vinDraft)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .padding(12)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    Button {
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
                HStack(spacing: 8) {
                    Button("Bağlan") { Task { await tesla.connectSaved() } }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Button("Yeniden eşleştir") { Task { await tesla.repair() } }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
                Text(telemetry.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                Text("NFC key card on console · data stays on device · not affiliated with Tesla")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 56)
            Spacer()
        }
        .background(Color.black.opacity(0.45).ignoresSafeArea())
    }

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section("Theme") {
                    ForEach(ClusterTheme.allCases) { t in
                        Button {
                            theme = t
                        } label: {
                            HStack {
                                Circle().fill(t.accent).frame(width: 12, height: 12)
                                Text(t.title)
                                Spacer()
                                if t == theme {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(t.accent)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("Audio mix") {
                    Picker("Mix", selection: $mixMode) {
                        Text("Blend").tag("blend")
                        Text("Under").tag("under")
                        Text("Solo").tag("solo")
                    }
                    .onChange(of: mixMode) { _, v in EtubuClusterAudioBridge.setMixMode(v) }
                }
                Section("Vehicle") {
                    Button("Pair / VIN") { showSettings = false; showVINEditor = true }
                    Button("Reconnect Tesla") { Task { await tesla.connectSaved() } }
                    Button("Disconnect Tesla") { Task { await tesla.disconnect() } }
                    Button("Forget vehicle", role: .destructive) {
                        Task { await tesla.clearVehicle() }
                        showVINEditor = true
                    }
                    Button("OBD fallback…") { showObdMenu = true }
                }
            }
            .navigationTitle("ETUBU")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var shouldShowPairGuide: Bool { tesla.pairStep != .none }

    private var pairGuideOverlay: some View {
        VStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tesla Pair Yönergeleri")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("1) Araçta olun, Bluetooth açık olsun.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                Text("2) Uygulama anahtar isteğini gönderiyor…")
                    .font(.subheadline)
                    .foregroundStyle(tesla.pairStep == .sendingRequest ? theme.accent : .white.opacity(0.8))
                Text("3) Tesla anahtar kartını orta konsola dokundurun. Araç ekranında onay çıkınca onaylayın.")
                    .font(.subheadline)
                    .foregroundStyle(tesla.pairStep == .waitingForCard ? theme.accent : .white.opacity(0.8))
                Text(telemetry.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))

                if tesla.pairStep == .waitingForCard {
                    Button {
                        Task { await tesla.confirmCardTapped() }
                    } label: {
                        Text("Kartı dokundum — bağlan")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                HStack(spacing: 8) {
                    Button("Yeniden dene") { Task { await tesla.retryPair() } }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12), in: Capsule())
                    Button("İptal", role: .destructive) { Task { await tesla.disconnect() } }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red.opacity(0.95))
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 80)
            Spacer()
        }
        .background(Color.black.opacity(0.5).ignoresSafeArea())
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
        case .pairing, .waitingForCard: return "Pairing…"
        case .reconnecting: return "Reconnecting…"
        default: return "+ Pair Vehicle"
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
        // Phone battery is not available without UIDevice monitoring entitlement-free:
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level < 0 { return "" }
        return "\(Int(level * 100))"
    }

    private func toggleSound(_ on: Bool) {
        if on {
            EtubuClusterAudioBridge.startDrive(kmh: telemetry.kmh, gear: telemetry.gear, source: telemetry.source.rawValue)
        } else {
            EtubuClusterAudioBridge.endDrive()
        }
    }

    private func startLiveActivityShell() {
        guard #available(iOS 16.2, *) else { return }
        Task {
            EtubuLiveActivityController.ensureAudioSession(mixWithOthers: mixMode != "solo")
            EtubuLiveActivityController.startSilentKeepalive()
            _ = await EtubuLiveActivityController.start(
                voice: "ETUBU",
                kmh: telemetry.kmh,
                gear: telemetry.gear,
                rpm: telemetry.rpm,
                source: telemetry.source == .none ? "idle" : telemetry.source.rawValue
            )
        }
    }
}
