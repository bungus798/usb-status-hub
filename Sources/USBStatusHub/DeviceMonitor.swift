import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib

/// Enumerates USB and Thunderbolt devices via IOKit and publishes live updates
/// on connect/disconnect using IOKit matching notifications.
final class DeviceMonitor: ObservableObject {
    @Published private(set) var devices: [USBDevice] = []

    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    init() {
        start()
    }

    deinit {
        for it in iterators where it != 0 { IOObjectRelease(it) }
        if let port = notifyPort { IONotificationPortDestroy(port) }
    }

    private func start() {
        devices = Self.snapshot()

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            // Drain the iterator to re-arm the notification, then rescan.
            while case let obj = IOIteratorNext(iterator), obj != 0 { IOObjectRelease(obj) }
            guard let refcon else { return }
            let monitor = Unmanaged<DeviceMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.refresh()
        }

        for className in ["IOUSBHostDevice", "IOThunderboltSwitch"] {
            for notification in [kIOFirstMatchNotification, kIOTerminatedNotification] {
                guard let matching = IOServiceMatching(className) else { continue }
                var iterator: io_iterator_t = 0
                let kr = IOServiceAddMatchingNotification(
                    port, notification, matching, callback, refcon, &iterator
                )
                if kr == KERN_SUCCESS {
                    // Drain once to arm the notification.
                    while case let obj = IOIteratorNext(iterator), obj != 0 { IOObjectRelease(obj) }
                    iterators.append(iterator)
                }
            }
        }
    }

    private func refresh() {
        let old = devices
        let snapshot = Self.snapshot()
        guard snapshot != old else { return }
        devices = snapshot

        let oldIDs = Set(old.map(\.id))
        let newIDs = Set(snapshot.map(\.id))
        let added = snapshot.filter { !oldIDs.contains($0.id) }
        let removed = old.filter { !newIDs.contains($0.id) }
        if !added.isEmpty || !removed.isEmpty {
            HistoryStore.shared.record(connected: added, disconnected: removed)
        }
    }

    // MARK: - Enumeration

    static func snapshot() -> [USBDevice] {
        var result = enumerateUSB()
        result.append(contentsOf: enumerateThunderbolt())
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func enumerateUSB() -> [USBDevice] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var devices: [USBDevice] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let device = makeUSBDevice(service) {
                devices.append(device)
            }
        }
        return devices
    }

    private static func makeUSBDevice(_ service: io_service_t) -> USBDevice? {
        var entryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &entryID)

        let vendorID: Int? = prop(service, "idVendor")
        let productID: Int? = prop(service, "idProduct")
        let name: String? = prop(service, "USB Product Name") ?? prop(service, "kUSBProductString")
        let vendor: String? = prop(service, "USB Vendor Name") ?? prop(service, "kUSBVendorString")
        let serial: String? = prop(service, "USB Serial Number") ?? prop(service, "kUSBSerialNumberString")
        let locationID: UInt32? = (prop(service, "locationID") as Int?).map(UInt32.init)

        // Speed and power via the classic IOUSBDeviceInterface; registry keys as fallback.
        let details = deviceInterfaceDetails(service)
        let speedCode = details.speed
            ?? (prop(service, "USBSpeed") as Int?)
            ?? (prop(service, "Device Speed") as Int?)

        let fallbackName: String = {
            if let vendorID, let productID {
                return String(format: "USB Device (%04x:%04x)", vendorID, productID)
            }
            return "USB Device"
        }()

        let isHub = (prop(service, "bDeviceClass") as Int?) == 9

        return USBDevice(
            id: entryID,
            kind: .usb,
            name: name ?? fallbackName,
            vendor: vendor,
            serial: serial,
            vendorID: vendorID,
            productID: productID,
            locationID: locationID,
            connectionType: speedCode.map(USBSpeed.connectionType) ?? "USB",
            speedText: speedCode.flatMap(USBSpeed.speedText),
            powerMilliamps: details.maxPowerMilliamps,
            parentID: nearestUSBAncestorID(service),
            isHub: isHub,
            bsdName: isHub ? nil : bsdName(for: service, deviceID: entryID)
        )
    }

    /// Registry entry ID of the closest IOUSBHostDevice ancestor (the hub a
    /// device is plugged into), or nil for devices on a root port.
    private static func nearestUSBAncestorID(_ entry: io_object_t) -> UInt64? {
        var current: io_object_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &current) == KERN_SUCCESS else {
            return nil
        }
        while current != 0 {
            if IOObjectConformsTo(current, "IOUSBHostDevice") != 0 {
                var id: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(current, &id)
                IOObjectRelease(current)
                return id
            }
            var next: io_object_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &next)
            IOObjectRelease(current)
            if kr != KERN_SUCCESS { return nil }
            current = next
        }
        return nil
    }

    /// Whole-disk BSD name (e.g. "disk4") for a storage device, found by walking
    /// the device's registry subtree for an IOMedia entry. The ancestor check
    /// keeps a hub from claiming the media of a drive plugged into it.
    private static func bsdName(for service: io_service_t, deviceID: UInt64) -> String? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            service, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            guard IOObjectConformsTo(child, "IOMedia") != 0,
                  (prop(child, "Whole") as Bool?) == true,
                  let name: String = prop(child, "BSD Name"),
                  nearestUSBAncestorID(child) == deviceID else { continue }
            return name
        }
        return nil
    }

    private static func enumerateThunderbolt() -> [USBDevice] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOThunderboltSwitch"), &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var devices: [USBDevice] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            // Depth 0 is the Mac's own Thunderbolt controller, not an attached device.
            if let depth: Int = prop(service, "Depth") ?? prop(service, "Switch Depth"), depth == 0 {
                continue
            }
            guard let model: String = prop(service, "Device Model Name") else { continue }

            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)
            let vendor: String? = prop(service, "Device Vendor Name")

            devices.append(USBDevice(
                id: entryID,
                kind: .thunderbolt,
                name: model,
                vendor: vendor,
                serial: nil,
                vendorID: prop(service, "Device Vendor ID"),
                productID: prop(service, "Device ID"),
                locationID: nil,
                connectionType: "Thunderbolt",
                speedText: nil,
                powerMilliamps: nil,
                parentID: nil,
                isHub: false,
                bsdName: nil
            ))
        }
        return devices
    }

    private static func prop<T>(_ service: io_object_t, _ key: String) -> T? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? T
    }

    // MARK: - IOUSBDeviceInterface (speed + power draw)

    // IOUSBLib's UUID constants are C macros that Swift can't import, so re-declare them.
    private static let usbDeviceUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(nil,
        0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xd4,
        0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
    private static let usbDeviceInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
        0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xd4,
        0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
    private static let cfPlugInInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
        0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
        0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)

    private static func deviceInterfaceDetails(_ service: io_service_t) -> (speed: Int?, maxPowerMilliamps: Int?) {
        var pluginRaw: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(
            service, usbDeviceUserClientTypeID, cfPlugInInterfaceID, &pluginRaw, &score
        ) == KERN_SUCCESS, let plugin = pluginRaw else {
            return (nil, nil)
        }
        defer { _ = IODestroyPlugInInterface(plugin) }

        var raw: UnsafeMutableRawPointer?
        guard plugin.pointee!.pointee.QueryInterface(
            plugin, CFUUIDGetUUIDBytes(usbDeviceInterfaceID), &raw
        ) == S_OK, let raw else {
            return (nil, nil)
        }
        let device = raw.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBDeviceInterface>?.self)
        defer { _ = device.pointee!.pointee.Release(device) }

        var speedByte: UInt8 = 0
        let speed: Int? = device.pointee!.pointee.GetDeviceSpeed(device, &speedByte) == kIOReturnSuccess
            ? Int(speedByte) : nil

        var power: Int?
        var descPtr: IOUSBConfigurationDescriptorPtr?
        if device.pointee!.pointee.GetConfigurationDescriptorPtr(device, 0, &descPtr) == kIOReturnSuccess,
           let desc = descPtr {
            // bMaxPower is in 2 mA units at USB 2.0 speeds, 8 mA at SuperSpeed and above.
            let units = (speed ?? 0) >= 3 ? 8 : 2
            power = Int(desc.pointee.MaxPower) * units
        }
        return (speed, power)
    }
}
