import Foundation

// Stop battery charging while retaining adapter power. The margin is below
// the target in every backend; battery discharge is never commanded.
public enum ChargeLimitPolicy {
    public static func applies(to version: OperatingSystemVersion) -> Bool {
        version.majorVersion == 15 && version.minorVersion >= 8
    }

    public static func lowerThreshold(target: Int, margin: Int) -> Int {
        target - margin
    }

    public static func shouldHold(percent: Int, target: Int, margin: Int,
                                       wasHolding: Bool, chargeNow: Bool) -> Bool {
        if chargeNow || percent <= lowerThreshold(target: target, margin: margin) { return false }
        if percent >= target { return true }
        return wasHolding
    }
}

public enum ChargeControlError: LocalizedError {
    case commandNotApplied
    case stillCharging
    case recoveryFailed(operation: Error?, recovery: Error)

    public var errorDescription: String? {
        switch self {
        case .commandNotApplied:
            return "The charge-control command did not match its SMC readback."
        case .stillCharging:
            return "The battery still reports charging while charge inhibition is applied."
        case let .recoveryFailed(operation, recovery):
            let context = operation.map { "Operation failed: \($0.localizedDescription). " } ?? ""
            return context + "Normal charging restoration failed: \(recovery.localizedDescription)."
        }
    }
}

/// Keeps the requested state separate from hardware state: a firmware reset
/// must not reset the hysteresis latch. Every apply reads the actual register.
public final class ChargeInhibitionController {
    public private(set) var isHolding = false
    private let read: () throws -> Bool
    private let write: (Bool) throws -> Void
    private let pause: () -> Void
    private var chargingChecks = 0

    public init(read: @escaping () throws -> Bool,
                write: @escaping (Bool) throws -> Void,
                pause: @escaping () -> Void = { Thread.sleep(forTimeInterval: 0.15) }) {
        self.read = read
        self.write = write
        self.pause = pause
    }

    public func readHardwareState() throws -> Bool { try read() }

    @discardableResult
    public func apply(_ enabled: Bool, forceWrite: Bool = false) throws -> Bool {
        for attempt in 0..<3 {
            do {
                var wrote = false
                if try forceWrite || read() != enabled {
                    try write(enabled)
                    wrote = true
                    guard try read() == enabled else {
                        throw ChargeControlError.commandNotApplied
                    }
                }
                if isHolding != enabled { chargingChecks = 0 }
                isHolding = enabled
                return wrote
            } catch {
                if attempt == 2 { throw error }
                pause()
            }
        }
        preconditionFailure("Unreachable retry state")
    }

    // Called before applying the next command so the first snapshot after a
    // transition is allowed to settle. Three subsequent contradictions fail.
    public func checkChargingEvidence(isCharging: Bool) throws {
        chargingChecks = isHolding && isCharging ? chargingChecks + 1 : 0
        if chargingChecks >= 3 { throw ChargeControlError.stillCharging }
    }

    public func restore() throws { _ = try apply(false, forceWrite: true) }

    /// Recovery failures are propagated instead of being swallowed by defer.
    public func withRestoration(_ body: () throws -> Void) throws {
        do {
            try restore()
            try body()
        } catch {
            let operation = error
            do { try restore() }
            catch {
                throw ChargeControlError.recoveryFailed(operation: operation, recovery: error)
            }
            throw operation
        }
        do { try restore() }
        catch { throw ChargeControlError.recoveryFailed(operation: nil, recovery: error) }
    }
}
