import Foundation

let launchctl = "/bin/launchctl"
let plist = "com.lslqtz.bclm_loop.plist"
let plist_path = "/Library/LaunchDaemons/\(plist)"

struct Preferences: Codable {
    var Label: String
    var RunAtLoad: Bool
    var KeepAlive: Bool
    var ProgramArguments: [String]
}

func persist(_ enable: Bool) -> Bool {
    if isPersistent() && enable {
        return false
    }
    if !isPersistent() && !enable {
        return false
    }

    let process = Process()
    let pipe = Pipe()

    var load: String
    if enable {
        load = "load"
    } else {
        load = "unload"
    }

    process.launchPath = launchctl
    process.arguments = [load, plist_path]
    process.standardOutput = pipe
    process.standardError = pipe

    process.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

    if output != nil && !output!.isEmpty {
        print(output!)
    }
    
    return true
}

func isPersistent() -> Bool {
    let process = Process()
    let pipe = Pipe()

    process.launchPath = launchctl
    process.arguments = ["list"]
    process.standardOutput = pipe
    process.standardError = pipe

    process.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

    if output != nil && output!.contains(plist) {
        return true
    } else {
        return false
    }
}

func updatePlist(targetBatteryLevel: Int, targetBatteryMargin: Int) {
    let preferences =
            Preferences(
                Label: plist,
                RunAtLoad: true,
                KeepAlive: true,
                ProgramArguments: [
                    Bundle.main.executablePath! as String,
                    "loop",
                    String(targetBatteryLevel),
                    String(targetBatteryMargin),
                ]
            )

    let path = URL(fileURLWithPath: plist_path)

    let encoder = PropertyListEncoder()
    encoder.outputFormat = .xml

    do {
        let data = try encoder.encode(preferences)
        try data.write(to: path)
    } catch {
        print(error)
    }
}

func removePlist() {
    do {
        try FileManager.default.removeItem(at: URL(fileURLWithPath: plist_path))
    } catch {
        print(error)
    }
}
