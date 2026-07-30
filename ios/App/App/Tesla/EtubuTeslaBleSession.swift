import Foundation
import CryptoKit
import TeslaBLE

/// VIN-scoped Tesla BLE session: pair, connect, poll drive + extended vehicle data, auto-reconnect.
@MainActor
final class EtubuTeslaBleSession: ObservableObject {
    static let shared = EtubuTeslaBleSession()

    private let keyStore = KeychainTeslaKeyStore(service: "com.etubu.app.teslaBLE")
    private var client: TeslaVehicleClient?
    private var pollTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var userStopped = false
    private var reconnectAttempt = 0
    private var tick = 0
    private var activePairVIN: String?

    private var telemetry: EtubuVehicleTelemetry { .shared }

    private init() {}

    func bootstrapIfPossible() {
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
            return
        }
        userStopped = false
        Task { await connectNormal(vin: vin) }
    }

    func saveVINAndPair(_ raw: String) async {
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
        await connectNormal(vin: vin)
    }

    func disconnect() async {
        userStopped = true
        cancelJobs()
        if let client {
            await client.disconnect()
        }
        client = nil
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
        guard let vin = activePairVIN ?? EtubuTeslaVinStore.vin else {
            telemetry.connectionState = .needsVIN
            telemetry.statusMessage = "VIN bulunamadı"
            return
        }
        telemetry.connectionState = .connecting
        telemetry.statusMessage = "Kart doğrulaması sonrası bağlanıyor…"
        if let client {
            await client.disconnect()
        }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        await connectNormal(vin: vin, allowPairFallback: false, maxRetries: 3)
    }

    func retryPair() async {
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
        cancelJobs()
        activePairVIN = vin
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
            telemetry.connectionState = .waitingForCard
            telemetry.statusMessage = "Tesla anahtar kartını orta konsola dokundurun"

            try await c.send(.security(.addKey(
                publicKey: publicKey,
                role: .owner,
                formFactor: .iosDevice
            )))
            telemetry.connectionState = .waitingForCard
            telemetry.statusMessage = "Kartı dokundurup araç ekranındaki onayı verin, sonra \"Kartı dokundum — bağlan\"a basın"
        } catch {
            telemetry.connectionState = .failed
            telemetry.statusMessage = error.localizedDescription
        }
    }

    // MARK: - Connect + poll

    private func connectNormal(vin: String, allowPairFallback: Bool = true, maxRetries: Int = 1) async {
        cancelJobs()
        telemetry.connectionState = .connecting
        telemetry.statusMessage = "Connecting…"

        if (try? keyStore.loadPrivateKey(forVIN: vin)) == nil {
            if allowPairFallback {
                let key = KeyPairFactory.generateKeyPair()
                try? keyStore.savePrivateKey(key, forVIN: vin)
                await pair(vin: vin)
            } else {
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
                reconnectAttempt = 0
                telemetry.connectionState = .connected
                telemetry.source = .tesla
                telemetry.statusMessage = "Bağlandı"
                EtubuTeslaVinStore.setPairedConfirmed(true, for: vin)
                activePairVIN = nil
                startPolling(c)
                return
            } catch {
                if attempt < maxRetries {
                    telemetry.connectionState = .reconnecting
                    telemetry.statusMessage = "Bağlantı tekrar deneniyor (\(attempt + 1)/\(maxRetries))…"
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                    continue
                }
                telemetry.connectionState = .failed
                telemetry.statusMessage = error.localizedDescription
                scheduleReconnect(vin: vin)
            }
        }
    }

    private func startPolling(_ client: TeslaVehicleClient) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let drive = try await client.fetchDrive()
                    await MainActor.run { self.applyDrive(drive) }

                    self.tick += 1
                    // Rotate extended categories to keep BLE payload light
                    if self.tick % 3 == 0 {
                        let snap = try await client.fetch(.categories([.charge, .climate]))
                        await MainActor.run { self.applySnapshot(snap) }
                    }
                    if self.tick % 5 == 0 {
                        let snap = try await client.fetch(.categories([.tirePressure]))
                        await MainActor.run { self.applySnapshot(snap) }
                    }
                    if self.tick % 7 == 0 {
                        let snap = try await client.fetch(.categories([.closures]))
                        await MainActor.run { self.applySnapshot(snap) }
                    }
                    if self.tick % 4 == 0 {
                        let snap = try await client.fetch(.categories([.media, .mediaDetail]))
                        await MainActor.run { self.applySnapshot(snap) }
                    }
                } catch {
                    await MainActor.run {
                        self.telemetry.statusMessage = error.localizedDescription
                        self.telemetry.connectionState = .reconnecting
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
            }
            if !self.userStopped, let vin = EtubuTeslaVinStore.vin {
                await MainActor.run { self.scheduleReconnect(vin: vin) }
            }
        }
    }

    private func applyDrive(_ drive: DriveState) {
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
        pushLiveActivity()
    }

    private func applySnapshot(_ snap: TeslaVehicleSnapshot) {
        if let charge = snap.charge {
            let rangeKm: Int? = {
                if let mi = charge.estBatteryRangeMiles ?? charge.batteryRangeMiles {
                    return Int((mi * 1.60934).rounded())
                }
                return nil
            }()
            let charging = charge.chargingStatus == .charging || charge.chargingStatus == .starting
            telemetry.applyTeslaCharge(
                soc: charge.batteryLevel,
                rangeKm: rangeKm,
                chargeKw: charge.chargerPower,
                charging: charging,
                limitPercent: charge.chargeLimitPercent,
                amps: charge.chargerCurrent,
                volts: charge.chargerVoltage,
                minutesToFull: charge.minutesToFullCharge,
                portOpen: charge.chargePortOpen
            )
        }
        if let climate = snap.climate {
            telemetry.applyTeslaClimate(
                outsideC: climate.outsideTempCelsius,
                insideC: climate.insideTempCelsius,
                climateOn: climate.isClimateOn
            )
        }
        if let tires = snap.tirePressure {
            func reading(_ t: TirePressureState.Tire?) -> EtubuTireReading {
                EtubuTireReading(
                    psi: EtubuVehicleTelemetry.barToPsi(t?.pressureBar),
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
                    guard let self else { return }
                    switch state {
                    case .scanning:
                        self.telemetry.connectionState = .connecting
                        self.telemetry.statusMessage = "Scanning…"
                    case .connecting, .handshaking:
                        self.telemetry.connectionState = .connecting
                        self.telemetry.statusMessage = "Handshaking…"
                    case .connected:
                        self.telemetry.connectionState = .connected
                        self.telemetry.statusMessage = "Connected · salt okuma"
                    case .disconnected:
                        if !self.userStopped {
                            self.telemetry.connectionState = .reconnecting
                            self.telemetry.statusMessage = "Reconnecting…"
                        }
                    @unknown default:
                        break
                    }
                }
            }
        }
    }

    private func scheduleReconnect(vin: String) {
        guard !userStopped else { return }
        reconnectTask?.cancel()
        reconnectAttempt += 1
        let delay = min(15.0, pow(2.0, Double(min(reconnectAttempt, 4) - 1)))
        telemetry.connectionState = .reconnecting
        telemetry.statusMessage = "Reconnecting in \(Int(delay))s…"
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !self.userStopped else { return }
            await self.connectNormal(vin: vin)
        }
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
}
