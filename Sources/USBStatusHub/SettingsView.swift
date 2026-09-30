import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("showVendor") private var showVendor = true
    @AppStorage("showConnectionType") private var showConnectionType = true
    @AppStorage("showSpeed") private var showSpeed = true
    @AppStorage("showPower") private var showPower = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("General")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Device Details")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Toggle("Vendor", isOn: $showVendor)
                Toggle("Connection type", isOn: $showConnectionType)
                Toggle("Speed", isOn: $showSpeed)
                Toggle("Power draw", isOn: $showPower)
            }
        }
        .toggleStyle(.checkbox)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
