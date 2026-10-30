import CoreBluetooth
import Foundation
import Observation
import os
import WalkPadCore

private let ftmsService = CBUUID(string: "1826")
private let treadmillData = CBUUID(string: "2ACD")
private let controlPoint = CBUUID(string: "2AD9")
private let speedRangeChar = CBUUID(string: "2AD4")
private let inclineRangeChar = CBUUID(string: "2AD5")
private let savedPeripheralKey = "peripheralID"
let restoreSpeedKey = "restoreSpeedAfterPause"
private let log = Logger(subsystem: "com.github.gureevleonid.walkpadbar", category: "ble")

/// Keeps a BLE connection to an FTMS treadmill and exposes its latest stats.
/// CoreBluetooth callbacks are delivered on the main queue.
@Observable
final class WalkPad: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum Link: Equatable {
        case bluetoothUnavailable(String)
        case searching
        case connecting
        case connected
    }

    private(set) var link: Link = .searching {
        didSet { if link != oldValue { log.info("link: \(String(describing: self.link), privacy: .public)") } }
    }
    private(set) var name: String?
    private(set) var stats = TreadmillSample()
    private(set) var lastUpdate: Date?

    /// Belt is moving and data is fresh. Re-evaluated on every sample and once a second.
    private(set) var isRunning = false
    /// Paused mid-session: the pad keeps reporting the old speed with frozen counters.
    private(set) var isPaused = false

    /// Pad's control point is available.
    var canControl: Bool { link == .connected && controlChar != nil }
    private(set) var speedRange = SupportedRange(min: 1, max: 6, step: 0.1)
    private(set) var inclineRange = SupportedRange(min: 0, max: 9, step: 1)
    /// Last command rejected by the pad, shown in the panel until the next success.
    private(set) var commandError: String?

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    private var controlChar: CBCharacteristic?
    @ObservationIgnored private var hasControl = false
    @ObservationIgnored private var queued: [FTMSCommand] = []
    /// Most recently requested targets, so rapid +/− clicks build on each other
    /// instead of on the (lagging) reported values.
    @ObservationIgnored private var targetSpeed: (value: Double, at: Date)?
    @ObservationIgnored private var targetIncline: (value: Double, at: Date)?
    @ObservationIgnored private var belt = BeltTracker()

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        // Frames can stop arriving (link drop) or freeze (pause), so re-check movement every second.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshRunning() }
    }

    private func refreshRunning() {
        let now = Date()
        let live = link == .connected && lastUpdate.map { now.timeIntervalSince($0) < 5 } ?? false
        let running = live && belt.isMoving(at: now)
        let paused = live && belt.isPaused
        if running != isRunning { isRunning = running }
        if paused != isPaused { isPaused = paused }
    }

    // MARK: Control

    func startBelt() { send(.start) }
    func pauseBelt() { send(.pause) }
    func stopBelt() { send(.stop) }

    func changeSpeed(by delta: Double) {
        let base = recent(targetSpeed) ?? stats.speedKmh ?? speedRange.min
        let v = speedRange.clamp(base + delta)
        targetSpeed = (v, Date())
        belt.userSet(v)
        send(.setSpeed(kmh: v))
    }

    func changeIncline(by delta: Double) {
        let base = recent(targetIncline) ?? stats.inclinePercent ?? inclineRange.min
        let v = inclineRange.clamp(base + delta)
        targetIncline = (v, Date())
        send(.setIncline(percent: v))
    }

    private func recent(_ t: (value: Double, at: Date)?) -> Double? {
        guard let t, Date().timeIntervalSince(t.at) < 3 else { return nil }
        return t.value
    }

    private func send(_ cmd: FTMSCommand) {
        guard let p = peripheral, let ch = controlChar else { return }
        guard hasControl else {
            // FTMS requires Request Control first; replay the command once it is granted.
            if queued.isEmpty { write(.requestControl, p, ch) }
            queued.append(cmd)
            return
        }
        write(cmd, p, ch)
    }

    private func write(_ cmd: FTMSCommand, _ p: CBPeripheral, _ ch: CBCharacteristic) {
        log.info("control -> \(String(describing: cmd), privacy: .public)")
        p.writeValue(cmd.bytes, for: ch, type: .withResponse)
    }

    private func handleControlResponse(_ r: FTMSResponse) {
        log.info("control <- op \(r.requestOpcode) result \(String(describing: r.result), privacy: .public)")
        if r.requestOpcode == FTMSCommand.requestControl.opcode {
            hasControl = r.result == .success
            let pending = queued
            queued = []
            if hasControl { pending.forEach(send) } else { commandError = "Pad refused control" }
            return
        }
        switch r.result {
        case .success: commandError = nil
        case .notPermitted:
            // Control lapsed (e.g. pad was used from its remote); ask again next time.
            hasControl = false
            commandError = "Pad refused the command — try again"
        case .notSupported: commandError = "Not supported by this pad"
        case .invalidParameter: commandError = "Value out of range"
        default: commandError = "Command failed"
        }
    }

    func reconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        start()
    }

    private func start() {
        guard central.state == .poweredOn else { return }
        if let id = UserDefaults.standard.string(forKey: savedPeripheralKey).flatMap(UUID.init),
           let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(p)
        }
        // Scan regardless: the remembered peripheral may be stale or powered off.
        link = peripheral == nil ? .searching : .connecting
        central.scanForPeripherals(withServices: [ftmsService])
    }

    private func connect(_ p: CBPeripheral) {
        peripheral = p
        name = p.name
        p.delegate = self
        link = .connecting
        // A pending connect never times out, so this also covers "pad is switched off".
        central.connect(p)
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        log.debug("central state: \(c.state.rawValue)")
        switch c.state {
        case .poweredOn: start()
        case .poweredOff: link = .bluetoothUnavailable("Bluetooth is off")
        case .unauthorized: link = .bluetoothUnavailable("Bluetooth access denied")
        case .unsupported: link = .bluetoothUnavailable("Bluetooth unsupported")
        default: link = .bluetoothUnavailable("Bluetooth unavailable")
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        log.debug("discovered \(p.name ?? "?", privacy: .public) \(p.identifier, privacy: .public)")
        guard peripheral == nil || peripheral?.identifier == p.identifier,
              p.state == .disconnected else { return }
        c.stopScan()
        connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        c.stopScan()
        UserDefaults.standard.set(p.identifier.uuidString, forKey: savedPeripheralKey)
        name = p.name
        link = .connected
        p.discoverServices([ftmsService])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        connect(p)
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        lastUpdate = nil
        stats.speedKmh = nil
        controlChar = nil
        hasControl = false
        queued = []
        belt = BeltTracker()
        refreshRunning()
        guard p.identifier == peripheral?.identifier else { return }
        connect(p)
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] where s.uuid == ftmsService {
            p.discoverCharacteristics([treadmillData, controlPoint, speedRangeChar, inclineRangeChar], for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            switch ch.uuid {
            case treadmillData, controlPoint: p.setNotifyValue(true, for: ch)
            case speedRangeChar, inclineRangeChar: p.readValue(for: ch)
            default: break
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        // Responses arrive as indications, so only offer control once they are enabled.
        if ch.uuid == controlPoint, ch.isNotifying { controlChar = ch }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let v = ch.value else { return }
        switch ch.uuid {
        case controlPoint:
            if let r = FTMSResponse.parse(v) { handleControlResponse(r) }
            return
        case speedRangeChar:
            if let r = SupportedRange.parse(v, scale: 0.01) { speedRange = r }
            return
        case inclineRangeChar:
            if let r = SupportedRange.parse(v, scale: 0.1) { inclineRange = r }
            return
        default: break
        }
        guard ch.uuid == treadmillData, let s = TreadmillDataParser.parse(v) else { return }
        stats.merge(s)
        lastUpdate = Date()
        if let speed = s.speedKmh,
           let cruise = belt.observe(speed: speed, elapsed: s.elapsedSeconds,
                                     distance: stats.distanceMeters, at: Date()),
           UserDefaults.standard.object(forKey: restoreSpeedKey) as? Bool ?? true {
            log.info("resumed at \(speed) km/h, restoring \(cruise) km/h")
            targetSpeed = (cruise, Date())
            send(.setSpeed(kmh: speedRange.clamp(cruise)))
        }
        refreshRunning()
        log.debug("sample: \(String(describing: self.stats), privacy: .public)")
    }
}
