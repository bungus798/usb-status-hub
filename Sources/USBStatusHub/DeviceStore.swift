import Foundation

/// Persists per-device user state (pins, custom names) keyed by USBDevice.persistentKey.
final class DeviceStore: ObservableObject {
    @Published private(set) var pinned: Set<String>
    @Published private(set) var customNames: [String: String]

    private static let pinnedKey = "pinnedDevices"
    private static let namesKey = "customDeviceNames"

    init() {
        pinned = Set(UserDefaults.standard.stringArray(forKey: Self.pinnedKey) ?? [])
        customNames = UserDefaults.standard.dictionary(forKey: Self.namesKey) as? [String: String] ?? [:]
    }

    func isPinned(_ device: USBDevice) -> Bool {
        pinned.contains(device.persistentKey)
    }

    func togglePin(_ device: USBDevice) {
        if !pinned.insert(device.persistentKey).inserted {
            pinned.remove(device.persistentKey)
        }
        UserDefaults.standard.set(Array(pinned), forKey: Self.pinnedKey)
    }

    func displayName(for device: USBDevice) -> String {
        customNames[device.persistentKey] ?? device.name
    }

    func setCustomName(_ name: String, for device: USBDevice) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == device.name {
            customNames.removeValue(forKey: device.persistentKey)
        } else {
            customNames[device.persistentKey] = trimmed
        }
        UserDefaults.standard.set(customNames, forKey: Self.namesKey)
    }
}
