import XCTest
@testable import ChargeControlCore

private enum TestFailure: Error { case io, batteryRead, recovery }

private final class Register {
    var enabled = false // charging inhibited; adapter power is retained
    var writes: [Bool] = []
    var reads = 0
    var failuresRemaining = 0
    var ignoresPause = false
    var rejectsRestore = false

    func makeController() -> ChargeInhibitionController {
        ChargeInhibitionController(read: {
            self.reads += 1
            return self.enabled
        }, write: { enabled in
            self.writes.append(enabled)
            if self.failuresRemaining > 0 {
                self.failuresRemaining -= 1
                throw TestFailure.io
            }
            if !enabled && self.rejectsRestore { throw TestFailure.recovery }
            if !enabled || !self.ignoresPause { self.enabled = enabled }
        }, pause: {})
    }
}

final class ChargeControlTests: XCTestCase {
    func testStartingAboveTargetOnlyPausesCharging() throws {
        let register = Register()
        let controller = register.makeController()
        var percent = 95
        for _ in 0..<20 {
            try controller.apply(ChargeLimitPolicy.shouldHold(
                percent: percent, target: 80, margin: 5,
                wasHolding: controller.isHolding, chargeNow: false))
            if !register.enabled { percent += 1 } // adapter supplies system power
            XCTAssertEqual(percent, 95)
            XCTAssertTrue(register.enabled)
        }
        // Holding above the upper bound never commands a lower battery level.
        XCTAssertEqual(register.writes, [true])
        XCTAssertEqual(percent, 95)
    }

    func testHoldingAtEightyDoesNotDrainTheBattery() throws {
        let register = Register()
        let controller = register.makeController()
        var percent = 79
        for _ in 0..<20 {
            let hold = ChargeLimitPolicy.shouldHold(percent: percent, target: 80, margin: 5,
                                                    wasHolding: controller.isHolding, chargeNow: false)
            try controller.apply(hold)
            // Model adapter-powered operation: pausing charge keeps the level
            // stable. Natural depletion must be an external event, not a command.
            if !register.enabled { percent += 1 }
            XCTAssertLessThanOrEqual(percent, 80)
        }
        XCTAssertEqual(percent, 80)
        XCTAssertTrue(controller.isHolding)
        for level in [79, 78, 77, 76] { // natural drift stays in the hold phase
            try controller.apply(ChargeLimitPolicy.shouldHold(percent: level, target: 80, margin: 5,
                                                               wasHolding: controller.isHolding, chargeNow: false))
            XCTAssertTrue(register.enabled)
        }
        try controller.apply(ChargeLimitPolicy.shouldHold(percent: 75, target: 80, margin: 5,
                                                           wasHolding: controller.isHolding, chargeNow: false))
        XCTAssertFalse(register.enabled)
    }

    func testVersionBoundaries() {
        for (major, minor, patch, supported) in [
            (14, 8, 1, false), (15, 7, 9, false), (15, 8, 0, true),
            (15, 8, 1, true), (15, 9, 0, true), (16, 0, 0, false),
            (26, 0, 0, false), (26, 4, 0, false), (27, 0, 0, false)
        ] {
            XCTAssertEqual(ChargeLimitPolicy.applies(to: OperatingSystemVersion(
                majorVersion: major, minorVersion: minor, patchVersion: patch)), supported)
        }
    }

    func testFullCycleUsesInclusiveBoundariesAndRetainsTheLatch() {
        var holding = false
        for (percent, expected) in [(74, false), (75, false), (79, false),
                                    (80, true), (79, true), (76, true), (75, false)] {
            holding = ChargeLimitPolicy.shouldHold(
                percent: percent, target: 80, margin: 5,
                wasHolding: holding, chargeNow: false)
            XCTAssertEqual(holding, expected, "percentage \(percent)")
        }
    }

    func testEveryAcceptedParameterPairUsesTargetAsUpperBound() {
        for target in 5...95 {
            for margin in 2...30 where target - margin >= 5 {
                let lower = target - margin
                XCTAssertTrue(ChargeLimitPolicy.shouldHold(
                    percent: target, target: target, margin: margin,
                    wasHolding: false, chargeNow: false), "\(target)/\(margin)")
                XCTAssertFalse(ChargeLimitPolicy.shouldHold(
                    percent: lower, target: target, margin: margin,
                    wasHolding: true, chargeNow: false), "\(target)/\(margin)")
                for percent in (lower + 1)..<target {
                    for latch in [false, true] {
                        XCTAssertEqual(ChargeLimitPolicy.shouldHold(
                            percent: percent, target: target, margin: margin,
                            wasHolding: latch, chargeNow: false), latch)
                    }
                }
            }
        }
    }

    func testFullChargeOverrideAllowsChargingRegardlessOfLatch() throws {
        for percent in 0...100 {
            for latch in [false, true] {
                XCTAssertFalse(ChargeLimitPolicy.shouldHold(
                    percent: percent, target: 80, margin: 5,
                    wasHolding: latch, chargeNow: true))
            }
        }
        let register = Register()
        let controller = register.makeController()
        try controller.apply(true)
        let next = ChargeLimitPolicy.shouldHold(
            percent: 90, target: 80, margin: 5,
            wasHolding: controller.isHolding, chargeNow: true)
        try controller.apply(next)
        XCTAssertFalse(register.enabled)
    }

    func testUnchangedIntentStillReadsHardwareButAvoidsRedundantWrites() throws {
        let register = Register()
        let controller = register.makeController()
        try controller.apply(true)
        let before = register.reads
        XCTAssertFalse(try controller.apply(true))
        XCTAssertEqual(register.reads, before + 1)
        XCTAssertEqual(register.writes, [true])
    }

    func testFirmwareResetIsCorrectedInsideTheHysteresisBand() throws {
        let register = Register()
        let controller = register.makeController()
        try controller.apply(true)
        register.enabled = false // firmware or another controller cleared it
        let next = ChargeLimitPolicy.shouldHold(
            percent: 77, target: 80, margin: 5,
            wasHolding: controller.isHolding, chargeNow: false)
        XCTAssertTrue(next)
        XCTAssertTrue(try controller.apply(next))
        XCTAssertTrue(register.enabled)
        XCTAssertEqual(register.writes, [true, true])
    }

    func testWriteFailureRetriesAndOnlyThenUpdatesIntent() throws {
        let register = Register()
        register.failuresRemaining = 2
        let controller = register.makeController()
        try controller.apply(true)
        XCTAssertEqual(register.writes, [true, true, true])
        XCTAssertTrue(controller.isHolding)
    }

    func testIgnoredPauseWriteFailsVerification() {
        let register = Register()
        register.ignoresPause = true
        let controller = register.makeController()
        XCTAssertThrowsError(try controller.apply(true))
        XCTAssertEqual(register.writes, [true, true, true])
        XCTAssertFalse(controller.isHolding)
    }

    func testBatteryReadFailureRestoresChargingAndStillThrows() {
        let register = Register()
        register.enabled = true // state left behind by a previous process
        let controller = register.makeController()
        XCTAssertThrowsError(try controller.withRestoration {
            XCTAssertFalse(register.enabled) // startup recovery ran first
            try controller.apply(true)
            throw TestFailure.batteryRead
        }) { error in
            guard case TestFailure.batteryRead = error else {
                return XCTFail("Original battery-read error was lost: \(error)")
            }
        }
        XCTAssertFalse(register.enabled)
        XCTAssertEqual(register.writes, [false, true, false])
    }

    func testFailedPauseIsRestoredBeforePropagatingError() {
        let register = Register()
        register.ignoresPause = true
        let controller = register.makeController()
        XCTAssertThrowsError(try controller.withRestoration { try controller.apply(true) })
        XCTAssertEqual(register.writes, [false, true, true, true, false])
        XCTAssertFalse(register.enabled)
    }

    func testNormalTerminationRestoresCharging() throws {
        let register = Register()
        let controller = register.makeController()
        try controller.withRestoration { try controller.apply(true) }
        XCTAssertFalse(register.enabled)
        XCTAssertFalse(controller.isHolding)
        XCTAssertEqual(register.writes, [false, true, false])
    }

    func testRecoveryRetryWritesEvenWhenReadIsUnavailable() throws {
        var writes = 0
        let controller = ChargeInhibitionController(read: {
            if writes < 3 { throw TestFailure.io }
            return false
        }, write: { _ in writes += 1 }, pause: {})
        try controller.restore()
        XCTAssertEqual(writes, 3)
    }

    func testRecoveryFailureIsReportedAlongsideTheOriginalError() {
        let register = Register()
        let controller = register.makeController()
        XCTAssertThrowsError(try controller.withRestoration {
            try controller.apply(true)
            register.rejectsRestore = true
            throw TestFailure.batteryRead
        }) { error in
            guard case ChargeControlError.recoveryFailed(let operation, let recovery) = error,
                  case TestFailure.batteryRead? = operation,
                  case TestFailure.recovery = recovery else {
                return XCTFail("Both failure causes must be retained: \(error)")
            }
        }
        XCTAssertEqual(register.writes.suffix(3), [false, false, false])
        XCTAssertTrue(register.enabled)
    }

    func testCleanupFailureAfterNormalTerminationDoesNotReturnSuccess() {
        let register = Register()
        let controller = register.makeController()
        XCTAssertThrowsError(try controller.withRestoration {
            try controller.apply(true)
            register.rejectsRestore = true
        }) { error in
            guard case ChargeControlError.recoveryFailed(nil, _) = error else {
                return XCTFail("Cleanup error was swallowed")
            }
        }
    }

    func testPersistentChargingContradictionRestoresChargingAndThrows() {
        let register = Register()
        let controller = register.makeController()
        XCTAssertThrowsError(try controller.withRestoration {
            try controller.apply(true)
            try controller.checkChargingEvidence(isCharging: true)
            try controller.checkChargingEvidence(isCharging: true)
            try controller.checkChargingEvidence(isCharging: true)
        }) { error in
            guard case ChargeControlError.stillCharging = error else {
                return XCTFail("Expected physical-state contradiction error")
            }
        }
        XCTAssertFalse(register.enabled)
    }

    func testChargingEvidenceCounterResetsAfterAConsistentSnapshot() throws {
        let controller = Register().makeController()
        try controller.apply(true)
        try controller.checkChargingEvidence(isCharging: true)
        try controller.checkChargingEvidence(isCharging: true)
        try controller.checkChargingEvidence(isCharging: false)
        XCTAssertNoThrow(try controller.checkChargingEvidence(isCharging: true))
    }
}
