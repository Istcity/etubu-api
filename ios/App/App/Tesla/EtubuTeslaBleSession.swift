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
    private var stateTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var userStopped = false
    private var reconnectAttempt = 0
    private var tick = 0
    private var lastLiveActivityPush = Date.distantPast
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
            telemetry.statusMessage = "VIN girin ve eşleştirin"
            return
        }
        telemetry.vin = vin
        telemetry.deviceLabel = "Tesla \(String(vin.suffix(6)))"
        guard EtubuTeslaVinStore.pairedConfirmed(for: vin) else {
            telemetry.connectionState = .needsVIN
            telemetry.statusMessage = "Eşleştirmeyi tamamlamak için Pair açın"
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
            telemetry.statusMessage = "VIN must be 17 characters"
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
        telemetry.statusMessage = "Disconnected"
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
        telemetry.statusMessage = "VIN girin ve eşleştirin"
        telemetry.deviceLabel = "Tesla"
        activePairVIN = nil
        pairStep = .none
    }

    func repair() async {
        guard let vin = EtubuTeslaVinStore.vin else {
            telemetry.connectionState = .needsVIN
            telemetry.statusMessage = "VIN girin ve eşleştirin"
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
            telemetry.statusMessage = "VIN bulunamadı"
            return
        }
        pairInFlight = true
        defer { pairInFlight = false }
        telemetry.connectionState = .connecting
        telemetry.statusMessage = "Kart doğrulaması sonrası bağlanıyor…"
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
            telemetry.statusMessage = "VIN girin ve eşleştirin"
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
        telemetry.statusMessage = "Anahtar isteği Bluetooth üzerinden gönderiliyor…"

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
            telemetry.statusMessage = "Tesla anahtar kartını orta konsola dokundurun"

            try await c.send(.security(.addKey(
                publicKey: publicKey,
                role: .owner,
                formFactor: .iosDevice
            )))
            pairStep = .waitingForCard
            telemetry.connectionState = .waitingForCard
            telemetry.statusMessage = "Kartı dokundurup araç ekranındaki onayı verin, sonra \"Kartı dokundum — bağlan\"a basın"
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
        telemetry.statusMessage = "Bağlanıyor…"

        if (try? keyStore.loadPrivateKey(forVIN: vin)) == nil {
            if allowPairFallback {
                let key = KeyPairFactory.generateKeyPair()
                try? keyStore.savePrivateKey(key, forVIN: vin)
                await pair(vin: vin)
            } else {
                pairStep = .failed
                telemetry.connectionState = .failed
                telemetry.statusMessage = "Kayıtlı anahtar bulunamadı, yeniden eşleştirin"
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
                try? await Task.sleep(nanoseconds: 700_000_000)
                reconnectAttempt = 0
                connectedAt = Date()
                ignoreDisconnectUntil = Date().addingTimeInterval(5)
                telemetry.connectionState = .connected
                telemetry.source = .tesla
                telemetry.statusMessage = "Bağlandı"
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
                    telemetry.statusMessage = "Bağlantı tekrar deneniyor (\(attempt + 1)/\(maxRetries))…"
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

    private func startPolling(_ client: TeslaVehicleClient) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            var failStreak = 0
            // İlk bağlanmada iklim / enerji / lastik hemen gelsin
            do {
                let boot = try await client.fetch(.categories([.charge, .climate, .tirePressure]))
                await MainActor.run { self.applySnapshot(boot) }
            } catch {
                // Kombine istek başarısızsa lastiği ayrı dene
                if let tiresOnly = try? await client.fetch(.categories([.tirePressure])) {
                    await MainActor.run { self.applySnapshot(tiresOnly) }
                }
                if let chargeOnly = try? await client.fetch(.categories([.charge, .climate])) {
                    await MainActor.run { self.applySnapshot(chargeOnly) }
                }
            }
            // Lastik yoksa bir kez daha zorla
            let missingTires = await MainActor.run {
                self.telemetry.tpmsFL.psi == nil
                    && self.telemetry.tpmsFR.psi == nil
                    && self.telemetry.tpmsRL.psi == nil
                    && self.telemetry.tpmsRR.psi == nil
            }
            if missingTires, let tires = try? await client.fetch(.categories([.tirePressure])) {
                await MainActor.run { self.applySnapshot(tires) }
            }
            while !Task.isCancelled {
                let suspended = await MainActor.run { self.demoSuspended }
                if suspended { return }
                do {
                    // Drive first + apply immediately — speed/gear/power never wait on extras
                    let drive = try await client.fetchDrive()
                    failStreak = 0
                    await MainActor.run { self.applyDrive(drive) }

                    self.tick += 1
                    let parked = await MainActor.run { self.telemetry.kmh < 3 }
                    let missingExtras = await MainActor.run {
                        self.telemetry.socPercent == nil
                            || self.telemetry.outsideC == nil
                            || self.telemetry.insideC == nil
                            || (self.telemetry.tpmsFL.psi == nil
                                && self.telemetry.tpmsFR.psi == nil
                                && self.telemetry.tpmsRL.psi == nil
                                && self.telemetry.tpmsRR.psi == nil)
                    }

                    // Eksik SoC/iklim/TPMS varken her döngüde zorla; yoksa seyrek tut.
                    if missingExtras || self.tick % (parked ? 2 : 2) == 0 {
                        let snap = try await client.fetch(.categories([.charge, .climate, .tirePressure]))
                        await MainActor.run { self.applySnapshot(snap) }
                    } else if self.tick % (parked ? 5 : 4) == 0 {
                        let snap = try await client.fetch(.categories([.tirePressure]))
                        await MainActor.run { self.applySnapshot(snap) }
                    } else if self.tick % (parked ? 12 : 9) == 0 {
                        let snap = try await client.fetch(.categories([.closures]))
                        await MainActor.run { self.applySnapshot(snap) }
                    } else if self.tick % (parked ? 10 : 7) == 0 {
                        let snap = try await client.fetch(.categories([.media, .mediaDetail]))
                        await MainActor.run { self.applySnapshot(snap) }
                    }
                } catch {
                    failStreak += 1
                    if failStreak < 5 {
                        await MainActor.run {
                            self.telemetry.statusMessage = "Sinyal zayıf… (\(failStreak)/5)"
                        }
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        continue
                    }
                    await MainActor.run {
                        self.telemetry.statusMessage = error.localizedDescription
                        self.telemetry.connectionState = .failed
                    }
                    // Poll öldü — otomatik reconnect yok (yalnızca açılış / kullanıcı).
                    return
                }
                // Moving: ~2 Hz drive; parked: ~0.8 Hz — critical cluster data stays snappy
                let sleepNs: UInt64 = await MainActor.run {
                    self.telemetry.kmh < 3 ? 1_200_000_000 : 450_000_000
                }
                try? await Task.sleep(nanoseconds: sleepNs)
            }
            // Oturum düştüyse otomatik yeniden bağlanma yok.
        }
    }

    private func applyDrive(_ drive: DriveState) {
        guard !demoSuspended else { return }
        let mph = drive.speedMph ?? 0
        let kmh = Int((mph * 1.60934).rounded())
        let gear: String = {
            switch drive.shiftState {
            case .park: return "P"
            case .reverse: return "R"
            case .neutral: return "N"
            case .drive: return "D"
            case .none: return telemetry.gear
            }
        }()
        let odoKm: Int? = {
            guard let hundredths = drive.odometerHundredthsMile else { return nil }
            let miles = Double(hundredths) / 100.0
            return Int((miles * 1.60934).rounded())
        }()
        let remainKm: Double? = {
            guard let mi = drive.activeRouteMilesToArrival else { return nil }
            return mi * 1.60934
        }()
        telemetry.applyTeslaDrive(
            kmh: kmh,
            gear: gear,
            powerKw: drive.powerKW,
            odometerKm: odoKm,
            navDestination: drive.activeRouteDestination,
            navRemainKm: remainKm,
            navEtaMinutes: drive.activeRouteMinutesToArrival
        )
        EtubuClusterAudioBridge.pushDrive(
            kmh: kmh,
            powerKw: drive.powerKW,
            source: "tesla"
        )
        AppDelegate.activateDriveAudioSession()
        // Live Activity: max ~2 Hz so faster drive poll doesn't spam
        if Date().timeIntervalSince(lastLiveActivityPush) >= 0.5 {
            lastLiveActivityPush = Date()
            pushLiveActivity()
        }
    }

    private func applySnapshot(_ snap: TeslaVehicleSnapshot) {
        if let charge = snap.charge {
            let rangeKm: Int? = {
                if let mi = charge.estBatteryRangeMiles ?? charge.batteryRangeMiles, mi > 0.5 {
                    return Int((mi * 1.60934).rounded())
                }
                return nil
            }()
            let charging = charge.chargingStatus == .charging || charge.chargingStatus == .starting
            // SPM mapper unset optional → 0; gerçek 0% yalnızca şarj/menzil kanıtı varsa.
            let soc: Int? = {
                guard let bl = charge.batteryLevel else { return nil }
                if bl > 0 { return min(100, bl) }
                if charging { return 0 }
                if rangeKm != nil { return 0 }
                return nil
            }()
            telemetry.applyTeslaCharge(
                soc: soc,
                rangeKm: rangeKm,
                chargeKw: charge.chargerPower.flatMap { $0 == 0 && !charging ? nil : $0 },
                charging: charging,
                limitPercent: charge.chargeLimitPercent.flatMap { $0 > 0 ? $0 : nil },
                amps: charge.chargerCurrent.flatMap { $0 == 0 && !charging ? nil : $0 },
                volts: charge.chargerVoltage.flatMap { $0 == 0 && !charging ? nil : $0 },
                minutesToFull: charge.minutesToFullCharge.flatMap { $0 > 0 ? $0 : nil },
                portOpen: charge.chargePortOpen
            )
        }
        if let climate = snap.climate {
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
                // Tesla reports bar; if value looks like psi already (> 8), keep as-is.
                let raw = t?.pressureBar
                let psi: Double? = {
                    guard let raw, raw > 0.2 else { return nil }
                    if raw > 8 { return raw }
                    return EtubuVehicleTelemetry.barToPsi(raw)
                }()
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
                        self.telemetry.statusMessage = "Scanning…"
                    case .connecting, .handshaking:
                        self.telemetry.connectionState = .connecting
                        self.telemetry.statusMessage = "Handshaking…"
                    case .connected:
                        self.connectedAt = Date()
                        self.ignoreDisconnectUntil = Date().addingTimeInterval(4)
                        self.telemetry.connectionState = .connected
                        self.telemetry.statusMessage = "Bağlandı · salt okuma"
                        EtubuVehicleLaunchNotifier.shared.notifyVehicleConnected(source: "tesla")
                    case .disconnected:
                        if !self.userStopped {
                            if self.pairStep == .waitingForCard {
                                self.telemetry.connectionState = .waitingForCard
                            } else if let until = self.ignoreDisconnectUntil, Date() < until {
                                // Bağlantı sonrası kısa flicker — yok say, oturumu bozma
                                break
                            } else if let last = self.telemetry.lastUpdateAt,
                                      Date().timeIntervalSince(last) < 4 {
                                // Poll hâlâ veri alıyor — sahte disconnect
                                break
                            } else {
                                // Otomatik yeniden bağlanma yok — kullanıcı Ayarlar’dan bağlar.
                                self.telemetry.connectionState = .idle
                                self.telemetry.statusMessage = "Bağlantı kesildi"
                            }
                        }
                    @unknown default:
                        break
                    }
                }
            }
        }
    }

    private func scheduleReconnect(vin: String, debounce: TimeInterval = 0) {
        // Kullanıcı isteği: otomatik yeniden bağlanma yok (yalnızca uygulama açılışı).
        _ = vin
        _ = debounce
    }

    /// SPM Charge/Climate mapper unset optional → 0; her iki temp de ~0 ise yok say.
    private static func sanitizeTempC(_ value: Double?, other: Double?) -> Double? {
        guard let value else { return nil }
        let otherZ = other.map { abs($0) < 0.05 } ?? true
        if abs(value) < 0.05, otherZ { return nil }
        // Tesla kabin/dış için mantıklı aralık dışı → yok say
        if value < -50 || value > 70 { return nil }
        return value
    }

    private func cancelJobs() {
        pollTask?.cancel()
        stateTask?.cancel()
        reconnectTask?.cancel()
        pollTask = nil
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

    @Published var lastCommandMessage: String = ""

    func setClimate(on: Bool) async {
        await sendCommand(.climate(on ? .on : .off), label: on ? "İklim açıldı" : "İklim kapandı")
    }

    func setChargeLimit(_ percent: Int) async {
        let p = Int32(min(100, max(50, percent)))
        await sendCommand(.charge(.setLimit(percent: p)), label: "Şarj limiti \(p)%")
    }

    func setCharging(start: Bool) async {
        await sendCommand(.charge(start ? .start : .stop), label: start ? "Şarj başladı" : "Şarj durdu")
    }

    func setLocked(_ lock: Bool) async {
        await sendCommand(.security(lock ? .lock : .unlock), label: lock ? "Kilitlendi" : "Kilit açıldı")
    }

    private func sendCommand(_ command: Command, label: String) async {
        guard let client else {
            lastCommandMessage = "Araç bağlı değil"
            telemetry.statusMessage = lastCommandMessage
            return
        }
        do {
            try await client.send(command)
            lastCommandMessage = label
            telemetry.statusMessage = label
        } catch {
            lastCommandMessage = "Komut başarısız: \(error.localizedDescription)"
            telemetry.statusMessage = lastCommandMessage
        }
    }
}
