import Foundation

/// Persistent log of connect/disconnect events, newest first, capped at 200.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var events: [DeviceEvent]

    private static let defaultsKey = "deviceHistory"
    private static let maxEvents = 200

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([DeviceEvent].self, from: data) {
            events = decoded
        } else {
            events = []
        }
    }

    func record(connected: [USBDevice], disconnected: [USBDevice]) {
        let now = Date()
        var new: [DeviceEvent] = []
        for device in disconnected {
            new.append(DeviceEvent(
                id: UUID(), date: now, deviceName: device.name,
                connectionType: device.connectionType, connected: false
            ))
        }
        for device in connected {
            new.append(DeviceEvent(
                id: UUID(), date: now, deviceName: device.name,
                connectionType: device.connectionType, connected: true
            ))
        }
        events = Array((new + events).prefix(Self.maxEvents))
        persist()
    }

    func clear() {
        events = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
