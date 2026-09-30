import SwiftUI

struct DeviceRow: View {
    let device: USBDevice
    var indent: Int = 0

    @EnvironmentObject private var store: DeviceStore
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var isEjecting = false
    @State private var ejectError: String?
    @State private var showingEjectError = false

    @AppStorage("showVendor") private var showVendor = true
    @AppStorage("showConnectionType") private var showConnectionType = true
    @AppStorage("showSpeed") private var showSpeed = true
    @AppStorage("showPower") private var showPower = true

    private var subtitle: String {
        var parts: [String] = []
        if showVendor, let vendor = device.vendor { parts.append(vendor) }
        if showConnectionType { parts.append(device.connectionType) }
        if showSpeed, let speed = device.speedText { parts.append(speed) }
        if showPower, let power = device.powerText { parts.append(power) }
        return parts.joined(separator: " · ")
    }

    private var iconName: String {
        if device.kind == .thunderbolt { return "bolt.horizontal" }
        if device.bsdName != nil { return "externaldrive" }
        if device.isHub { return "arrow.triangle.branch" }
        return "cable.connector"
    }

    var body: some View {
        HStack(spacing: 9) {
            if indent > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.displayName(for: device))
                    .fontWeight(.medium)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if device.bsdName != nil, isHovering || isEjecting {
                Button {
                    ejectDevice()
                } label: {
                    if isEjecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "eject")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isEjecting)
                .help("Eject")
            }
            if isHovering || store.isPinned(device) {
                Button {
                    store.togglePin(device)
                } label: {
                    Image(systemName: store.isPinned(device) ? "pin.fill" : "pin")
                        .foregroundStyle(store.isPinned(device) ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(store.isPinned(device) ? "Unpin" : "Pin to top")
            }
        }
        .padding(.leading, CGFloat(indent) * 14)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(store.isPinned(device) ? "Unpin" : "Pin to Top") {
                store.togglePin(device)
            }
            Button("Rename…") {
                draftName = store.displayName(for: device)
                isRenaming = true
            }
            if store.displayName(for: device) != device.name {
                Button("Restore Original Name") {
                    store.setCustomName("", for: device)
                }
            }
            if device.bsdName != nil {
                Button("Eject") {
                    ejectDevice()
                }
                .disabled(isEjecting)
            }
            Divider()
            Button("Copy Device Info") {
                let info = [
                    "Name: \(device.name)",
                    device.vendor.map { "Vendor: \($0)" },
                    "Type: \(device.connectionType)",
                    device.speedText.map { "Speed: \($0)" },
                    device.powerText.map { "Power: \($0)" },
                    device.serial.map { "Serial: \($0)" },
                    device.bsdName.map { "Disk: \($0)" },
                ].compactMap { $0 }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(info, forType: .string)
            }
        }
        .alert("Rename Device", isPresented: $isRenaming) {
            TextField(device.name, text: $draftName)
            Button("Save") {
                store.setCustomName(draftName, for: device)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Set a custom display name for “\(device.name)”.")
        }
        .alert("Eject Failed", isPresented: $showingEjectError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(ejectError ?? "Unknown error.")
        }
    }

    private func ejectDevice() {
        guard let bsdName = device.bsdName else { return }
        isEjecting = true
        Ejector.eject(bsdName: bsdName) { error in
            isEjecting = false
            if let error {
                ejectError = error
                showingEjectError = true
            }
        }
    }
}
