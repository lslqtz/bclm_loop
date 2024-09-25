import ArgumentParser
import Foundation
import IOKit.ps
import IOKit.pwr_mgt

var defaultTargetBatteryLevel = 80
var defaultBatteryLevelMargin = 5
var targetBatteryLevelRange = [5, 95]
var targetBatteryMarginRange = [2, 30]
var chwaExist = false

var chwa_key = SMCKit.getKey("CHWA", type: DataTypes.UInt8)
var ch0b_key = SMCKit.getKey("CH0B", type: DataTypes.UInt8)
var ch0c_key = SMCKit.getKey("CH0C", type: DataTypes.UInt8)
var ch0i_key = SMCKit.getKey("CH0I", type: DataTypes.UInt8)
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

struct BCLMLoop: ParsableCommand {
    static let configuration = CommandConfiguration(
            commandName: "bclm_loop",
            abstract: "Battery Charge Level Max (BCLM) Utility.",
            version: "1.0",
            subcommands: [Loop.self, Persist.self, Unpersist.self])

    struct Loop: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Loop bclm on target battery level (Default: \(defaultTargetBatteryLevel)%).")
        
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

            do {
                _ = try SMCKit.readData(chwa_key)
            } catch {
                print("SMCKey \"CHWA\" not found.")
                return false
            }

            return true
        }

        func AllowCharging(status: Bool) throws {
            if chwaExist {
                if status {
                    try SMCKit.writeData(chwa_key, data: chwa_bytes_unlimit)
                } else {
                    try SMCKit.writeData(chwa_key, data: chwa_bytes_limit)
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

        func ForceDischarging(status: Bool) throws {
            if chwaExist {
                return
            }

            if status {
                try SMCKit.writeData(ch0i_key, data: ch0i_bytes_discharge)
            } else {
                try SMCKit.writeData(ch0i_key, data: ch0i_bytes_charge)
            }
        }
        
        func ChangeMagSafeLED(color: String) throws {
            switch color {
            case "Green":
                try SMCKit.writeData(aclc_key, data: aclc_bytes_green)
                break
            case "Red":
                try SMCKit.writeData(aclc_key, data: aclc_bytes_red)
                break
            case "Unknown": fallthrough
            default:
                try SMCKit.writeData(aclc_key, data: aclc_bytes_unknown)
                break
            }
        }
        
        func run() {
            if CheckFirmwareSupport() {
                chwaExist = true
                print("Use firmware-based battery level limits.")
            } else {
                chwaExist = false
                print("Use software-based battery level limits.")
            }

            var pmStatus : IOReturn? = nil
            var assertionID : IOPMAssertionID = IOPMAssertionID(0)
            let reasonForActivity = "bclm_loop - Prevent sleep before charging limit is reached."
            let maxTryCount = 3
            var lastLimit = false
            var lastLimitCheckCount = 0
            var lastACPower : Bool? = nil
            var lastCharging : Bool? = nil
            var lastChargingCheckCount = 0

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
                        // If already in battery level limit, some margin (defaultBatteryLevelMargin) is required to release the battery level limit.
                        if (!lastLimit && currentBattLevelInt < targetBatteryLevel) || (lastLimit && currentBattLevelInt < (targetBatteryLevel - defaultBatteryLevelMargin)) {
                            needLimit = false
                        }
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
                        if isCharging == false {
                            try ChangeMagSafeLED(color: "Green")
                            print("MagSafe LED status has changed! (Full)")
                        } else if isCharging == true {
                            try ChangeMagSafeLED(color: "Red")
                            print("MagSafe LED status has changed! (Charging)")
                        } else {
                            try ChangeMagSafeLED(color: "Unknown")
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
            }
            updatePlist(targetBatteryLevel: targetBatteryLevel, targetBatteryMargin: targetBatteryMargin)
            _ = persist(true)
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
            removePlist()
        }
    }
}

BCLMLoop.main()
