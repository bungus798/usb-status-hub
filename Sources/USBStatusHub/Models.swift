import Foundation

enum ConnectionKind: String, Hashable {
    case usb = "USB"
    case thunderbolt = "Thunderbolt"
}

struct USBDevice: Identifiable, Hashable {
    let id: UInt64                 // IORegistry entry ID (unique per connection session)
    let kind: ConnectionKind
    let name: String
    let vendor: String?
    let serial: String?
    let vendorID: Int?
    let productID: Int?
    let locationID: UInt32?
    let connectionType: String     // e.g. "USB 2.0", "USB 3.1", "Thunderbolt"
    let speedText: String?         // e.g. "480 Mb/s"
    let powerMilliamps: Int?
    let parentID: UInt64?          // registry entry ID of the hub this device sits behind
    let isHub: Bool
    let bsdName: String?           // whole-disk BSD name (e.g. "disk4") if this is storage

    /// Stable key across reconnects, used for pinning and custom names.
    var persistentKey: String {
        if kind == .thunderbolt {
            return "tb:\(vendor ?? "?"):\(name)"
        }
        let vid = vendorID.map(String.init) ?? "?"
        let pid = productID.map(String.init) ?? "?"
        if let serial, !serial.isEmpty {
            return "usb:\(vid):\(pid):\(serial)"
        }
        return "usb:\(vid):\(pid):\(name)"
    }

    var powerText: String? {
        powerMilliamps.map { "\($0) mA" }
    }
}

struct DeviceEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let deviceName: String
    let connectionType: String
    let connected: Bool
}

/// Maps IOUSBHostFamily connection speed codes to display strings.
enum USBSpeed {
    static func speedText(_ code: Int) -> String? {
        switch code {
        case 0: return "1.5 Mb/s"
        case 1: return "12 Mb/s"
        case 2: return "480 Mb/s"
        case 3: return "5 Gb/s"
        case 4: return "10 Gb/s"
        case 5: return "20 Gb/s"
        default: return nil
        }
    }

    static func connectionType(_ code: Int) -> String {
        switch code {
        case 0, 1: return "USB 1.1"
        case 2: return "USB 2.0"
        case 3: return "USB 3.0"
        case 4: return "USB 3.1"
        case 5: return "USB 3.2"
        default: return "USB"
        }
    }
}
