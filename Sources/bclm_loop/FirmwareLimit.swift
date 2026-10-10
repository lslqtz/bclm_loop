import Foundation

private struct FirmwareLimitError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// The bf* firmware interface uses little-endian percentages and a one-byte
// activation value. Known-size reads also work when key metadata is empty.
enum FirmwareLimitRegister: String, CaseIterable {
    case activation = "bfF0", upper = "bfD0", lower = "bfE0"
    var key: SMCKey { SMCKit.getKey(rawValue, type: self == .activation ? DataTypes.UInt8 : DataTypes.UInt32) }

    func acceptsMetadata(_ info: DataType) -> Bool { info.size == 0 || info == key.info }

    func decode(_ bytes: SMCBytes) -> UInt32 {
        if self == .activation { return UInt32(bytes.0) }
        return UInt32(bytes.0) | UInt32(bytes.1) << 8 | UInt32(bytes.2) << 16 | UInt32(bytes.3) << 24
    }

    func encode(_ value: UInt32) -> SMCBytes {
        var bytes = SMCParamStruct().bytes
        bytes.0 = UInt8(truncatingIfNeeded: value)
        if self != .activation {
            bytes.1 = UInt8(truncatingIfNeeded: value >> 8)
            bytes.2 = UInt8(truncatingIfNeeded: value >> 16)
            bytes.3 = UInt8(truncatingIfNeeded: value >> 24)
        }
        return bytes
    }
}

final class FirmwareLimit {
    private let read: (FirmwareLimitRegister) throws -> UInt32
    private let write: (FirmwareLimitRegister, UInt32) throws -> Void
    private let pause: () -> Void

    init(read: @escaping (FirmwareLimitRegister) throws -> UInt32 = { register in
        register.decode(try SMCKit.readData(register.key))
    }, write: @escaping (FirmwareLimitRegister, UInt32) throws -> Void = { register, value in
        try SMCKit.writeData(register.key, data: register.encode(value))
    }, pause: @escaping () -> Void = { Thread.sleep(forTimeInterval: 0.15) }) {
        self.read = read; self.write = write; self.pause = pause
    }

    func probe() throws {
        let activation = try read(.activation)
        guard activation == 0 || activation == 2 else {
            throw FirmwareLimitError("Unexpected bfF0 activation value: \(activation).")
        }
        _ = try read(.upper); _ = try read(.lower)
    }

    private func writeVerified(_ register: FirmwareLimitRegister, _ value: UInt32) throws {
        try write(register, value)
        guard try read(register) == value else {
            throw FirmwareLimitError("SMC readback did not match the write to \(register.rawValue).")
        }
    }

    func restore() throws {
        for attempt in 0..<3 {
            do { try writeVerified(.activation, 0); return }
            catch {
                if attempt == 2 { throw error }
                pause()
            }
        }
    }

    @discardableResult
    func apply(target: Int, margin: Int, enabled: Bool) throws -> Bool {
        guard (1...100).contains(target), margin > 0, margin < target else {
            throw FirmwareLimitError("Firmware limits must satisfy 1 <= lower < upper <= 100.")
        }
        if !enabled {
            if try read(.activation) == 0 { return false }
            try restore()
            return true
        }
        let upper = UInt32(target), lower = UInt32(target - margin)
        for attempt in 0..<3 {
            do {
                if try read(.activation) == 2 && read(.upper) == upper && read(.lower) == lower { return false }
                // Always deactivate before changing either threshold.
                try writeVerified(.activation, 0)
                try writeVerified(.upper, upper)
                try writeVerified(.lower, lower)
                try writeVerified(.activation, 2)
                guard try read(.activation) == 2 && read(.upper) == upper && read(.lower) == lower else {
                    throw FirmwareLimitError("Firmware charging limits changed during verification.")
                }
                return true
            } catch {
                let operation = error
                do { try restore() }
                catch {
                    throw FirmwareLimitError("\(operation.localizedDescription) Firmware limit restoration failed: \(error.localizedDescription)")
                }
                if attempt == 2 { throw operation }
                pause()
            }
        }
        preconditionFailure("Unreachable retry state")
    }
}
