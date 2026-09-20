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
    private var vcsecTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var userStopped = false
    private var reconnectAttempt = 0
    private var lastUserPresent: Bool?
    private var extrasTick = 0
    /// Consecutive extras polls still missing SoC/climate/TPMS — wake after ~8.
    private var extrasMissingStreak = 0
    private var lastExtrasWakeAt = Date.distantPast
    private var activePairVIN: String?
    /// Ignore brief BLE disconnect flickers right after a successful connect.
    private var connectedAt: Date?
    private var ignoreDisconnectUntil: Date?
    @Published private(set) var pairStep: PairFlowStep = .none
    /// ECDH / MAC / counter-window desync — UI should ask for NFC re-pair.
    @Published private(set) var needsRePairing = false
    private var cryptoFaultStreak = 0

    private var telemetry: EtubuVehicleTelemetry { .shared }
    /// Demo sürerken BLE poll yazmasın.
    private var demoSuspended = false
    /// Pair / connect spam kilidi.
    private var pairInFlight = false
    /// Uygulama açılışında bir kez otomatik bağlan; sonra yalnızca kullanıcı / demo dönüşü.
    private var didAutoBootstrapThisProcess = false
    private var connectInFlight = false
    /// Dropped reconnect while connect was in-flight — retry after current connect finishes.
    private var pendingReconnectVIN: String?
    private var pollGeneration = 0
    private var driveWatchTask: Task<Void, Never>?
    private var liveHealTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var emptyDriveStreak = 0
    private var lastForcedReconnectAt = Date.distantPast
    private var lastFreshExtrasAt = Date.distantPast

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
        Task { await connectNormal(vin: vin, allowPairFallback: false) }
    }

    private var isSessionHealthy: Bool {
        guard client != nil, telemetry.connectionState == .connected else { return false }
        if let valueAt = telemetry.lastDriveValueAt {
            return Date().timeIntervalSince(valueAt) < 6
        }
        return false
    }

    /// Power-save: keep drive speed; pause extras / VCSEC / heavy UI feeds.
    func setPowerSave(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "etubu.cluster.powerSave")
        guard !demoSuspended else { return }
        if on {
            extrasTask?.cancel()
            vcsecTask?.cancel()
            keepAliveTask?.cancel()
            extrasTask = nil
            vcsecTask = nil
            keepAliveTask = nil
        } else if let client, telemetry.connectionState == .connected || telemetry.connectionState == .reconnecting {
            // Restart side loops without tearing down drive poll.
            if extrasTask == nil || vcsecTask == nil {
                startPolling(client)
            }
        }
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
        clearRePairingLock()
        await pair(vin: vin)
    }

    func connectSaved() async {
        guard let vin = EtubuTeslaVinStore.vin else {
            telemetry.connectionState = .needsVIN
            return
        }
        userStopped = false
        didAutoBootstrapThisProcess = true
        await connectNormal(vin: vin, allowPairFallback: false)
    }

    /// Switch to a previously used VIN without wiping its pairing flag.
    func switchToVIN(_ raw: String) async {
        let vin = EtubuTeslaVinStore.normalize(raw)
        guard EtubuTeslaVinStore.isValidVIN(vin) else {
            telemetry.statusMessage = EtubuClusterL10n.t("bleVinLen")
            return
        }
        userStopped = false
        if client != nil {
            cancelJobs()
            await client?.disconnect()
            client = nil
        }
        EtubuTeslaVinStore.vin = vin
        telemetry.vin = vin
        telemetry.deviceLabel = "Tesla \(String(vin.suffix(6)))"
        userStopped = false
        if EtubuTeslaVinStore.pairedConfirmed(for: vin) {
            didAutoBootstrapThisProcess = true
            await connectNormal(vin: vin, allowPairFallback: false)
        } else {
            await pair(vin: vin)
        }
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
        clearRePairingLock()
        await pair(vin: vin)
    }

    /// Crypto desync CTA — stop reconnect loop and start a fresh NFC pair.
    func beginRePairing() async {
        userStopped = false
        clearRePairingLock()
        await retryPair()
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
        clearRePairingLock()

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

    private func connectNormal(vin: String, allowPairFallback: Bool = false, maxRetries: Int = 1) async {
        guard !demoSuspended else { return }
        if isSessionHealthy {
            if pollTask == nil, let client { startPolling(client) }
            return
        }
        guard !connectInFlight else {
            pendingReconnectVIN = vin
            return
        }
        connectInFlight = true
        defer {
            connectInFlight = false
            if let pending = pendingReconnectVIN, pending == vin, !isSessionHealthy, shouldAutoReconnect {
                pendingReconnectVIN = nil
                scheduleReconnect(vin: pending, debounce: 1.0)
            } else if pendingReconnectVIN == vin {
                pendingReconnectVIN = nil
            }
        }
        cancelJobs()
        if let old = client {
            await old.disconnect()
            client = nil
        }
        telemetry.connectionState = .connecting
        telemetry.statusMessage = EtubuClusterL10n.t("bleConnecting")
        pairStep = .none

        // Never mint a new key on reconnect — that forces another NFC card tap.
        if (try? keyStore.loadPrivateKey(forVIN: vin)) == nil {
            telemetry.connectionState = .failed
            telemetry.statusMessage = EtubuClusterL10n.t("bleKeyMissing")
            if allowPairFallback {
                await pair(vin: vin)
            } else if shouldAutoReconnect {
                scheduleReconnect(vin: vin, debounce: 3.0)
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
                clearRePairingLock()
                telemetry.connectionState = .connected
                telemetry.lockToTeslaSource()
                telemetry.statusMessage = EtubuClusterL10n.t("bleConnected")
                EtubuVehicleTelemetry.shared.scrubDemoChargeResidueIfNeeded()
                EtubuTeslaVinStore.setPairedConfirmed(true, for: vin)
                activePairVIN = nil
                pairStep = .none
                pendingReconnectVIN = nil
                startPolling(c)
                startLiveHeal(c)
                EtubuVehicleLaunchNotifier.shared.notifyVehicleConnected(source: "tesla")
                return
            } catch {
                if notePossibleDesync(error, threshold: 2) { return }
                if attempt < maxRetries {
                    telemetry.connectionState = .reconnecting
                    telemetry.statusMessage = String(format: EtubuClusterL10n.t("bleRetryFmt"), attempt + 1, maxRetries)
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                    continue
                }
                pairStep = .none
                telemetry.connectionState = .failed
                telemetry.statusMessage = error.localizedDescription
                if self.shouldAutoReconnect {
                    self.scheduleReconnect(vin: vin, debounce: 2.5)
                }
            }
        }
    }

    /// Dual-loop Infotainment: drive HUD ~4–5 Hz when moving; GPS fills BLE gaps.
    /// Charge/climate/TPMS ~60 s. Keepalive wake while moving. Failures never poison other loops.
    private func startPolling(_ client: TeslaVehicleClient) {
        pollTask?.cancel()
        extrasTask?.cancel()
        vcsecTask?.cancel()
        keepAliveTask?.cancel()
        driveWatchTask?.cancel()
        pollGeneration &+= 1
        let gen = pollGeneration
        pollTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    if self.pollGeneration == gen { self.pollTask = nil }
                }
            }
            var failStreak = 0
            while !Task.isCancelled {
                let suspended = await MainActor.run { self.demoSuspended }
                if suspended { return }
                do {
                    let drive = try await client.fetchDrive(timeout: .seconds(2))
                    failStreak = 0
                    await MainActor.run { self.applyDrive(drive) }
                } catch {
                    if await MainActor.run(body: { self.notePossibleDesync(error, threshold: 3) }) {
                        return
                    }
                    failStreak += 1
                    if failStreak < 10 {
                        await MainActor.run {
                            self.telemetry.statusMessage = String(format: EtubuClusterL10n.t("bleWeakSignalFmt"), failStreak)
                        }
                        try? await Task.sleep(nanoseconds: UInt64(min(1200, 280 + failStreak * 90)) * 1_000_000)
                        continue
                    }
                    await MainActor.run {
                        self.telemetry.statusMessage = error.localizedDescription
                        self.telemetry.connectionState = .reconnecting
                        if self.shouldAutoReconnect, let vin = EtubuTeslaVinStore.vin {
                            self.scheduleReconnect(vin: vin, debounce: 1.5)
                        }
                    }
                    failStreak = 4
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    continue
                }
                // Drive HUD: ~180 ms gap when moving → ~4–5 Hz with BLE RTT.
                // Parked stays slower so extras/VCSEC keep the wire.
                // Timeout is 2 s. Extras loop is separate — safe to raise drive rate.
                let sleepNs: UInt64 = await MainActor.run {
                    let moving = self.telemetry.kmh >= 3 || self.telemetry.kmhFine >= 3
                    if moving { return 180_000_000 }
                    return 1_600_000_000
                }
                try? await Task.sleep(nanoseconds: sleepNs)
            }
        }
        extrasTask = Task { [weak self] in
            guard let self else { return }
            await self.bootstrapExtras(client)
            while !Task.isCancelled {
                let suspended = await MainActor.run { self.demoSuspended }
                if suspended { return }
                let (due, missing) = await MainActor.run { () -> (Bool, Bool) in
                    let missing = !self.telemetry.liveChargeConfirmed
                    let age = self.telemetry.lastChargeAt.map { Date().timeIntervalSince($0) } ?? 99
                    return (missing || age > 58, missing)
                }
                if due {
                    await self.pollExtrasOnce(client)
                    await MainActor.run { self.lastFreshExtrasAt = Date() }
                }
                try? await Task.sleep(nanoseconds: missing ? 8_000_000_000 : 60_000_000_000)
            }
        }
        startVcsecStatusLoop(client)
        startKeepAliveWake(client)
        startLiveHeal(client)
        driveWatchTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                let action = await MainActor.run { () -> String in
                    guard !self.demoSuspended, !self.userStopped else { return "stop" }
                    guard self.client === client else { return "stop" }
                    guard self.telemetry.connectionState == .connected
                        || self.telemetry.connectionState == .reconnecting else { return "wait" }
                    if self.pollTask == nil { return "restart" }
                    let gpsOk = self.telemetry.lastGpsSampleFresh || self.telemetry.hudUsesGpsSpeed
                    if gpsOk { return "ok" }
                    if let last = self.telemetry.lastDriveValueAt,
                       Date().timeIntervalSince(last) > 5.5 {
                        return "restart"
                    }
                    if self.telemetry.lastDriveValueAt == nil,
                       let last = self.telemetry.lastDriveAt,
                       Date().timeIntervalSince(last) > 5.5 {
                        return "restart"
                    }
                    return "ok"
                }
                if action == "stop" { return }
                if action == "restart" {
                    await MainActor.run {
                        if self.client === client { self.startPolling(client) }
                    }
                    return
                }
            }
        }
    }

    /// Charge/climate health is independent of TPMS — tires must not mask a frozen SoC.
    private func startLiveHeal(_ client: TeslaVehicleClient) {
        liveHealTask?.cancel()
        liveHealTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                let action = await MainActor.run { () -> String in
                    guard !self.demoSuspended, !self.userStopped else { return "stop" }
                    guard self.client === client else { return "stop" }
                    let connected = self.telemetry.connectionState == .connected
                        || self.telemetry.connectionState == .reconnecting
                    guard connected else { return "wait" }
                    let driveAge = self.telemetry.lastDriveValueAt.map { Date().timeIntervalSince($0) } ?? 99
                    let gpsOk = self.telemetry.lastGpsSampleFresh || self.telemetry.hudUsesGpsSpeed
                    if driveAge > 40, !gpsOk, Date().timeIntervalSince(self.lastForcedReconnectAt) > 20 {
                        return "rehandshake"
                    }
                    if self.telemetry.needsVehicleExtrasRefresh { return "fresh" }
                    return "ok"
                }
                if action == "stop" { return }
                if action == "wait" { continue }
                if action == "rehandshake" {
                    await MainActor.run {
                        self.lastForcedReconnectAt = Date()
                        if let vin = EtubuTeslaVinStore.vin, self.shouldAutoReconnect {
                            self.scheduleReconnect(vin: vin, debounce: 0.4)
                        }
                    }
                    continue
                }
                if action == "fresh" {
                    let shouldWake = await MainActor.run {
                        Date().timeIntervalSince(self.lastExtrasWakeAt) > 14
                    }
                    if shouldWake {
                        try? await client.send(.security(.wakeVehicle))
                        await MainActor.run { self.lastExtrasWakeAt = Date() }
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                    await self.bootstrapExtras(client)
                    await MainActor.run { self.lastFreshExtrasAt = Date() }
                }
            }
        }
    }

    /// Keep Infotainment from napping while the cluster is live. Moving: ~25 s. Parked: before the 60 s extras sync.
    private func startKeepAliveWake(_ client: TeslaVehicleClient) {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                let shouldWake = await MainActor.run { () -> Bool in
                    guard !self.demoSuspended, !self.userStopped else { return false }
                    guard self.client === client else { return false }
                    let connected = self.telemetry.connectionState == .connected
                        || self.telemetry.connectionState == .reconnecting
                    guard connected else { return false }
                    if Date().timeIntervalSince(self.lastExtrasWakeAt) < 22 { return false }
                    let moving = self.telemetry.kmh >= 3
                    let chargeDue = self.telemetry.needsVehicleExtrasRefresh
                    return moving || chargeDue
                }
                if shouldWake {
                    try? await client.send(.security(.wakeVehicle))
                    await MainActor.run { self.lastExtrasWakeAt = Date() }
                }
            }
        }
    }

    /// 1 Hz VCSEC GET_STATUS over the existing signed session (incrementing counter in Dispatcher).
    /// Does not replace Infotainment drive/charge polls — lock/presence stay live even if Infotainment naps.
    private func startVcsecStatusLoop(_ client: TeslaVehicleClient) {
        vcsecTask?.cancel()
        vcsecTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let suspended = await MainActor.run { self.demoSuspended }
                if suspended { return }
                do {
                    let result = try await client.query(.bodyControllerState, timeout: .seconds(3))
                    if case .bodyControllerState(let status) = result {
                        await MainActor.run { self.applyVcsecStatus(status) }
                    }
                } catch {
                    await MainActor.run { _ = self.notePossibleDesync(error, threshold: 4) }
                    // VCSEC miss must never cancel drive/extras.
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private func applyVcsecStatus(_ status: VCSEC_VehicleStatus) {
        guard !demoSuspended else { return }
        let locked: Bool? = {
            switch status.vehicleLockState {
            case .vehiclelockstateLocked, .vehiclelockstateInternalLocked: return true
            case .vehiclelockstateUnlocked, .vehiclelockstateSelectiveUnlocked: return false
            default: return nil
            }
        }()
        let present: Bool? = {
            switch status.userPresence {
            case .vehicleUserPresencePresent: return true
            case .vehicleUserPresenceNotPresent: return false
            default: return nil
            }
        }()
        telemetry.applyVcsecStatus(locked: locked, userPresent: present)
        if status.vehicleSleepStatus == .vehicleSleepStatusAsleep,
           telemetry.needsVehicleExtrasRefresh,
           Date().timeIntervalSince(lastExtrasWakeAt) > 12 {
            lastExtrasWakeAt = Date()
            Task { try? await client?.send(.security(.wakeVehicle)) }
        }
    }

    /// Boot: sequential category fetches so one timeout cannot drop SoC/climate.
    private func bootstrapExtras(_ client: TeslaVehicleClient) async {
        for attempt in 1...3 {
            for cats in [
                Set<StateCategory>([.charge]),
                Set<StateCategory>([.climate]),
                Set<StateCategory>([.tirePressure]),
                Set<StateCategory>([.location]),
            ] {
                if let snap = try? await client.fetch(.categories(cats), timeout: .seconds(5)) {
                    await MainActor.run { self.applySnapshot(snap) }
                }
            }
            if attempt == 1, let clos = try? await client.fetch(.categories([.closures]), timeout: .seconds(4)) {
                await MainActor.run { self.applySnapshot(clos) }
            }
            let stillMissing = await MainActor.run { self.telemetry.needsVehicleExtrasRefresh }
            if !stillMissing { return }
            if attempt < 3 {
                try? await client.send(.security(.wakeVehicle))
                await MainActor.run { self.lastExtrasWakeAt = Date() }
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
            }
        }
    }

    private func pollExtrasOnce(_ client: TeslaVehicleClient) async {
        extrasTick += 1
        let tick = extrasTick
        let (parked, missing) = await MainActor.run { () -> (Bool, Bool) in
            let t = self.telemetry
            return (t.kmh < 3, !t.liveChargeConfirmed || t.needsVehicleExtrasRefresh)
        }

        if missing, Date().timeIntervalSince(lastExtrasWakeAt) > 20 {
            extrasMissingStreak = 0
            await MainActor.run { self.lastExtrasWakeAt = Date() }
            try? await client.send(.security(.wakeVehicle))
            try? await Task.sleep(nanoseconds: 400_000_000)
        } else if !missing {
            extrasMissingStreak = 0
        }

        func fetchCats(_ cats: Set<StateCategory>, timeoutSec: Int = 5) async {
            do {
                let snap = try await client.fetch(.categories(cats), timeout: .seconds(timeoutSec))
                await MainActor.run { self.applySnapshot(snap) }
            } catch {
                await MainActor.run { _ = self.notePossibleDesync(error, threshold: 3) }
                if missing {
                    for cat in cats {
                        if let one = try? await client.fetch(.categories([cat]), timeout: .seconds(3)) {
                            await MainActor.run { self.applySnapshot(one) }
                        }
                    }
                }
            }
        }

        let extrasTimeout = parked ? 8 : 5
        await fetchCats([.charge], timeoutSec: extrasTimeout)
        await fetchCats([.climate], timeoutSec: extrasTimeout)
        await fetchCats([.tirePressure], timeoutSec: extrasTimeout)
        await fetchCats([.location], timeoutSec: extrasTimeout)
        if tick % 2 == 0 {
            await fetchCats([.closures], timeoutSec: extrasTimeout)
        }
    }

    private func applyDrive(_ drive: DriveState) {
        guard !demoSuspended else { return }
        // Nil speedMph → keep prior km/h (do not publish 0).
        let kmhFine: Double? = {
            guard let mph = drive.speedMph, mph.isFinite, mph >= 0, mph <= 175 else {
                return nil
            }
            return max(0, mph * 1.60934)
        }()
        let kmh: Int? = kmhFine.map { Int($0.rounded()) }
        if kmh == nil, drive.shiftState == nil, drive.powerKW == nil,
           drive.activeRouteDestination == nil {
            emptyDriveStreak += 1
            telemetry.publishFusedHudSpeed()
            let gpsOk = telemetry.lastGpsSampleFresh || telemetry.hudUsesGpsSpeed
            if !gpsOk, emptyDriveStreak >= 10, Date().timeIntervalSince(lastForcedReconnectAt) > 12 {
                lastForcedReconnectAt = Date()
                emptyDriveStreak = 0
                if let vin = EtubuTeslaVinStore.vin, shouldAutoReconnect {
                    scheduleReconnect(vin: vin, debounce: 0.4)
                }
            }
            return
        }
        emptyDriveStreak = 0
        let gear: String? = {
            switch drive.shiftState {
            case .park: return "P"
            case .reverse: return "R"
            case .neutral: return "N"
            case .drive: return "D"
            case .none:
                if let kmh, kmh >= 3 { return "D" }
                return nil
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
            guard let kw = drive.powerKW else { return nil }
            if abs(kw) > 800 { return nil }
            return kw
        }()
        let vehicleArrival: Int? = {
            guard let e = drive.activeRouteEnergyAtArrival, e.isFinite else { return nil }
            // Tesla may report 0–1 fraction or 0–100 percent.
            let pct = e <= 1.5 ? e * 100.0 : e
            guard pct >= 0, pct <= 100 else { return nil }
            return Int(pct.rounded())
        }()
        let destLat = drive.activeRouteLatitude
        let destLng = drive.activeRouteLongitude
        telemetry.applyTeslaDrive(
            kmh: kmh,
            kmhFine: kmhFine,
            gear: gear,
            powerKw: power,
            odometerKm: odoKm,
            navDestination: drive.activeRouteDestination,
            navRemainKm: remainKm,
            navEtaMinutes: drive.activeRouteMinutesToArrival,
            vehicleEnergyAtArrival: vehicleArrival,
            navDestLat: destLat,
            navDestLng: destLng
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
            etaMinutes: drive.activeRouteMinutesToArrival,
            destLat: destLat,
            destLng: destLng
        )
        // Live Activity: gear / SoC / warn / nav — not live speed (ActivityKit budget).
        pushLiveActivity()
    }

    private func applySnapshot(_ snap: TeslaVehicleSnapshot) {
        if let charge = snap.charge {
            // Mapper now preserves optionals (unset ≠ 0).
            let rangeKm: Int? = {
                let mi = charge.estBatteryRangeMiles ?? charge.batteryRangeMiles
                guard let mi, mi.isFinite, mi > 0.5, mi < 800 else { return nil }
                return Int((mi * 1.60934).rounded())
            }()
            let rangeIdealKm: Int? = {
                guard let mi = charge.idealBatteryRangeMiles, mi.isFinite, mi > 0.5, mi < 800 else { return nil }
                return Int((mi * 1.60934).rounded())
            }()
            let charging = charge.chargingStatus == .charging || charge.chargingStatus == .starting
            let soc: Int? = {
                guard let bl = charge.batteryLevel else { return nil }
                if bl < 0 || bl > 100 { return nil }
                return bl
            }()
            let limit: Int? = {
                guard let lim = charge.chargeLimitPercent, (50...100).contains(lim) else { return nil }
                return lim
            }()
            telemetry.applyTeslaCharge(
                soc: soc,
                rangeKm: rangeKm,
                rangeIdealKm: rangeIdealKm,
                chargeKw: charge.chargerPower.flatMap { $0 == 0 && !charging ? nil : $0 },
                charging: charging,
                limitPercent: limit,
                amps: charge.chargerCurrent.flatMap { $0 == 0 && !charging ? nil : $0 },
                volts: charge.chargerVoltage.flatMap { $0 == 0 && !charging ? nil : $0 },
                minutesToFull: charge.minutesToFullCharge.flatMap { $0 > 0 ? $0 : nil },
                portOpen: charge.chargePortOpen,
                homeLat: charge.homeLatitude,
                homeLng: charge.homeLongitude,
                workLat: charge.workLatitude,
                workLng: charge.workLongitude
            )
        }
        if let climate = snap.climate {
            // Optionals are real now — no unset→0.0 fake temps.
            let out = climate.outsideTempCelsius.flatMap { Self.sanitizeTempC($0, other: climate.insideTempCelsius) }
            let inn = climate.insideTempCelsius.flatMap { Self.sanitizeTempC($0, other: climate.outsideTempCelsius) }
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
            let doorOpen = [c.frontDriverDoor, c.frontPassengerDoor, c.rearDriverDoor, c.rearPassengerDoor, c.frontTrunk, c.rearTrunk]
                .contains { $0 == true }
            if doorOpen || c.isUserPresent == true {
                resumeAutoConnectIfNeeded()
            }
            if c.isUserPresent == false, lastUserPresent == true, telemetry.kmh < 3 {
                EtubuVehicleLaunchNotifier.shared.scheduleLeaveCarSummary()
            }
            if let present = c.isUserPresent {
                lastUserPresent = present
            }
        }
        if snap.media != nil || snap.mediaDetail != nil {
            telemetry.applyTeslaMedia(
                title: snap.media?.nowPlayingTitle,
                artist: snap.media?.nowPlayingArtist,
                album: snap.mediaDetail?.nowPlayingAlbum,
                sourceName: snap.mediaDetail?.nowPlayingSource ?? snap.mediaDetail?.a2dpSourceName
            )
        }
        if let loc = snap.location {
            telemetry.applyTeslaVehicleLocation(
                lat: loc.latitude,
                lng: loc.longitude,
                heading: loc.headingDeg
            )
        }
        pushLiveActivity()
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
                        self.reconnectAttempt = 0
                        self.ignoreDisconnectUntil = Date().addingTimeInterval(4)
                        self.telemetry.connectionState = .connected
                        self.telemetry.lockToTeslaSource()
                        self.telemetry.statusMessage = EtubuClusterL10n.t("bleConnectedReadOnly")
                        EtubuVehicleLaunchNotifier.shared.notifyVehicleConnected(source: "tesla")
                    case .disconnected:
                        if !self.userStopped {
                            EtubuVehicleLaunchNotifier.shared.scheduleLeaveCarSummary()
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

    /// Sürüş / aktif rota / eşleşmiş VIN varken kopunca yeniden dene.
    private var shouldAutoReconnect: Bool {
        guard !needsRePairing else { return false }
        guard !userStopped, !demoSuspended else { return false }
        guard let vin = EtubuTeslaVinStore.vin,
              EtubuTeslaVinStore.pairedConfirmed(for: vin) else { return false }
        return true
    }

    private func scheduleReconnect(vin: String, debounce: TimeInterval = 0) {
        guard shouldAutoReconnect else { return }
        guard EtubuTeslaVinStore.pairedConfirmed(for: vin) else { return }
        if isSessionHealthy { return }
        reconnectTask?.cancel()
        reconnectAttempt += 1
        let delay = max(debounce, min(12.0, pow(2.0, Double(min(reconnectAttempt, 5) - 1))))
        telemetry.connectionState = .reconnecting
        telemetry.statusMessage = String(format: EtubuClusterL10n.t("bleReconnectInFmt"), Int(delay))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !self.userStopped, !self.demoSuspended else { return }
            guard self.shouldAutoReconnect else {
                await MainActor.run {
                    if self.needsRePairing {
                        self.telemetry.connectionState = .failed
                        self.telemetry.statusMessage = EtubuClusterL10n.t("bleNeedsRePair")
                    } else {
                        self.telemetry.connectionState = .idle
                        self.telemetry.statusMessage = EtubuClusterL10n.t("bleDisconnected")
                    }
                }
                return
            }
            if self.isSessionHealthy { return }
            await self.connectNormal(vin: vin, allowPairFallback: false, maxRetries: 2)
        }
    }

    /// Foreground / BT ready — restore paired session without re-pair.
    func resumeAutoConnectIfNeeded() {
        guard !demoSuspended, !userStopped else { return }
        guard let vin = EtubuTeslaVinStore.vin,
              EtubuTeslaVinStore.pairedConfirmed(for: vin) else { return }
        if isSessionHealthy {
            if pollTask == nil, let client { startPolling(client) }
            return
        }
        didAutoBootstrapThisProcess = false
        reconnectAttempt = 0
        bootstrapIfPossible(reason: .userRequested)
    }

    /// SPM Climate mapper unset optional → nil; gerçek 0°C ile karıştırma.
    /// Exact ~0 alone (both sides unset/nil) → nil; if the other side is a real temp, keep 0°C.
    private static func sanitizeTempC(_ value: Double, other: Double?) -> Double? {
        guard value.isFinite else { return nil }
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
        vcsecTask?.cancel()
        stateTask?.cancel()
        reconnectTask?.cancel()
        driveWatchTask?.cancel()
        liveHealTask?.cancel()
        keepAliveTask?.cancel()
        pollTask = nil
        extrasTask = nil
        vcsecTask = nil
        stateTask = nil
        reconnectTask = nil
        driveWatchTask = nil
        liveHealTask = nil
        keepAliveTask = nil
    }

    private func pushLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        Task {
            EtubuLiveActivityController.ensureAudioSession(mixWithOthers: true)
            await EtubuLiveActivityController.publishCurrent()
        }
    }

    private func clearRePairingLock() {
        if needsRePairing { needsRePairing = false }
        cryptoFaultStreak = 0
    }

    /// MESSAGEFAULT_ERROR_INVALID_SIGNATURE (MAC) and sibling ECDH/counter faults.
    @discardableResult
    private func notePossibleDesync(_ error: Error, threshold: Int) -> Bool {
        guard Self.isCryptoDesync(error) else {
            cryptoFaultStreak = 0
            return false
        }
        cryptoFaultStreak += 1
        guard cryptoFaultStreak >= threshold else { return false }
        raiseNeedsRePairing()
        return true
    }

    private func raiseNeedsRePairing() {
        needsRePairing = true
        cryptoFaultStreak = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        cancelJobs()
        telemetry.connectionState = .failed
        telemetry.statusMessage = EtubuClusterL10n.t("bleNeedsRePair")
        pairStep = .failed
    }

    private static func isCryptoDesync(_ error: Error) -> Bool {
        if let tesla = error as? TeslaBLEError {
            switch tesla {
            case .handshakeFailed(let s), .fetchFailed(let s), .addKeyFailed(let s):
                if isCryptoDesyncText(s) { return true }
            default:
                break
            }
        }
        return isCryptoDesyncText(
            [String(describing: error), error.localizedDescription].joined(separator: " ")
        )
    }

    private static func isCryptoDesyncText(_ raw: String) -> Bool {
        let blob = raw.lowercased()
        let needles = [
            "rrorinvalidsignature",
            "messagefault_error_invalid_signature",
            "rrorinvalidtokenorcounter",
            "invalid_token_or_counter",
            "invalidtokenorcounter",
            "rrorunknownkeyid",
            "unknown_key_id",
            "unknownkeyid",
            "rrorinactivekey",
            "inactive_key",
            "inactivekey",
            "rrorincorrectepoch",
            "incorrect_epoch",
            "incorrectepoch",
            "rrornotprovisioned",
            "not_provisioned",
            "hmacmismatch",
            "hmac mismatch",
            "aesdecryptauth",
            "tokenandcounterinvalid"
        ]
        return needles.contains { blob.contains($0) }
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

    func mediaNext() async {
        await sendCommand(.media(.nextTrack), label: EtubuClusterL10n.t("cmdOkMediaNext"))
    }

    func mediaPrevious() async {
        await sendCommand(.media(.previousTrack), label: EtubuClusterL10n.t("cmdOkMediaPrev"))
    }

    func mediaTogglePlayback() async {
        await sendCommand(.media(.togglePlayback), label: EtubuClusterL10n.t("cmdOkMediaPlay"))
    }

    func setSentryMode(_ on: Bool) async {
        await sendCommand(
            .security(.setSentryMode(on)),
            label: EtubuClusterL10n.t(on ? "cmdOkSentryOn" : "cmdOkSentryOff")
        )
    }

    func setDogMode(_ on: Bool) async {
        await sendCommand(
            .climate(.setKeeperMode(on ? .dog : .off)),
            label: EtubuClusterL10n.t(on ? "cmdOkDog" : "cmdOkDogOff")
        )
    }

    func setCabinOverheatProtection(_ on: Bool) async {
        await sendCommand(
            .climate(.setCabinOverheatProtection(enabled: on, fanOnly: false)),
            label: EtubuClusterL10n.t(on ? "cmdOkCabinOverheat" : "cmdOkCabinOverheatOff")
        )
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
            _ = notePossibleDesync(error, threshold: 3)
            lastCommandMessage = String(
                format: EtubuClusterL10n.t("commandFailedFmt"),
                error.localizedDescription
            )
            telemetry.statusMessage = lastCommandMessage
        }
    }
}
