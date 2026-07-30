import Foundation
import CoreBluetooth

/// Native ELM327 BLE manager — scan, connect, multi-PID poll, auto-reconnect.
final class EtubuObdBleManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = EtubuObdBleManager()

    private enum Pid: CaseIterable {
        case speed, rpm, coolant, voltage, throttle, load

        var command: String {
            switch self {
            case .speed: return "010D\r"
            case .rpm: return "010C\r"
            case .coolant: return "0105\r"
            case .voltage: return "0142\r"
            case .throttle: return "0111\r"
            case .load: return "0104\r"
            }
        }
    }

    private let knownUartServiceUUIDs: [CBUUID] = [
        CBUUID(string: "FFF0"),
        CBUUID(string: "FFE0"),
        CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"),
    ]

    private var central: CBCentralManager?
    private var target: CBPeripheral?
    private var rxChar: CBCharacteristic?
    private var txChar: CBCharacteristic?
    private var isConnecting = false
    private var isConnected = false
    private var userRequestedDisconnect = false
    private var autoConnectPreferred = true
    private var pendingConnect: ((Bool, String) -> Void)?
    private var emit: (([String: Any]) -> Void)?
    private var pollTimer: Timer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var scanTimeoutWorkItem: DispatchWorkItem?
    private var reconnectAttempt = 0
    private var pidIndex = 0
    private var lineBuffer = ""
    private var lastKmh: Int = 0
    private var lastRpm: Int = 0
    private var discoveryById: [UUID: EtubuObdDiscoveredDevice] = [:]
    private var preferredPeripheralId: UUID?

    var telemetry: EtubuObdTelemetry { .shared }

    private override init() {
        super.init()
    }

    func setEmit(_ handler: @escaping ([String: Any]) -> Void) {
        emit = handler
    }

    func statePayload() -> [String: Any] {
        [
            "ok": true,
            "connected": isConnected,
            "connecting": isConnecting || telemetry.connectionState == .reconnecting,
            "name": target?.name ?? telemetry.deviceName,
            "state": telemetry.connectionState.rawValue,
            "kmh": lastKmh,
            "rpm": lastRpm,
        ]
    }

    // MARK: - Public API

    /// Connect: prefers remembered UUID, else starts discovery (auto-picks first OBD if `autoConnectPreferred`).
    func connect(completion: @escaping (Bool, String) -> Void) {
        userRequestedDisconnect = false
        autoConnectPreferred = true
        preferredPeripheralId = EtubuObdDeviceStore.lastUUID

        if isConnected {
            completion(true, "already_connected")
            return
        }
        if isConnecting {
            completion(false, "already_connecting")
            return
        }

        pendingConnect = completion
        isConnecting = true
        setState(.connecting)
        emitStatus("connecting")
        ensureCentral()
    }

    /// Scan only — populate device list for picker (no auto-connect).
    func startScanForPicker() {
        userRequestedDisconnect = false
        autoConnectPreferred = false
        preferredPeripheralId = nil
        discoveryById.removeAll()
        DispatchQueue.main.async {
            self.telemetry.discovered = []
            self.telemetry.isScanning = true
        }
        setState(.scanning)
        emitStatus("scanning")
        isConnecting = true
        ensureCentral()
        scheduleScanTimeout(seconds: 12)
    }

    func stopScanForPicker() {
        scanTimeoutWorkItem?.cancel()
        central?.stopScan()
        isConnecting = false
        DispatchQueue.main.async { self.telemetry.isScanning = false }
        if !isConnected {
            setState(.idle)
        }
    }

    func connect(to id: UUID, completion: @escaping (Bool, String) -> Void) {
        userRequestedDisconnect = false
        autoConnectPreferred = false
        preferredPeripheralId = id
        stopScanForPicker()

        if isConnected, target?.identifier == id {
            completion(true, "already_connected")
            return
        }
        if isConnected {
            disconnect(userInitiated: false)
        }

        pendingConnect = completion
        isConnecting = true
        setState(.connecting)
        emitStatus("connecting")
        ensureCentral()
        attemptConnectToPreferred()
    }

    func disconnect() {
        disconnect(userInitiated: true)
    }

    private func disconnect(userInitiated: Bool) {
        userRequestedDisconnect = userInitiated
        cancelReconnect()
        stopPolling()
        scanTimeoutWorkItem?.cancel()
        central?.stopScan()
        if let p = target {
            central?.cancelPeripheralConnection(p)
        }
        if userInitiated {
            EtubuObdDeviceStore.clear()
        }
        cleanupConnection(notify: true)
        setState(userInitiated ? .idle : .disconnected)
        DispatchQueue.main.async {
            self.telemetry.isScanning = false
            if userInitiated { self.telemetry.resetLiveValues() }
        }
        if userInitiated {
            pendingConnect?(false, "disconnected")
            pendingConnect = nil
        }
    }

    // MARK: - Central lifecycle

    private func ensureCentral() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            startScanIfReady()
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        startScanIfReady()
    }

    private func startScanIfReady() {
        guard let c = central else { return }
        guard c.state == .poweredOn else {
            if c.state == .poweredOff || c.state == .unauthorized || c.state == .unsupported {
                isConnecting = false
                setState(.bluetoothUnavailable)
                pendingConnect?(false, "bluetooth_unavailable")
                pendingConnect = nil
                emitStatus("bluetooth_unavailable")
                DispatchQueue.main.async { self.telemetry.isScanning = false }
            }
            return
        }

        if let preferred = preferredPeripheralId ?? EtubuObdDeviceStore.lastUUID {
            preferredPeripheralId = preferred
            let known = c.retrievePeripherals(withIdentifiers: [preferred])
            if let p = known.first {
                connectPeripheral(p)
                return
            }
        }

        beginScan(c)
    }

    private func attemptConnectToPreferred() {
        guard let c = central, c.state == .poweredOn else { return }
        guard let id = preferredPeripheralId else {
            beginScan(c)
            return
        }
        let known = c.retrievePeripherals(withIdentifiers: [id])
        if let p = known.first {
            connectPeripheral(p)
        } else {
            beginScan(c)
        }
    }

    private func beginScan(_ c: CBCentralManager) {
        c.stopScan()
        discoveryById.removeAll()
        if telemetry.connectionState != .reconnecting && telemetry.connectionState != .scanning {
            setState(autoConnectPreferred ? .connecting : .scanning)
        }
        c.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scheduleScanTimeout(seconds: autoConnectPreferred ? 10 : 12)
    }

    private func scheduleScanTimeout(seconds: TimeInterval) {
        scanTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.isConnecting && !self.isConnected {
                self.central?.stopScan()
                self.isConnecting = false
                DispatchQueue.main.async { self.telemetry.isScanning = false }
                if self.telemetry.connectionState == .reconnecting {
                    self.scheduleReconnect()
                } else {
                    self.setState(.scanTimeout)
                    self.pendingConnect?(false, "scan_timeout")
                    self.pendingConnect = nil
                    self.emitStatus("scan_timeout")
                }
            }
        }
        scanTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isConnecting || telemetry.isScanning else { return }

        let localName = (peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "")
        let nameLower = localName.lowercased()
        let serviceIds = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let hasUart = serviceIds.contains(where: { knownUartServiceUUIDs.contains($0) })
        let likelyObd = hasUart
            || nameLower.contains("obd")
            || nameLower.contains("elm")
            || nameLower.contains("vlink")
            || nameLower.contains("icar")
            || nameLower.contains("obdii")

        guard likelyObd else { return }

        let display = localName.isEmpty ? "OBD" : localName
        let device = EtubuObdDiscoveredDevice(
            id: peripheral.identifier,
            name: display,
            rssi: RSSI.intValue
        )
        discoveryById[peripheral.identifier] = device
        let list = discoveryById.values.sorted { $0.rssi > $1.rssi }
        DispatchQueue.main.async {
            self.telemetry.discovered = list
        }

        if let preferred = preferredPeripheralId, peripheral.identifier == preferred {
            scanTimeoutWorkItem?.cancel()
            connectPeripheral(peripheral)
            return
        }

        if autoConnectPreferred {
            scanTimeoutWorkItem?.cancel()
            connectPeripheral(peripheral)
        }
    }

    private func connectPeripheral(_ peripheral: CBPeripheral) {
        central?.stopScan()
        DispatchQueue.main.async { self.telemetry.isScanning = false }
        target = peripheral
        peripheral.delegate = self
        setState(telemetry.connectionState == .reconnecting ? .reconnecting : .connecting)
        central?.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnecting = false
        emitStatus("connect_failed", extra: ["error": error?.localizedDescription ?? ""])
        cleanupConnection(notify: false)
        if !userRequestedDisconnect, EtubuObdDeviceStore.lastUUID != nil {
            setState(.reconnecting)
            scheduleReconnect()
        } else {
            setState(.connectFailed)
            pendingConnect?(false, "connect_failed")
            pendingConnect = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let hadConnection = isConnected
        cleanupConnection(notify: true)
        if hadConnection {
            emitStatus("disconnected")
        }
        if !userRequestedDisconnect, EtubuObdDeviceStore.lastUUID != nil {
            setState(.reconnecting)
            scheduleReconnect()
        } else if !userRequestedDisconnect {
            setState(.disconnected)
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        cancelReconnect()
        reconnectAttempt += 1
        let delay = min(15.0, pow(2.0, Double(min(reconnectAttempt, 4) - 1)))
        setState(.reconnecting)
        emitStatus("reconnecting")
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.userRequestedDisconnect else { return }
            self.isConnecting = true
            self.preferredPeripheralId = EtubuObdDeviceStore.lastUUID
            self.autoConnectPreferred = true
            self.ensureCentral()
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        reconnectAttempt = 0
    }

    // MARK: - Peripheral GATT

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            pendingConnect?(false, "service_discovery_failed")
            pendingConnect = nil
            return
        }
        (peripheral.services ?? []).forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        for ch in service.characteristics ?? [] {
            if ch.properties.contains(.notify) || ch.properties.contains(.indicate) {
                if rxChar == nil { rxChar = ch }
            }
            if ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse) {
                if txChar == nil { txChar = ch }
            }
        }
        if rxChar != nil && txChar != nil {
            finishConnect(peripheral)
        }
    }

    private func finishConnect(_ peripheral: CBPeripheral) {
        guard let rx = rxChar else { return }
        peripheral.setNotifyValue(true, for: rx)
        isConnecting = false
        isConnected = true
        reconnectAttempt = 0
        cancelReconnect()
        scanTimeoutWorkItem?.cancel()
        EtubuObdDeviceStore.remember(peripheral)
        let name = peripheral.name ?? EtubuObdDeviceStore.lastName ?? "OBD"
        DispatchQueue.main.async {
            self.telemetry.deviceName = name
            self.telemetry.isScanning = false
        }
        setState(.connected)
        pendingConnect?(true, "connected")
        pendingConnect = nil
        emitStatus("connected", extra: ["name": name])
        bootstrapElm()
        startPolling()
    }

    private func bootstrapElm() {
        send("ATZ\r")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.send("ATE0\r")
            self?.send("ATL0\r")
            self?.send("ATS0\r")
            self?.send("ATH0\r")
            self?.send("ATSP0\r")
        }
    }

    private func startPolling() {
        stopPolling()
        pidIndex = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            let pids = Pid.allCases
            let pid = pids[self.pidIndex % pids.count]
            self.pidIndex += 1
            self.send(pid.command)
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func send(_ cmd: String) {
        guard let p = target, let tx = txChar else { return }
        let data = Data(cmd.utf8)
        if tx.properties.contains(.writeWithoutResponse) {
            p.writeValue(data, for: tx, type: .withoutResponse)
        } else if tx.properties.contains(.write) {
            p.writeValue(data, for: tx, type: .withResponse)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        lineBuffer += chunk
        while let idx = lineBuffer.firstIndex(where: { $0 == "\r" || $0 == "\n" || $0 == ">" }) {
            let line = String(lineBuffer[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            lineBuffer = String(lineBuffer[lineBuffer.index(after: idx)...])
            if !line.isEmpty { parseElmLine(line) }
        }
    }

    private func parseElmLine(_ line: String) {
        let clean = line.replacingOccurrences(of: " ", with: "").uppercased()

        if let speedHex = capture(clean, pattern: "410D([0-9A-F]{2})"), let raw = Int(speedHex, radix: 16) {
            lastKmh = max(0, raw)
            pushSpeed()
            return
        }
        if let rpmHex = capture(clean, pattern: "410C([0-9A-F]{4})"), let raw = Int(rpmHex, radix: 16) {
            lastRpm = max(0, raw / 4)
            pushSpeed()
            return
        }
        if let hex = capture(clean, pattern: "4105([0-9A-F]{2})"), let raw = Int(hex, radix: 16) {
            let c = raw - 40
            DispatchQueue.main.async {
                self.telemetry.coolantC = c
                EtubuVehicleTelemetry.shared.coolantC = c
            }
            return
        }
        if let hex = capture(clean, pattern: "4142([0-9A-F]{4})"), let raw = Int(hex, radix: 16) {
            let v = Double(raw) / 1000.0
            DispatchQueue.main.async {
                self.telemetry.voltageV = v
                EtubuVehicleTelemetry.shared.voltageV = v
            }
            return
        }
        if let hex = capture(clean, pattern: "4111([0-9A-F]{2})"), let raw = Int(hex, radix: 16) {
            let pct = Int((Double(raw) * 100.0 / 255.0).rounded())
            DispatchQueue.main.async { self.telemetry.throttlePct = pct }
            return
        }
        if let hex = capture(clean, pattern: "4104([0-9A-F]{2})"), let raw = Int(hex, radix: 16) {
            let pct = Int((Double(raw) * 100.0 / 255.0).rounded())
            DispatchQueue.main.async { self.telemetry.engineLoadPct = pct }
        }
    }

    private func pushSpeed() {
        DispatchQueue.main.async {
            self.telemetry.applySpeed(kmh: self.lastKmh, rpm: self.lastRpm)
            EtubuVehicleTelemetry.shared.applyObdFallback(
                kmh: self.lastKmh,
                rpm: self.lastRpm,
                coolant: self.telemetry.coolantC,
                voltage: self.telemetry.voltageV
            )
        }
        var payload: [String: Any] = [
            "type": "speed",
            "kmh": lastKmh,
            "source": "obd_ble",
        ]
        payload["rpm"] = lastRpm
        emit?(payload)
    }

    private func capture(_ text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: text, options: [], range: range), m.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private func cleanupConnection(notify: Bool) {
        stopPolling()
        rxChar = nil
        txChar = nil
        lineBuffer = ""
        isConnecting = false
        isConnected = false
        if notify {
            emit?(["type": "state", "connected": false, "source": "obd_ble"])
        }
    }

    private func setState(_ state: EtubuObdConnectionState) {
        DispatchQueue.main.async {
            self.telemetry.connectionState = state
        }
    }

    private func emitStatus(_ state: String, extra: [String: Any] = [:]) {
        var payload: [String: Any] = ["type": "status", "state": state]
        for (k, v) in extra { payload[k] = v }
        emit?(payload)
    }
}
