import Foundation
import CryptoKit
import TeslaBLE

/// VIN-scoped Tesla BLE session: pair, connect, poll drive + extended vehicle data, auto-reconnect.
@MainActor
final class EtubuTeslaBleSession: ObservableObject {
    static let shared = EtubuTeslaBleSession()
    
    enum PairFlowStep: Equatable {
        case none
        case sendingRequest
        case waitingForCard
        case connectingAfterCard
        case failed
    }

    private let keyStore = KeychainTeslaKeyStore(service: "com.etubu.app.teslaBLE")
    private var client: TeslaVehicleClient?
    private var pollTask: Task<Void, Never>?
    private var extrasTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var userStopped = false
    private var reconnectAttempt = 0
    private var extrasTick = 0
    /// Consecutive extras polls still missing SoC/climate/TPMS — wake after ~8.
    private var extrasMissingStreak = 0
    private var lastLiveActivityPush = Date.distantPast
    private var lastExtrasWakeAt = Date.distantPast
    private var activePairVIN: String?
    /// Ignore brief BLE disconnect flickers right after a successful connect.
    private var connectedAt: Date?
    private var ignoreDisconnectUntil: Date?
    @Published private(set) var pairStep: PairFlowStep = .none

    private var telemetry: EtubuVehicleTelemetry { .shared }
    /// Demo sürerken BLE poll yazmasın.
    private var demoSuspended = false
    /// Pair / connect spam kilidi.
    private var pairInFlight = false
    /// Uygulama açılışında bir kez otomatik bağlan; sonra yalnızca kullanıcı / demo dönüşü.
    private var didAutoBootstrapThisProcess = false
    private var connectInFlight = false

    private init() {}

    enum BootstrapReason {
        /// Soğuk açılış / onboarding sonrası — process başına bir kez.
        case autoLaunch
        /// Ayarlar / Pair sonrası kullanıcı isteği.
        case userRequested
        /// Demo bitince oturumu geri aç.
        case afterDemo
    }

    func bootstrapIfPossible(reason: BootstrapReason = .autoLaunch) {
        guard !demoSuspended else { return }
        guard let vin = EtubuTeslaVinStore.vin else {
            telemetry.connectionState = .needsVIN
            telemetry.statusMessage = EtubuClusterL10n.t("bleEnterVin")
            return
        }
        telemetry.vin = vin
        telemetry.deviceLabel = "Tesla \(String(vin.suffix(6)))"
        guard EtubuTeslaVinStore.pairedConfirmed(for: vin) else {
            telemetry.connectionState = .needsVIN
            telemetry.statusMessage = EtubuClusterL10n.t("bleOpenPair")
            pairStep = .none
            return
        }
        if reason == .autoLaunch {
            guard !didAutoBootstrapThisProcess else { return }
            didAutoBootstrapThisProcess = true
        }
        // Zaten sağlıklı oturum varsa koparıp yeniden bağlanma.
        if isSessionHealthy {
            if pollTask == nil, let client { startPolling(client) }
            return
        }
        userStopped = false
        Task { await connectNormal(vin: vin) }
    }

    private var isSessionHealthy: Bool {
        guard client != nil, telemetry.connectionState == .connected else { return false }
        guard let last = telemetry.lastUpdateAt else { return false }
        return Date().timeIntervalSince(last) < 8
    }

    /// Demo drive telemetry çakışmasını önlemek için BLE poll'u durdur.
    func suspendForDemo() {
        demoSuspended = true
        cancelJobs()
    }

    func resumeAfterDemo() {
        guard demoSuspended else { return }
        demoSuspended = false
        userStopped = false
        bootstrapIfPossible(reason: .afterDemo)
    }

    func saveVINAndPair(_ raw: String) async {
        guard !pairInFlight else { return }
        switch pairStep {
        case .sendingRequest, .connectingAfterCard: return
        default: break
        }
        let vin = EtubuTeslaVinStore.normalize(raw)
        guard EtubuTeslaVinStore.isValidVIN(vin) else {
            telemetry.statusMessage = EtubuClusterL10n.t("bleVinLen")
            telemetry.connectionState = .failed
            return
        }
        EtubuTeslaVinStore.vin = vin
        EtubuTeslaVinStore.setPairedConfirmed(false, for: vin)
        telemetry.vin = vin
        telemetry.deviceLabel = "Tesla \(String(vin.suffix(6)))"
        userStopped = false
        await pair(vin: vin)
    }

    func connectSaved() async {
        guard let vin = EtubuTeslaVinStore.vin else {
            telemetry.connectionState = .needsVIN
            return
        }
        userStopped = false
        didAutoBootstrapThisProcess = true
        await connectNormal(vin: vin)
    }

    func disconnect() async {
        userStopped = true
        cancelJobs()
        if let client {
            await client.disconnect()
        }
        client = nil
        activePairVIN = nil
        pairStep = .none
        telemetry.connectionState = .idle
        telemetry.statusMessage = EtubuClusterL10n.t("bleDisconnected")
        if telemetry.source == .tesla {
            telemetry.source = .none
        }
    }

    func clearVehicle() async {
        let currentVIN = EtubuTeslaVinStore.vin
        await disconnect()
        if let currentVIN {
            try? keyStore.deletePrivateKey(forVIN: currentVIN)
            EtubuTeslaVinStore.setPairedConfirmed(false, for: currentVIN)
        }
        EtubuTeslaVinStore.vin = nil
        telemetry.vin = ""
        telemetry.connectionState = .needsVIN
        telemetry.statusMessage = EtubuClusterL10n.t("bleEnterVin")
        telemetry.deviceLabel = "Tesla"
        activePairVIN = nil
        pairStep = .none
    }

    func repair() async {
        guard let vin = EtubuTeslaVinStore.vin else {
            telemetry.connectionState = .needsVIN
            telemetry.statusMessage = EtubuClusterL10n.t("bleEnterVin")
            return
        }
        try? keyStore.deletePrivateKey(forVIN: vin)
        EtubuTeslaVinStore.setPairedConfirmed(false, for: vin)
        userStopped = false
        await pair(vin: vin)
    }

    func confirmCardTapped() async {
        guard !pairInFlight else { return }
        guard pairStep == .waitingForCard || pairStep == .failed else { return }
        guard let vin = activePairVIN ?? EtubuTeslaVinStore.vin else {
            telemetry.connectionState = .needsVIN
            telemetry.statusMessage = EtubuClusterL10n.t("bleVinMissing")
            return
        }
        pairInFlight = true
        defer { pairInFlight = false }
        telemetry.connectionState = .connecting
        telemetry.statusMessage = EtubuClusterL10n.t("bleConnectingAfterCard")
        pairStep = .connectingAfterCard
        if let client {
            await client.disconnect()
        }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        guard !demoSuspended else { return }
        await connectNormal(vin: vin, allowPairFallback: false, maxRetries: 3)
    }

    func retryPair() async {
        guard !pairInFlight else { return }
        switch pairStep {
        case .sendingRequest, .connectingAfterCard: return
        default: break
        }
        guard let vin = activePairVIN ?? EtubuTeslaVinStore.vin else {
            telemetry.connectionState = .needsVIN
            telemetry.statusMessage = EtubuClusterL10n.t("bleEnterVin")
            return
        }
        userStopped = false
        await pair(vin: vin)
    }

    // MARK: - Pairing

    private func pair(vin: String) async {
        guard !pairInFlight else { return }
        pairInFlight = true
        defer { pairInFlight = false }
        cancelJobs()
        activePairVIN = vin
        pairStep = .sendingRequest
        telemetry.connectionState = .pairing
        telemetry.statusMessage = EtubuClusterL10n.t("bleSendingKey")

        do {
            let privateKey: P256.KeyAgreement.PrivateKey
            if let existing = try keyStore.loadPrivateKey(forVIN: vin) {
                privateKey = existing
            } else {
                privateKey = KeyPairFactory.generateKeyPair()
                try keyStore.savePrivateKey(privateKey, forVIN: vin)
            }
            let publicKey = KeyPairFactory.publicKeyBytes(of: privateKey)

            let c = TeslaVehicleClient(vin: vin, keyStore: keyStore)
            client = c
            observeState(c)

            try await c.connect(mode: .pairing)
            pairStep = .waitingForCard
            telemetry.connectionState = .waitingForCard
            telemetry.statusMessage = EtubuClusterL10n.t("bleTapCard")

            try await c.send(.security(.addKey(
                publicKey: publicKey,
                role: .owner,
                formFactor: .iosDevice
            )))
            pairStep = .waitingForCard
            telemetry.connectionState = .waitingForCard
            telemetry.statusMessage = EtubuClusterL10n.t("bleTapCardConfirm")
        } catch {
            pairStep = .failed
            telemetry.connectionState = .failed
            telemetry.statusMessage = error.localizedDescription
        }
    }

    // MARK: - Connect + poll

    private func connectNormal(vin: String, allowPairFallback: Bool = true, maxRetries: Int = 1) async {
        guard !demoSuspended else { return }
        if isSessionHealthy {
            if pollTask == nil, let client { startPolling(client) }
            return
        }
        guard !connectInFlight else { return }
        connectInFlight = true
        defer { connectInFlight = false }
        cancelJobs()
        telemetry.connectionState = .connecting
        telemetry.statusMessage = EtubuClusterL10n.t("bleConnecting")

        if (try? keyStore.loadPrivateKey(forVIN: vin)) == nil {
            if allowPairFallback {
                let key = KeyPairFactory.generateKeyPair()
                try? keyStore.savePrivateKey(key, forVIN: vin)
                await pair(vin: vin)
            } else {
                pairStep = .failed
                telemetry.connectionState = .failed
                telemetry.statusMessage = EtubuClusterL10n.t("bleKeyMissing")
            }
            return
        }

        for attempt in 1...max(1, maxRetries) {
            do {
                let c = TeslaVehicleClient(vin: vin, keyStore: keyStore)
                client = c
                observeState(c)
                try await c.connect(mode: .normal)
                // Infotainment uykudaysa SoC/iklim/TPMS boş gelir — uyandır.
                try? await c.send(.security(.wakeVehicle))
                lastExtrasWakeAt = Date()
                try? await Task.sleep(nanoseconds: 700_000_000)
                reconnectAttempt = 0
                connectedAt = Date()
                ignoreDisconnectUntil = Date().addingTimeInterval(5)
                telemetry.connectionState = .connected
                telemetry.lockToTeslaSource()
                telemetry.statusMessage = EtubuClusterL10n.t("bleConnected")
                EtubuVehicleTelemetry.shared.scrubDemoChargeResidueIfNeeded()
                EtubuTeslaVinStore.setPairedConfirmed(true, for: vin)
                activePairVIN = nil
                pairStep = .none
                startPolling(c)
                EtubuVehicleLaunchNotifier.shared.notifyVehicleConnected(source: "tesla")
                return
            } catch {
                if attempt < maxRetries {
                    telemetry.connectionState = .reconnecting
                    telemetry.statusMessage = String(format: EtubuClusterL10n.t("bleRetryFmt"), attempt + 1, maxRetries)
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                    continue
                }
                pairStep = allowPairFallback ? .none : .failed
                telemetry.connectionState = .failed
                telemetry.statusMessage = error.localizedDescription
                // Otomatik yeniden bağlanma yok — yalnızca uygulama açılışı / kullanıcı.
            }
        }
    }

    /// Dual-loop telemetry (see docs/TESLA_BLE_TELEMETRY.md):
    /// - Drive ~10–12 Hz: speed / gear / power only (`fetchDrive`) — never blocked by extras.
    /// - Extras ~0.7–1.5 Hz: charge / climate / TPMS / closures / media — failures never poison drive.
    private func startPolling(_ client: TeslaVehicleClient) {
        pollTask?.cancel()
        extrasTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            var failStreak = 0
            while !Task.isCancelled {
                let suspended = await MainActor.run { self.demoSuspended }
                if suspended { return }
                do {
                    let drive = try await client.fetchDrive(timeout: .milliseconds(1800))
                    failStreak = 0
                    await MainActor.run { self.applyDrive(drive) }
                } catch {
                    failStreak += 1
                    if failStreak < 6 {
                        await MainActor.run {
                            self.telemetry.statusMessage = String(format: EtubuClusterL10n.t("bleWeakSignalFmt"), failStreak)
                        }
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        continue
                    }
                    await MainActor.run {
                        self.telemetry.statusMessage = error.localizedDescription
                        self.telemetry.connectionState = .reconnecting
                    }
                    let vin = await MainActor.run { EtubuTeslaVinStore.vin }
                    let auto = await MainActor.run { self.shouldAutoReconnect }
                    if auto, let vin {
                        await MainActor.run { self.scheduleReconnect(vin: vin, debounce: 1.5) }
                    } else {
                        await MainActor.run { self.telemetry.connectionState = .failed }
                    }
                    return
                }
                // ~10–12 Hz when moving; slower when parked so Infotainment can sleep.
                let sleepNs: UInt64 = await MainActor.run {
                    self.telemetry.kmh < 3 ? 700_000_000 : 85_000_000
                }
                try? await Task.sleep(nanoseconds: sleepNs)
            }
            let auto = await MainActor.run { self.shouldAutoReconnect }
            if auto, let vin = EtubuTeslaVinStore.vin {
                await MainActor.run { self.scheduleReconnect(vin: vin, debounce: 2.0) }
            }
        }
        extrasTask = Task { [weak self] in
            guard let self else { return }
            await self.bootstrapExtras(client)
            while !Task.isCancelled {
                let suspended = await MainActor.run { self.demoSuspended }
                if suspended { return }
                await self.pollExtrasOnce(client)
                let sleepNs: UInt64 = await MainActor.run {
                    let parked = self.telemetry.kmh < 3
                    let missing = self.telemetry.needsVehicleExtrasRefresh
                    if missing { return parked ? 900_000_000 : 650_000_000 }
                    return parked ? 2_200_000_000 : 1_100_000_000
                }
                try? await Task.sleep(nanoseconds: sleepNs)
            }
        }
    }

    /// Boot: tire + charge + climate in parallel, up to 3 retries (closures best-effort).
    private func bootstrapExtras(_ client: TeslaVehicleClient) async {
        for attempt in 1...3 {
            async let tiresTask = try? client.fetch(.categories([.tirePressure]), timeout: .seconds(5))
            async let chargeClimateTask = try? client.fetch(
                .categories([.charge, .climate]),
                timeout: .seconds(6)
            )
            async let closTask: TeslaVehicleSnapshot? = attempt == 1
                ? try? client.fetch(.categories([.closures]), timeout: .seconds(4))
                : nil
            let (tires, chargeClimate, clos) = await (tiresTask, chargeClimateTask, closTask)
            if let tires {
                await MainActor.run { self.applySnapshot(tires) }
            }
            if let chargeClimate {
                await MainActor.run { self.applySnapshot(chargeClimate) }
            }
            if let clos {
                await MainActor.run { self.applySnapshot(clos) }
            }
            let stillMissing = await MainActor.run { self.telemetry.needsVehicleExtrasRefresh }
            if !stillMissing { return }
            if attempt < 3 {
                try? await client.send(.security(.wakeVehicle))
                await MainActor.run { self.lastExtrasWakeAt = Date() }
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 450_000_000)
            }
        }
    }

    private func pollExtrasOnce(_ client: TeslaVehicleClient) async {
        extrasTick += 1
        let tick = extrasTick
        let (parked, missing, staleExtras) = await MainActor.run { () -> (Bool, Bool, Bool) in
            let t = self.telemetry
            let parked = t.kmh < 3
            let missing = t.needsVehicleExtrasRefresh
            let stale: Bool = {
                guard let at = t.lastExtrasAt else { return true }
                return Date().timeIntervalSince(at) > (parked ? 12 : 6)
            }()
            return (parked, missing, stale)
        }

        // Infotainment asleep → empty SoC/climate/TPMS; wake after ~8 missing ticks.
        if missing {
            extrasMissingStreak += 1
            let shouldWake = extrasMissingStreak >= 8 || Date().timeIntervalSince(lastExtrasWakeAt) > 18
            if shouldWake {
                extrasMissingStreak = 0
                await MainActor.run { self.lastExtrasWakeAt = Date() }
                try? await client.send(.security(.wakeVehicle))
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        } else {
            extrasMissingStreak = 0
        }

        // Prefer smaller payloads so one bad category does not block the rest.
        func fetchCats(_ cats: Set<StateCategory>) async {
            do {
                let snap = try await client.fetch(.categories(cats), timeout: .seconds(6))
                await MainActor.run { self.applySnapshot(snap) }
            } catch {
                // Extras never kill the drive loop — try singles on hard miss.
                if missing {
                    for cat in cats {
                        if let one = try? await client.fetch(.categories([cat]), timeout: .seconds(4)) {
                            await MainActor.run { self.applySnapshot(one) }
                        }
                    }
                }
            }
        }

        // Drive: charge + climate + tires every extras tick (not every 2nd).
        // Parked: every other tick once filled, every tick while missing/stale.
        if !parked || missing || staleExtras || tick % 2 == 0 {
            await fetchCats([.charge, .climate, .tirePressure])
        }
        if tick % (parked ? 3 : 2) == 0 {
            await fetchCats([.closures])
        }
        if tick % (parked ? 8 : 5) == 0 {
            await fetchCats([.media, .mediaDetail])
        }
    }

    private func applyDrive(_ drive: DriveState) {
        guard !demoSuspended else { return }
        let mph = drive.speedMph ?? 0
        // Bozuk / imkansız paket — yayınlama (ama oturum sağlığını taze tut).
        guard mph.isFinite, mph >= 0, mph <= 175 else {
            telemetry.touchDriveHealth()
            return
        }
        // Prefer nearest km/h; float mph → km/h without coarse banding.
        let kmh = max(0, Int((mph * 1.60934).rounded()))
        let gear: String = {
            switch drive.shiftState {
            case .park: return "P"
            case .reverse: return "R"
            case .neutral: return "N"
            case .drive: return "D"
            case .none:
                // Unset shift + hareket → stuck "P" park-gate hızı sıfırlamasın.
                if kmh >= 3 { return "D" }
                return telemetry.gear
            }
        }()
        let odoKm: Int? = {
            guard let hundredths = drive.odometerHundredthsMile, hundredths > 0 else { return nil }
            let miles = Double(hundredths) / 100.0
            guard miles.isFinite, miles > 0, miles < 2_000_000 else { return nil }
            return Int((miles * 1.60934).rounded())
        }()
        let remainKm: Double? = {
            guard let mi = drive.activeRouteMilesToArrival, mi.isFinite, mi >= 0, mi < 12_000 else { return nil }
            return mi * 1.60934
        }()
        let power: Int? = {
            guard let kw = drive.powerKW else { return telemetry.powerKw }
            // Aşırı gürültü paketini yutma; önceki gücü koru.
            if abs(kw) > 800 { return telemetry.powerKw }
            return kw
        }()
        telemetry.applyTeslaDrive(
            kmh: kmh,
            gear: gear,
            powerKw: power,
            odometerKm: odoKm,
            navDestination: drive.activeRouteDestination,
            navRemainKm: remainKm,
            navEtaMinutes: drive.activeRouteMinutesToArrival
        )
        // EV ses — kullanıcı açtıysa Tesla’da da demo gibi motoru ayakta tut.
        if EtubuClusterAudioBridge.isSoundWanted {
            EtubuClusterAudioBridge.ensureLiveDriveSound(
                kmh: telemetry.kmh,
                powerKw: telemetry.powerKw,
                gear: telemetry.gear
            )
        } else {
            EtubuClusterAudioBridge.pushDrive(
                kmh: telemetry.kmh,
                powerKw: telemetry.powerKw,
                source: "tesla"
            )
        }
        AppDelegate.activateDriveAudioSession()
        // Araç navigasyonu → uygulama rotası + uyarı hattı (arka planda).
        EtubuRouteBridge.adaptVehicleNavIfNeeded(
            destination: drive.activeRouteDestination,
            remainKm: remainKm,
            etaMinutes: drive.activeRouteMinutesToArrival
        )
        // Live Activity: max ~2 Hz so faster drive poll doesn't spam
        if Date().timeIntervalSince(lastLiveActivityPush) >= 0.5 {
            lastLiveActivityPush = Date()
            pushLiveActivity()
        }
    }

    private func applySnapshot(_ snap: TeslaVehicleSnapshot) {
        if let charge = snap.charge {
            // SPM VehicleSnapshotMapper maps unset optionals → 0 (not nil). Treat protocol zeros carefully.
            let rangeKm: Int? = {
                let mi = charge.estBatteryRangeMiles ?? charge.batteryRangeMiles
                guard let mi, mi.isFinite, mi > 0.5, mi < 800 else { return nil }
                return Int((mi * 1.60934).rounded())
            }()
            let charging = charge.chargingStatus == .charging || charge.chargingStatus == .starting
            let soc: Int? = {
                guard let bl = charge.batteryLevel else { return nil }
                // Unset-as-0 from mapper: only accept 0% with charge/range proof.
                if bl < 0 || bl > 100 { return nil }
                if bl > 0 { return bl }
                if charging { return 0 }
                if rangeKm != nil { return 0 }
                return nil
            }()
            let limit: Int? = {
                guard let lim = charge.chargeLimitPercent, (50...100).contains(lim) else { return nil }
                return lim
            }()
            telemetry.applyTeslaCharge(
                soc: soc,
                rangeKm: rangeKm,
                chargeKw: charge.chargerPower.flatMap { $0 == 0 && !charging ? nil : $0 },
                charging: charging,
                limitPercent: limit,
                amps: charge.chargerCurrent.flatMap { $0 == 0 && !charging ? nil : $0 },
                volts: charge.chargerVoltage.flatMap { $0 == 0 && !charging ? nil : $0 },
                minutesToFull: charge.minutesToFullCharge.flatMap { $0 > 0 ? $0 : nil },
                portOpen: charge.chargePortOpen
            )
        }
        if let climate = snap.climate {
            // If one side is exact 0°C and the other is a real temp, keep the 0 (don't nil both).
            let out = Self.sanitizeTempC(climate.outsideTempCelsius, other: climate.insideTempCelsius)
            let inn = Self.sanitizeTempC(climate.insideTempCelsius, other: climate.outsideTempCelsius)
            if out != nil || inn != nil || climate.isClimateOn != nil {
                telemetry.applyTeslaClimate(
                    outsideC: out,
                    insideC: inn,
                    climateOn: climate.isClimateOn
                )
            }
        }
        if let tires = snap.tirePressure {
            func reading(_ t: TirePressureState.Tire?) -> EtubuTireReading {
                let psi = EtubuVehicleTelemetry.tireRawToPsi(t?.pressureBar)
                return EtubuTireReading(
                    psi: psi,
                    warning: t?.hasWarning == true
                )
            }
            telemetry.applyTeslaTPMS(
                fl: reading(tires.frontLeft),
                fr: reading(tires.frontRight),
                rl: reading(tires.rearLeft),
                rr: reading(tires.rearRight)
            )
        }
        if let c = snap.closures {
            telemetry.applyTeslaClosures(
                locked: c.locked,
                fl: c.frontDriverDoor,
                fr: c.frontPassengerDoor,
                rl: c.rearDriverDoor,
                rr: c.rearPassengerDoor,
                frunk: c.frontTrunk,
                trunk: c.rearTrunk,
                sentry: c.sentryModeActive,
                valet: c.valetMode,
                present: c.isUserPresent
            )
        }
        if snap.media != nil || snap.mediaDetail != nil {
            telemetry.applyTeslaMedia(
                title: snap.media?.nowPlayingTitle,
                artist: snap.media?.nowPlayingArtist,
                album: snap.mediaDetail?.nowPlayingAlbum,
                sourceName: snap.mediaDetail?.nowPlayingSource ?? snap.mediaDetail?.a2dpSourceName
            )
        }
    }

    private func observeState(_ client: TeslaVehicleClient) {
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            for await state in client.stateStream {
                await MainActor.run {
                    guard let self, !self.demoSuspended else { return }
                    switch state {
                    case .scanning:
                        self.telemetry.connectionState = .connecting
                        self.telemetry.statusMessage = EtubuClusterL10n.t("bleScanning")
                    case .connecting, .handshaking:
                        self.telemetry.connectionState = .connecting
                        self.telemetry.statusMessage = EtubuClusterL10n.t("bleHandshaking")
                    case .connected:
                        self.connectedAt = Date()
                        self.ignoreDisconnectUntil = Date().addingTimeInterval(4)
                        self.telemetry.connectionState = .connected
                        self.telemetry.lockToTeslaSource()
                        self.telemetry.statusMessage = EtubuClusterL10n.t("bleConnectedReadOnly")
                        EtubuVehicleLaunchNotifier.shared.notifyVehicleConnected(source: "tesla")
                    case .disconnected:
                        if !self.userStopped {
                            if self.pairStep == .waitingForCard {
                                self.telemetry.connectionState = .waitingForCard
                            } else if let until = self.ignoreDisconnectUntil, Date() < until {
                                break
                            } else if let last = self.telemetry.lastUpdateAt,
                                      Date().timeIntervalSince(last) < 4 {
                                break
                            } else if self.shouldAutoReconnect, let vin = EtubuTeslaVinStore.vin {
                                self.telemetry.connectionState = .reconnecting
                                self.telemetry.statusMessage = EtubuClusterL10n.t("bleReconnecting")
                                self.scheduleReconnect(vin: vin, debounce: 2.0)
                            } else {
                                self.telemetry.connectionState = .idle
                                self.telemetry.statusMessage = EtubuClusterL10n.t("bleDisconnected")
                            }
                        }
                    @unknown default:
                        break
                    }
                }
            }
        }
    }

    /// Sürüş / aktif rota / taze Tesla oturumu varken kopunca yeniden dene; uzun parkta sessiz.
    private var shouldAutoReconnect: Bool {
        guard !userStopped, !demoSuspended else { return false }
        guard EtubuTeslaVinStore.vin != nil else { return false }
        let t = telemetry
        if t.kmh >= 3 || t.routeActive { return true }
        // Park-gate veya geçici 0 hız olsa bile son drive paketi yeniyse toparla.
        if t.source == .tesla,
           let last = t.lastDriveAt,
           Date().timeIntervalSince(last) < 90 {
            return true
        }
        return false
    }

    private func scheduleReconnect(vin: String, debounce: TimeInterval = 0) {
        guard shouldAutoReconnect else { return }
        guard EtubuTeslaVinStore.pairedConfirmed(for: vin) else { return }
        if isSessionHealthy { return }
        guard reconnectAttempt < 4 else {
            telemetry.connectionState = .failed
            telemetry.statusMessage = EtubuClusterL10n.t("bleConnectFailed")
            return
        }
        reconnectTask?.cancel()
        reconnectAttempt += 1
        let delay = max(debounce, min(8.0, pow(2.0, Double(min(reconnectAttempt, 4) - 1))))
        telemetry.connectionState = .reconnecting
        telemetry.statusMessage = String(format: EtubuClusterL10n.t("bleReconnectInFmt"), Int(delay))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !self.userStopped, !self.demoSuspended else { return }
            guard self.shouldAutoReconnect else {
                await MainActor.run {
                    self.telemetry.connectionState = .idle
                    self.telemetry.statusMessage = EtubuClusterL10n.t("bleDisconnected")
                }
                return
            }
            if self.isSessionHealthy { return }
            await self.connectNormal(vin: vin, allowPairFallback: false, maxRetries: 2)
        }
    }

    /// SPM Climate mapper unset optional → 0.0; gerçek 0°C ile karıştırma.
    /// Exact ~0 alone (both sides unset) → nil; if the other side is a real temp, keep 0°C.
    private static func sanitizeTempC(_ value: Double?, other: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        if value < -50 || value > 70 { return nil }
        if abs(value) < 0.05 {
            let otherValid = other.map {
                $0.isFinite && abs($0) >= 0.05 && $0 >= -50 && $0 <= 70
            } ?? false
            return otherValid ? 0 : nil
        }
        return value
    }

    private func cancelJobs() {
        pollTask?.cancel()
        extrasTask?.cancel()
        stateTask?.cancel()
        reconnectTask?.cancel()
        pollTask = nil
        extrasTask = nil
        stateTask = nil
        reconnectTask = nil
    }

    private func pushLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        let t = telemetry
        Task {
            EtubuLiveActivityController.ensureAudioSession(mixWithOthers: true)
            await EtubuLiveActivityController.update(
                kmh: t.kmh,
                gear: t.gear,
                rpm: t.rpm,
                voice: "ETUBU",
                source: "tesla"
            )
        }
    }

    // MARK: - Remote commands (BLE write)

    struct NearbyChargerSite: Identifiable, Equatable {
        var id: String
        var name: String
        var distanceKm: Double
        var available: Int
        var total: Int
        var maxPowerKw: Int

        var subtitle: String {
            let dist = String(format: "%.1f km", distanceKm)
            let stalls = total > 0 ? "\(available)/\(total)" : "—"
            let kw = maxPowerKw > 0 ? " · \(maxPowerKw) kW" : ""
            return "\(dist) · \(stalls)\(kw)"
        }
    }

    @Published var lastCommandMessage: String = ""
    @Published var nearbyChargers: [NearbyChargerSite] = []

    func setClimate(on: Bool) async {
        await sendCommand(
            .climate(on ? .on : .off),
            label: EtubuClusterL10n.t(on ? "cmdOkClimateOn" : "cmdOkClimateOff")
        )
    }

    func setChargeLimit(_ percent: Int) async {
        let p = Int32(min(100, max(50, percent)))
        await sendCommand(
            .charge(.setLimit(percent: p)),
            label: String(format: EtubuClusterL10n.t("cmdOkChargeLimitFmt"), Int(p))
        )
    }

    func setCharging(start: Bool) async {
        await sendCommand(
            .charge(start ? .start : .stop),
            label: EtubuClusterL10n.t(start ? "cmdOkChargeStart" : "cmdOkChargeStop")
        )
    }

    func setLocked(_ lock: Bool) async {
        await sendCommand(
            .security(lock ? .lock : .unlock),
            label: EtubuClusterL10n.t(lock ? "cmdOkLocked" : "cmdOkUnlocked")
        )
    }

    func setSeatHeater(level: Command.Climate.SeatHeaterLevel, seat: Command.Climate.SeatPosition) async {
        let label: String
        switch level {
        case .off: label = EtubuClusterL10n.t("cmdOkSeatOff")
        case .low: label = EtubuClusterL10n.t("cmdOkSeat1")
        case .medium: label = EtubuClusterL10n.t("cmdOkSeat2")
        case .high: label = EtubuClusterL10n.t("cmdOkSeat3")
        }
        await sendCommand(.climate(.setSeatHeater(level: level, seat: seat)), label: label)
    }

    func ventWindows() async {
        await sendCommand(.actions(.ventWindows), label: EtubuClusterL10n.t("cmdOkVent"))
    }

    func closeWindows() async {
        await sendCommand(.actions(.closeWindows), label: EtubuClusterL10n.t("cmdOkCloseWindows"))
    }

    func openFrunk() async {
        await sendCommand(.security(.openFrunk), label: EtubuClusterL10n.t("cmdOkFrunk"))
    }

    /// Frunk BLE’de yalnızca açma var — açıksa bilgilendir.
    func toggleFrunk() async {
        if telemetry.frunkOpen == true {
            lastCommandMessage = EtubuClusterL10n.t("cmdFrunkManualClose")
            telemetry.statusMessage = lastCommandMessage
            return
        }
        await openFrunk()
        await refreshClosuresSoon()
    }

    func openTrunk() async {
        await sendCommand(.security(.openTrunk), label: EtubuClusterL10n.t("cmdOkTrunk"))
    }

    func closeTrunk() async {
        await sendCommand(.security(.closeTrunk), label: EtubuClusterL10n.t("cmdOkTrunkClose"))
    }

    /// Aynı tuş: açıksa kapat, kapalıysa aç (powered liftgate / actuate).
    func toggleTrunk() async {
        if telemetry.trunkOpen == true {
            await sendCommand(.security(.closeTrunk), label: EtubuClusterL10n.t("cmdOkTrunkClose"))
        } else {
            // actuateTrunk = smart open/close; openTrunk yedek
            await sendCommand(.security(.actuateTrunk), label: EtubuClusterL10n.t("cmdOkTrunk"))
        }
        await refreshClosuresSoon()
    }

    func openChargePort() async {
        await sendCommand(.charge(.openPort), label: EtubuClusterL10n.t("cmdOkChargePort"))
    }

    func closeChargePort() async {
        await sendCommand(.charge(.closePort), label: EtubuClusterL10n.t("cmdOkChargePortClose"))
    }

    func toggleChargePort() async {
        if telemetry.chargePortOpen == true {
            await closeChargePort()
        } else {
            await openChargePort()
        }
        await refreshClosuresSoon()
    }

    func flashLights() async {
        await sendCommand(.actions(.flashLights), label: EtubuClusterL10n.t("cmdOkFlash"))
    }

    private func refreshClosuresSoon() async {
        guard let client else { return }
        try? await Task.sleep(nanoseconds: 450_000_000)
        if let snap = try? await client.fetch(.categories([.closures, .charge])) {
            await MainActor.run { applySnapshot(snap) }
        }
    }

    func refreshNearbyChargers() async {
        guard let client else {
            lastCommandMessage = EtubuClusterL10n.t("vehicleNotConnected")
            return
        }
        do {
            let result = try await client.query(.nearbyCharging(includeMetadata: true, radiusMiles: 50, count: 8))
            if case .nearbyCharging(let sites) = result {
                nearbyChargers = sites.superchargers
                    .filter { !$0.siteClosed && !$0.name.isEmpty }
                    .sorted { $0.distanceMiles < $1.distanceMiles }
                    .prefix(8)
                    .map { s in
                        NearbyChargerSite(
                            id: "\(s.id)-\(s.name)",
                            name: s.name,
                            distanceKm: Double(s.distanceMiles) * 1.60934,
                            available: Int(s.availableStalls),
                            total: Int(s.totalStalls),
                            maxPowerKw: Int(s.maxPowerKw)
                        )
                    }
                lastCommandMessage = nearbyChargers.isEmpty
                    ? EtubuClusterL10n.t("noNearbySuperchargers")
                    : String(format: EtubuClusterL10n.t("superchargerCountFmt"), nearbyChargers.count)
                NotificationCenter.default.post(name: .etubuCarPlayNeedsRefresh, object: nil)
            }
        } catch {
            lastCommandMessage = String(
                format: EtubuClusterL10n.t("chargeSearchFailedFmt"),
                error.localizedDescription
            )
        }
    }

    private func sendCommand(_ command: Command, label: String) async {
        guard let client else {
            lastCommandMessage = EtubuClusterL10n.t("vehicleNotConnected")
            telemetry.statusMessage = lastCommandMessage
            return
        }
        do {
            try await client.send(command)
            lastCommandMessage = label
            telemetry.statusMessage = label
        } catch {
            lastCommandMessage = String(
                format: EtubuClusterL10n.t("commandFailedFmt"),
                error.localizedDescription
            )
            telemetry.statusMessage = lastCommandMessage
        }
    }
}
