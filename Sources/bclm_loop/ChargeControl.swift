import Foundation
import ArgumentParser
import IOKit
import Darwin
import Dispatch
import ChargeControlCore
import CPowerUIBridge

private final class ChargeRequests {
    private let lock = NSLock()
    private let wake = DispatchSemaphore(value: 0)
    private var stopping = false
    private var fullCharge = false
    var shouldStop: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopping
    }
    func receive(_ number: Int32) {
        lock.lock()
        if number == SIGUSR1 { fullCharge = true } else { stopping = true }
        lock.unlock()
        wake.signal()
    }
    func consumeFullChargeRequest() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let requested = fullCharge
        fullCharge = false
        return requested
    }
    func waitForPoll() { _ = wake.wait(timeout: .now() + 2) }
}

func acquireSequoiaControlLock() throws -> Int32 {
    let descriptor = open("/var/run/bclm_loop.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw ValidationError("Cannot open the bclm_loop control lock.") }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_uid == 0,
          info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o022 == 0 else {
        close(descriptor)
        throw ValidationError("The bclm_loop control lock is not a safe root-owned file.")
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
        close(descriptor)
        throw ValidationError("Another bclm_loop instance already controls charging.")
    }
    return descriptor
}

// Recover an override left by the earlier PowerUI implementation. New
// engagement is forbidden: 15.8 OBC requests chargeSocLimitDrain=1.
private func recoverPreviousNativeOverride() throws {
    let path = "/var/db/bclm_loop.powerui-owner"
    let marker = Data("bclm_loop PowerUI OBC v1\n".utf8)
    var info = stat()
    if lstat(path, &info) != 0 {
        guard errno == ENOENT else { throw ValidationError("Cannot inspect the PowerUI ownership journal.") }
        return
    }
    guard info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG,
          info.st_mode & 0o077 == 0,
          try Data(contentsOf: URL(fileURLWithPath: path)) == marker else {
        throw ValidationError("Invalid PowerUI ownership journal; charging was not changed.")
    }
    for attempt in 0..<3 {
        if BCLMPowerUIRelease() {
            guard unlink(path) == 0 || errno == ENOENT else {
                throw ValidationError("Cannot clear the PowerUI ownership journal.")
            }
            return
        }
        if attempt < 2 { Thread.sleep(forTimeInterval: 0.15) }
    }
    throw ValidationError("The previous PowerUI override could not be released; the ownership journal was retained.")
}

private func readInhibitState(_ keys: [SMCKey]) throws -> Bool {
    var inhibited = false
    for key in keys {
        let bytes = try SMCKit.readData(key)
        inhibited = inhibited || bytes.0 != 0 ||
            (key.info.size == 4 && (bytes.1 != 0 || bytes.2 != 0 || bytes.3 != 0))
    }
    return inhibited
}

private func makeSMCInhibitController() throws -> ChargeInhibitionController? {
    for keys in [[chte_key], [ch0b_key, ch0c_key]] {
        var present = true
        for key in keys {
            if !(try SMCKit.isKeyFound(key.code)) { present = false; break }
            let information = try SMCKit.keyInformation(key.code)
            // These legacy keys can remain as zero-size placeholders after a
            // firmware update; their names alone do not prove charge control.
            if information.size == 0 { present = false; break }
            guard information == key.info else {
                throw ValidationError("Unexpected charge-inhibit key size.")
            }
        }
        if !present { continue }
        let controller = ChargeInhibitionController(read: { try readInhibitState(keys) }, write: { holding in
            let bytes = !holding ? ch0x_bytes_unlimit : (keys.count == 1 ? chte_bytes_limit : ch0x_bytes_limit)
            for key in keys { try SMCKit.writeData(key, data: bytes) }
        })
        do { try controller.restore(); return controller }
        catch {
            guard (try? controller.readHardwareState()) == false else {
                throw ChargeControlError.recoveryFailed(operation: nil, recovery: error)
            }
            fputs("Charge-inhibit commands are unavailable: \(error)\n", stderr)
        }
    }
    return nil
}

private struct ChargeSnapshot {
    let percent: Int
    let fullyCharged: Bool
    let isCharging: Bool
    let adapterConnected: Bool
}

private func readChargeSnapshot() throws -> ChargeSnapshot {
    let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { throw ValidationError("Battery service unavailable.") }
    defer { IOObjectRelease(service) }
    var properties: Unmanaged<CFMutableDictionary>?
    let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
    let values = properties?.takeRetainedValue() as? [String: Any]
    guard result == KERN_SUCCESS, let battery = values,
          let percent = battery["CurrentCapacity"] as? Int,
          let charging = battery["IsCharging"] as? Bool,
          let connected = battery["ExternalConnected"] as? Bool,
          (0...100).contains(percent) else {
        throw ValidationError("Battery state unavailable; restoring normal charging.")
    }
    return ChargeSnapshot(percent: percent, fullyCharged: (battery["FullyCharged"] as? Bool) == true,
                          isCharging: charging, adapterConnected: connected)
}

func runSequoiaChargeControl(target: Int, margin: Int) throws {
    try recoverPreviousNativeOverride()
    try SMCKit.open()
    defer { SMCKit.close() }
    guard let controller = try makeSMCInhibitController() else {
        throw ValidationError("No verified charge-inhibit interface is available on this Mac. Native PowerUI requests battery draining and cannot implement passive target/margin control.")
    }

    let requests = ChargeRequests()
    let oldTerm = signal(SIGTERM, SIG_IGN)
    let oldInt = signal(SIGINT, SIG_IGN)
    let oldUser = signal(SIGUSR1, SIG_IGN)
    let signalQueue = DispatchQueue(label: "bclm_loop.charge-signals")
    let sources = [SIGTERM, SIGINT, SIGUSR1].map { number -> DispatchSourceSignal in
        let source = DispatchSource.makeSignalSource(signal: number, queue: signalQueue)
        source.setEventHandler { requests.receive(number) }
        source.resume()
        return source
    }
    defer {
        for source in sources { source.cancel() }
        signal(SIGTERM, oldTerm); signal(SIGINT, oldInt); signal(SIGUSR1, oldUser)
    }

    try controller.withRestoration {
        var fullCharge = false
        let lower = ChargeLimitPolicy.lowerThreshold(target: target, margin: margin)
        print("Maintaining \(lower)%–\(target)% using SMC charge inhibition.")
        while !requests.shouldStop {
            let battery = try readChargeSnapshot()
            if !battery.adapterConnected {
                fullCharge = false
                try controller.restore()
                requests.waitForPoll()
                continue
            }
            if CheckChargeNowFile() || requests.consumeFullChargeRequest() { fullCharge = true }
            if battery.percent >= 100 || battery.fullyCharged { fullCharge = false }
            let next = ChargeLimitPolicy.shouldHold(percent: battery.percent, target: target, margin: margin,
                                                    wasHolding: controller.isHolding, chargeNow: fullCharge)
            if next && controller.isHolding {
                try controller.checkChargingEvidence(isCharging: battery.isCharging)
            }
            if requests.shouldStop { break }
            let changed = next != controller.isHolding
            let wrote = try controller.apply(next)
            if changed || wrote {
                print("Battery \(battery.percent)%: \(next ? "charging paused; adapter remains connected" : "charging allowed")\(changed ? "" : " (state corrected)").")
            }
            requests.waitForPoll()
        }
    }
}
