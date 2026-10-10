import XCTest

private enum FirmwareTestFailure: Error { case write, battery, recovery }

private final class FirmwareRegisters {
    var values: [FirmwareLimitRegister: UInt32] = [.activation: 0, .upper: 0, .lower: 0]
    var writes: [(FirmwareLimitRegister, UInt32)] = []
    var failUpper = 0
    var ignoreActivation = false
    var rejectRestore = false

    func controller() -> FirmwareLimit {
        FirmwareLimit(read: { self.values[$0]! }, write: { register, value in
            self.writes.append((register, value))
            if register == .activation && value == 0 && self.rejectRestore { throw FirmwareTestFailure.recovery }
            if register == .upper && self.failUpper > 0 {
                self.failUpper -= 1
                throw FirmwareTestFailure.write
            }
            if register == .activation && value == 2 && self.ignoreActivation { return }
            self.values[register] = value
        }, pause: {})
    }
}

final class FirmwareChargeLimitTests: XCTestCase {
    @objc func testPercentagesUseLittleEndianAndActivationUsesOneByte() {
        let upper = FirmwareLimitRegister.upper.encode(80)
        let lower = FirmwareLimitRegister.lower.encode(75)
        XCTAssertEqual([upper.0, upper.1, upper.2, upper.3], [80, 0, 0, 0])
        XCTAssertEqual([lower.0, lower.1, lower.2, lower.3], [75, 0, 0, 0])
        XCTAssertEqual(FirmwareLimitRegister.upper.decode(upper), 80)
        var bytes = SMCParamStruct().bytes
        bytes.3 = 80
        XCTAssertEqual(FirmwareLimitRegister.upper.decode(bytes), 0x50000000)
        XCTAssertEqual(FirmwareLimitRegister.activation.key.info.size, 1)
        XCTAssertEqual(FirmwareLimitRegister.activation.encode(2).0, 2)
    }

    @objc func testEmptyMetadataIsAllowedButPopulatedWrongShapesAreRejected() {
        for register in FirmwareLimitRegister.allCases {
            XCTAssertTrue(register.acceptsMetadata(DataType(type: 0, size: 0)))
            XCTAssertTrue(register.acceptsMetadata(register.key.info))
            XCTAssertFalse(register.acceptsMetadata(DataType(type: 0, size: 2)))
            XCTAssertFalse(register.acceptsMetadata(DataType(type: FourCharCode(fromString: "flt "), size: register.key.info.size)))
        }
    }

    @objc func testEightyFiveProgramsSeventyFiveToEightyInOrder() throws {
        let registers = FirmwareRegisters()
        registers.values = [.activation: 2, .upper: 90, .lower: 70]
        XCTAssertTrue(try registers.controller().apply(target: 80, margin: 5, enabled: true))
        XCTAssertEqual(registers.writes.map { $0.0 }, [.activation, .upper, .lower, .activation])
        XCTAssertEqual(registers.writes.map { $0.1 }, [0, 80, 75, 2])
        XCTAssertEqual(registers.values, [.activation: 2, .upper: 80, .lower: 75])
    }

    @objc func testEveryAcceptedParameterPairProgramsTheRequestedBand() throws {
        for target in 5...95 {
            for margin in 2...30 where target - margin >= 5 {
                let registers = FirmwareRegisters()
                try registers.controller().apply(target: target, margin: margin, enabled: true)
                XCTAssertEqual(registers.values[.upper], UInt32(target))
                XCTAssertEqual(registers.values[.lower], UInt32(target - margin))
            }
        }
    }

    @objc func testUnchangedBandAvoidsWritesAndFirmwareDriftIsCorrected() throws {
        let registers = FirmwareRegisters()
        let controller = registers.controller()
        try controller.apply(target: 80, margin: 5, enabled: true)
        XCTAssertFalse(try controller.apply(target: 80, margin: 5, enabled: true))
        XCTAssertEqual(registers.writes.count, 4)
        registers.values[.lower] = 60
        XCTAssertTrue(try controller.apply(target: 80, margin: 5, enabled: true))
        XCTAssertEqual(registers.values[.lower], 75)
        registers.values[.activation] = 0
        XCTAssertTrue(try controller.apply(target: 80, margin: 5, enabled: true))
        XCTAssertEqual(registers.values[.activation], 2)
    }

    @objc func testPartialWriteDisablesBeforeRetryAndNeverActivatesOldBand() throws {
        let registers = FirmwareRegisters()
        registers.failUpper = 1
        try registers.controller().apply(target: 80, margin: 5, enabled: true)
        XCTAssertEqual(registers.writes.map { $0.0 }, [.activation, .upper, .activation,
                                                     .activation, .upper, .lower, .activation])
        XCTAssertEqual(registers.writes.map { $0.1 }, [0, 80, 0, 0, 80, 75, 2])
    }

    @objc func testPersistentWriteFailureLeavesLimitDisabled() {
        let registers = FirmwareRegisters()
        registers.failUpper = 3
        XCTAssertThrowsError(try registers.controller().apply(target: 80, margin: 5, enabled: true))
        XCTAssertEqual(registers.values[.activation], 0)
        XCTAssertFalse(registers.writes.contains { $0.0 == .activation && $0.1 == 2 })
    }

    @objc func testIgnoredActivationFailsReadbackAndDeactivates() {
        let registers = FirmwareRegisters()
        registers.ignoreActivation = true
        XCTAssertThrowsError(try registers.controller().apply(target: 80, margin: 5, enabled: true))
        XCTAssertEqual(registers.values[.activation], 0)
        XCTAssertEqual(registers.writes.filter { $0.0 == .activation && $0.1 == 2 }.count, 3)
    }

    @objc func testFullChargeOrUnplugReleaseAndThenReapplyTheBand() throws {
        let registers = FirmwareRegisters()
        let controller = registers.controller()
        try controller.apply(target: 80, margin: 5, enabled: true)
        XCTAssertTrue(try controller.apply(target: 80, margin: 5, enabled: false))
        XCTAssertEqual(registers.values[.activation], 0)
        XCTAssertFalse(try controller.apply(target: 80, margin: 5, enabled: false))
        try controller.apply(target: 80, margin: 5, enabled: true)
        XCTAssertEqual(registers.values, [.activation: 2, .upper: 80, .lower: 75])
    }

    @objc func testInvalidBandAndUnknownActivationAreRejectedWithoutWrites() {
        let registers = FirmwareRegisters()
        let controller = registers.controller()
        for (target, margin) in [(80, 0), (80, -1), (80, 80), (101, 5)] {
            XCTAssertThrowsError(try controller.apply(target: target, margin: margin, enabled: true))
        }
        registers.values[.activation] = 1
        XCTAssertThrowsError(try controller.probe())
        XCTAssertTrue(registers.writes.isEmpty)
    }

    @objc func testRestoreWritesDespiteUnavailableInitialReadAndReportsFailures() throws {
        var active: UInt32 = 2
        let controller = FirmwareLimit(read: { _ in
            if active == 2 { throw FirmwareTestFailure.battery }
            return active
        }, write: { _, value in active = value }, pause: {})
        try controller.restore()
        XCTAssertEqual(active, 0)

        let registers = FirmwareRegisters()
        registers.rejectRestore = true
        XCTAssertThrowsError(try registers.controller().restore())
        XCTAssertEqual(registers.writes.count, 3)
    }

    @objc func testPartialWriteWithFailedCleanupReportsBothErrors() {
        let registers = FirmwareRegisters()
        registers.failUpper = 1
        let controller = FirmwareLimit(read: { registers.values[$0]! }, write: { register, value in
            if register == .upper {
                registers.rejectRestore = true
                throw FirmwareTestFailure.write
            }
            if registers.rejectRestore { throw FirmwareTestFailure.recovery }
            registers.values[register] = value
        }, pause: {})
        XCTAssertThrowsError(try controller.apply(target: 80, margin: 5, enabled: true)) { error in
            XCTAssertTrue(error.localizedDescription.contains("restoration failed"))
        }
    }
}

let suite = FirmwareChargeLimitTests.defaultTestSuite
suite.run()
guard let result = suite.testRun, result.executionCount == 12, result.totalFailureCount == 0 else {
    exit(1)
}
