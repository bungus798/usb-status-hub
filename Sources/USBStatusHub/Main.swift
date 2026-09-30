import SwiftUI

@main
enum Main {
    static func main() {
        // Diagnostic mode: print enumerated devices to stdout and exit.
        if CommandLine.arguments.contains("--dump") {
            for device in DeviceMonitor.snapshot() {
                let parts = [
                    device.name,
                    device.vendor,
                    device.connectionType,
                    device.speedText,
                    device.powerText,
                    device.serial.map { "SN \($0)" },
                    device.isHub ? "hub" : nil,
                    device.bsdName.map { "disk \($0)" },
                    device.parentID.map { String(format: "behind hub 0x%llx", $0) },
                ].compactMap { $0 }
                print(parts.joined(separator: " | "))
            }
            return
        }
        USBStatusHubApp.main()
    }
}

struct USBStatusHubApp: App {
    @StateObject private var monitor = DeviceMonitor()
    @StateObject private var store = DeviceStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(store)
        } label: {
            Image(systemName: monitor.devices.isEmpty ? "cable.connector.slash" : "cable.connector")
            if !monitor.devices.isEmpty {
                Text("\(monitor.devices.count)")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
