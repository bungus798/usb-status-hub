import SwiftUI

struct ContentView: View {
    private enum Screen {
        case devices, history, settings
    }

    @EnvironmentObject private var monitor: DeviceMonitor
    @EnvironmentObject private var store: DeviceStore
    @State private var searchText = ""
    @State private var screen: Screen = .devices

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filteredDevices: [USBDevice] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return monitor.devices }
        return monitor.devices.filter { device in
            store.displayName(for: device).localizedCaseInsensitiveContains(query)
                || device.name.localizedCaseInsensitiveContains(query)
                || (device.vendor?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var pinnedDevices: [USBDevice] {
        filteredDevices.filter { store.isPinned($0) }
    }

    private var otherDevices: [USBDevice] {
        filteredDevices.filter { !store.isPinned($0) }
    }

    // MARK: Hub hierarchy

    private var childrenByParent: [UInt64: [USBDevice]] {
        let ids = Set(otherDevices.map(\.id))
        return Dictionary(grouping: otherDevices.filter {
            if let parentID = $0.parentID { return ids.contains(parentID) }
            return false
        }, by: { $0.parentID! })
    }

    private var rootDevices: [USBDevice] {
        let ids = Set(otherDevices.map(\.id))
        return otherDevices.filter { $0.parentID == nil || !ids.contains($0.parentID!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch screen {
            case .devices: deviceList
            case .history: HistoryView()
            case .settings: SettingsView()
            }
            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            switch screen {
            case .devices:
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search devices", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                Button {
                    screen = .history
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Connection history")
                Button {
                    screen = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            case .history:
                backButton
                Text("History")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    HistoryStore.shared.clear()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            case .settings:
                backButton
                Text("Settings")
                    .font(.headline)
                Spacer()
            }
        }
        .padding(10)
    }

    private var backButton: some View {
        Button {
            screen = .devices
        } label: {
            Image(systemName: "chevron.backward")
        }
        .buttonStyle(.plain)
    }

    private var deviceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if filteredDevices.isEmpty {
                    Text(searchText.isEmpty ? "No devices connected" : "No matching devices")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    if !pinnedDevices.isEmpty {
                        sectionHeader("Pinned")
                        ForEach(pinnedDevices) { DeviceRow(device: $0) }
                        if !otherDevices.isEmpty {
                            sectionHeader("Devices")
                        }
                    }
                    if isSearching {
                        ForEach(otherDevices) { DeviceRow(device: $0) }
                    } else {
                        deviceTree(rootDevices, indent: 0, in: childrenByParent)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
        .frame(maxHeight: 420)
    }

    private func deviceTree(_ devices: [USBDevice], indent: Int, in map: [UInt64: [USBDevice]]) -> AnyView {
        AnyView(ForEach(devices) { device in
            DeviceRow(device: device, indent: indent)
            deviceTree(map[device.id] ?? [], indent: indent + 1, in: map)
        })
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private var footer: some View {
        HStack {
            Text("\(monitor.devices.count) device\(monitor.devices.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
