import ArgumentParser
import Foundation
import IOKit.ps
import IOKit.pwr_mgt

var defaultTargetBatteryLevel = 80
var defaultBatteryLevelMargin = 5
var targetBatteryLevelRange = [5, 95]
var targetBatteryMarginRange = [2, 30]
var chargeNowFilePath = "/tmp/bclm_loop.chargeNow"
var chargeNowFileCreationTimeMaxInterval: Int64 = 12
var isFirmwareSupported = false
var isMagSafeSupported = false
var chargeNow = false

var chwa_key = SMCKit.getKey("CHWA", type: DataTypes.UInt8) // Removed in macOS Sequoia.
var ch0b_key = SMCKit.getKey("CH0B", type: DataTypes.UInt8)
var ch0c_key = SMCKit.getKey("CH0C", type: DataTypes.UInt8)
var ch0i_key = SMCKit.getKey("CH0I", type: DataTypes.UInt8)
var chte_key = SMCKit.getKey("CHTE", type: DataTypes.UInt32) // Added in macOS Tahoe.
var ch0j_key = SMCKit.getKey("CH0J", type: DataTypes.UInt8) // Added in macOS Tahoe.
var aclc_key = SMCKit.getKey("ACLC", type: DataTypes.UInt8)

var chwa_bytes_unlimit: SMCBytes = (
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)
var chwa_bytes_limit: SMCBytes = (
    UInt8(1), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)
var chte_bytes_unlimit: SMCBytes = (
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)
var chte_bytes_limit: SMCBytes = (
    UInt8(1), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)
var ch0x_bytes_unlimit: SMCBytes = (
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)
var ch0x_bytes_limit: SMCBytes = (
    UInt8(2), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)
var ch0i_bytes_charge: SMCBytes = (
    UInt8(1), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)
var ch0i_bytes_discharge: SMCBytes = (
    UInt8(1), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)
var ch0j_bytes_charge: SMCBytes = (
    UInt8(1), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)
var ch0j_bytes_discharge: SMCBytes = (
    UInt8(1), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)
var aclc_bytes_green: SMCBytes = (
    UInt8(3), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)
var aclc_bytes_red: SMCBytes = (
    UInt8(4), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)
var aclc_bytes_disable: SMCBytes = (
    UInt8(1), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)
var aclc_bytes_unknown: SMCBytes = (
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
    UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
)

func CheckPermission() throws {
    guard getuid() == 0 else {
        throw ValidationError("Must run as root.")
    }
}

func CheckPlatform() throws {
    #if arch(x86_64)
        throw ValidationError("Only support Apple Silicon.")
    #endif
}

func CheckTargetBatteryLevel(targetBatteryLevel: Int) throws {
    guard targetBatteryLevel >= targetBatteryLevelRange[0] && targetBatteryLevel <= targetBatteryLevelRange[1] else {
        throw ValidationError("Value must be between \(targetBatteryLevelRange[0]) and \(targetBatteryLevelRange[1]).")
    }
}

func CheckTargetBatteryMargin(targetBatteryLevel: Int, targetBatteryMargin: Int) throws {
    guard targetBatteryMargin >= targetBatteryMarginRange[0] && targetBatteryMargin <= targetBatteryMarginRange[1] else {
        throw ValidationError("Value must be between \(targetBatteryMarginRange[0]) and \(targetBatteryMarginRange[1]).")
    }

    guard (targetBatteryLevel - targetBatteryMargin) >= targetBatteryLevelRange[0] else {
        throw ValidationError("The value (\(targetBatteryLevel)-\(targetBatteryMargin)) must be greater than or equal to \(targetBatteryLevelRange[0]).")
    }
}

func GetCurrentTimestamp() -> Int64 {
    return Int64(ceil(Date().timeIntervalSince1970))
}

func CheckChargeNowFile() -> Bool {
    do {
        let chargeNowFileContent = try String(contentsOfFile: chargeNowFilePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        try FileManager.default.removeItem(atPath: chargeNowFilePath)

        let chargeNowFileCreationTimestamp = Int64(chargeNowFileContent)
        let currentTimestamp = GetCurrentTimestamp()
        if chargeNowFileCreationTimestamp != nil && (chargeNowFileCreationTimestamp! + chargeNowFileCreationTimeMaxInterval) >= currentTimestamp {
            return true
        }
        
        print("Bad chargeNow file content. (chargeNowFileContent: \(chargeNowFileContent), chargeNowFileCreationTimestamp: \(chargeNowFileCreationTimestamp != nil ? String(chargeNowFileCreationTimestamp!) : "nil"), currentTimestamp: \(String(currentTimestamp)))")
    } catch {
        let realError = error as NSError
        if realError.code != NSFileReadNoSuchFileError {
            print(realError.localizedDescription)
        }
    }

    return false
}

func SetChargeNowFile(status: Bool) -> Bool {
    try? FileManager.default.removeItem(atPath: chargeNowFilePath)

    if !status || FileManager.default.createFile(atPath: chargeNowFilePath, contents: String(GetCurrentTimestamp()).data(using: .utf8)) {
        return true
    }
    
    return false
}

func AllowChargeNow(status: Bool) -> Bool {
    if !chargeNow && status {
        chargeNow = true
    } else if chargeNow && !status {
        chargeNow = false
    } else {
        return false
    }
    
    return true
}

struct BCLMLoop: ParsableCommand {
    static let configuration = CommandConfiguration(
            commandName: "bclm_loop",
            abstract: "Battery Charge Level Max Loop (BCLM_Loop) Utility.",
            version: "1.0b7",
            subcommands: [Loop.self, ChargeNow.self, Persist.self, Unpersist.self])

    struct Loop: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Loop bclm on target battery level. (Default: \(defaultTargetBatteryLevel)%)")
        
        @Argument(help: "The value to set (\(targetBatteryLevelRange[0])-\(targetBatteryLevelRange[1])). Firmware-based battery level limits are not supported if not set to \(defaultTargetBatteryLevel).")
        var targetBatteryLevel: Int = defaultTargetBatteryLevel

        @Argument(help: "The value to set (\(targetBatteryMarginRange[0])-\(targetBatteryMarginRange[1])). Firmware-based battery level limits are not supported if not set to \(defaultBatteryLevelMargin).")
        var targetBatteryMargin: Int = defaultBatteryLevelMargin

        func validate() throws {
            try CheckPermission()
            try CheckPlatform()
            try CheckTargetBatteryLevel(targetBatteryLevel: targetBatteryLevel)
            try CheckTargetBatteryMargin(targetBatteryLevel: targetBatteryLevel, targetBatteryMargin: targetBatteryMargin)
        }

        func CheckFirmwareSupport() -> Bool {
            if targetBatteryLevel != defaultTargetBatteryLevel || targetBatteryMargin != defaultBatteryLevelMargin {
                return false
            }

            if #available(macOS 15, *) {
                return false
            }

            do {
                _ = try SMCKit.readData(chwa_key)
            } catch {
                return false
            }

            return true
        }

        func CheckMagSafeSupport() -> Bool {
            do {
                _ = try SMCKit.readData(aclc_key)
            } catch {
                return false
            }

            return true
        }

        func AllowCharging(status: Bool) throws {
            if isFirmwareSupported {
                if status {
                    try SMCKit.writeData(chwa_key, data: chwa_bytes_unlimit)
                } else {
                    try SMCKit.writeData(chwa_key, data: chwa_bytes_limit)
                }
            } else {
                if #available(macOS 15.7, *) {
                    if status {
                        try SMCKit.writeData(chte_key, data: chte_bytes_unlimit)
                    } else {
                        try SMCKit.writeData(chte_key, data: chte_bytes_limit)
                    }
                } else {
                    if status {
                        try SMCKit.writeData(ch0b_key, data: ch0x_bytes_unlimit)
                        try SMCKit.writeData(ch0c_key, data: ch0x_bytes_unlimit)
                    } else {
                        try SMCKit.writeData(ch0b_key, data: ch0x_bytes_limit)
                        try SMCKit.writeData(ch0c_key, data: ch0x_bytes_limit)
                    }
                }
            }
        }

        func ForceDischarging(status: Bool) throws {
            if isFirmwareSupported {
                return
            }
            
            if #available(macOS 15.7, *) {
                if status {
                    try SMCKit.writeData(ch0j_key, data: ch0j_bytes_discharge)
                } else {
                    try SMCKit.writeData(ch0j_key, data: ch0j_bytes_charge)
                }
            } else {
                if status {
                    try SMCKit.writeData(ch0i_key, data: ch0i_bytes_discharge)
                } else {
                    try SMCKit.writeData(ch0i_key, data: ch0i_bytes_charge)
                }
            }
        }
        
        func ChangeMagSafeLED(color: String) throws {
            if !isMagSafeSupported {
                return
            }
            
            switch color {
            case "Green":
                try SMCKit.writeData(aclc_key, data: aclc_bytes_green)
                break
            case "Red":
                try SMCKit.writeData(aclc_key, data: aclc_bytes_red)
                break
            case "Disable":
                try SMCKit.writeData(aclc_key, data: aclc_bytes_disable)
                break
            case "Unknown": fallthrough
            default:
                try SMCKit.writeData(aclc_key, data: aclc_bytes_unknown)
                break
            }
        }
        
        func run() {
            print("bclm_loop has started...")

            var pmStatus : IOReturn? = nil
            var assertionID = IOPMAssertionID(0)
            let reasonForActivity = "bclm_loop - Prevent sleep before charging limit is reached."
            let maxTryCount = 3
            var lastLimit = false
            var lastLimitCheckCount = 0
            var lastACPower : Bool? = nil
            var lastCharging : Bool? = nil
            var lastChargingCheckCount = 0
            
            if CheckFirmwareSupport() {
                isFirmwareSupported = true
                print("Use firmware-based battery level limits.")
            } else {
                isFirmwareSupported = false
                print("Use software-based battery level limits.")
            }
            
            if CheckMagSafeSupport() {
                isMagSafeSupported = true
                print("Enabled MagSafe control.")
            } else {
                isMagSafeSupported = false
                print("Disabled MagSafe control.")
            }
            
            signal(SIGUSR1) { _ in
                _ = AllowChargeNow(status: true)
                print("Received SIGUSR1 signal, enabled chargeNow.")
            }

            while true {
                let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
                let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
                let chargeState = sources[0]["Power Source State"] as? String
                let isACPower : Bool? = (chargeState == "AC Power") ? true : (chargeState == "Battery Power" ? false : nil)
                let isCharging = sources[0]["Is Charging"] as? Bool
                let currentBattLevelInt = Int((sources[0]["Current Capacity"] as? Int) ?? -1)
                //let maxBattLevelInt = Int((sources[0]["Max Capacity"] as? Int) ?? -1)

                // Avoid failure by repeating maxTryCount times, and avoid opening SMC each time to affect performance.
                var needLimit = true

                if chargeState != nil && currentBattLevelInt >= 0 {
                    if isACPower == true {
                        if CheckChargeNowFile() {
                            _ = AllowChargeNow(status: true)
                            print("Detect chargeNow file, enabled chargeNow.")
                        }
                        // If already in battery level limit, some margin (targetBatteryMargin) is required to release the battery level limit.
                        if chargeNow || (!lastLimit && currentBattLevelInt < targetBatteryLevel) || (lastLimit && currentBattLevelInt < (targetBatteryLevel - targetBatteryMargin)) {
                            needLimit = false
                        }
                    } else if chargeNow {
                        _ = AllowChargeNow(status: false)
                        print("AC power is disconnected, disabled chargeNow.")
                    }
                }
                if lastLimit != needLimit {
                    print("Limit status will be changed. (Current: \(String(needLimit)), Last: \(String(lastLimit)))")

                    lastLimit = needLimit
                    lastLimitCheckCount = 1
                } else {
                    lastLimitCheckCount += 1
                }

                if isACPower != nil && lastACPower != isACPower {
                    lastACPower = isACPower
                    lastCharging = nil
                }

                if lastCharging != isCharging {
                    var isChargingStr = "nil"
                    if isCharging != nil {
                        isChargingStr = String(isCharging!)
                    }
                    var lastChargingStr = "nil"
                    if lastCharging != nil {
                        lastChargingStr = String(lastCharging!)
                    }
                    print("Charging status has changed! (Current: \(isChargingStr), Last: \(lastChargingStr))")
                    
                    lastCharging = isCharging
                    lastChargingCheckCount = 1
                } else if isCharging != nil {
                    lastChargingCheckCount += 1
                }

                // If each function has been repeated maxTryCount times, skip check.
                if lastLimitCheckCount <= maxTryCount || lastChargingCheckCount <= maxTryCount {
                    do {
                        try SMCKit.open()
                        print("SMC has opened!")
                        
                        // Change charging status (If current charging status is known).
                        if needLimit == true  {
                            try AllowCharging(status: false)
                            //try ForceDischarging(status: true)
                            print("Limit status has changed! (Limit)")
                            
                            // A: The battery is "full", sleep will no longer be prevented (If currently prevented).
                            // B: No charger connected, sleep will no longer be prevented (If currently prevented), but charging is limited by default to prevent charging to 100% when disconnected from charger and sleeping.
                            if pmStatus != nil && IOPMAssertionRelease(assertionID) == kIOReturnSuccess {
                                pmStatus = nil
                                assertionID = IOPMAssertionID(0)
                            }
                        } else if needLimit == false {
                            try AllowCharging(status: true)
                            //try ForceDischarging(status: false)
                            print("Limit status has changed! (Unlimit)")
                            
                            // The battery is not "full", sleep will be prevented (If not currently prevented).
                            if pmStatus == nil {
                                pmStatus = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString, UInt32(kIOPMAssertionLevelOn), reasonForActivity as CFString, &assertionID)
                                if pmStatus != kIOReturnSuccess {
                                    pmStatus = nil
                                    assertionID = IOPMAssertionID(0)
                                    print("Failed to prevent sleep.")
                                }
                            }
                        }
                        
                        // Change MagSafe LED status.
                        if isMagSafeSupported {
                            if isCharging == false {
                                try ChangeMagSafeLED(color: "Green")
                                print("MagSafe LED status has changed! (Full)")
                            } else if isCharging == true {
                                try ChangeMagSafeLED(color: "Red")
                                print("MagSafe LED status has changed! (Charging)")
                            } else {
                                try ChangeMagSafeLED(color: "Unknown")
                                print("MagSafe LED status has changed! (Unknown)")
                            }
                        }
                        
                        SMCKit.close()
                        print("SMC has closed!")
                    } catch {
                        print(error)
                    }
                }

                sleep(2)
            }
        }
    }

    struct ChargeNow: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "chargeNow",
            abstract: "Send a command to bclm_loop to fully charge now. (Only available if bclm_loop is running and currently charging)")

        func validate() throws {
            try CheckPlatform()
        }

        func run() {
            if SetChargeNowFile(status: true) {
                print("The command has been sent. If bclm_loop is running and currently charging, it should respond quickly.")
            }
        }
    }

    struct Persist: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Persists bclm loop service.")
        
        @Argument(help: "The value to set (\(targetBatteryLevelRange[0])-\(targetBatteryLevelRange[1])). Firmware-based battery level limits are not supported if not set to \(defaultTargetBatteryLevel).")
        var targetBatteryLevel: Int = defaultTargetBatteryLevel
    
        @Argument(help: "The value to set (\(targetBatteryMarginRange[0])-\(targetBatteryMarginRange[1])). Firmware-based battery level limits are not supported if not set to \(defaultBatteryLevelMargin).")
        var targetBatteryMargin: Int = defaultBatteryLevelMargin

        func validate() throws {
            try CheckPermission()
            try CheckPlatform()
            try CheckTargetBatteryLevel(targetBatteryLevel: targetBatteryLevel)
            try CheckTargetBatteryMargin(targetBatteryLevel: targetBatteryLevel, targetBatteryMargin: targetBatteryMargin)
        }

        func run() {
            if persist(false) {
                print("Already persisting! Re-persist...\n")
                _ = removePlist()
            }

            if updatePlist(targetBatteryLevel: targetBatteryLevel, targetBatteryMargin: targetBatteryMargin) && persist(true) {
                print("Success!")
            }
        }
    }

    struct Unpersist: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Unpersists bclm loop service.")

        func validate() throws {
            try CheckPermission()
            try CheckPlatform()
        }

        func run() {
            if !persist(false) {
                fputs("Already not persisting!\n", stderr)
            }

            if removePlist() {
                print("Success!")
            }
        }
    }
}

BCLMLoop.main()
