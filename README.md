# USB Status Hub

A lightweight macOS menu bar app that monitors USB and Thunderbolt devices, built with Swift, SwiftUI (`MenuBarExtra`), and IOKit. Requires macOS 13+.

## Features

- Menu bar icon that reflects connection state (device count badge; slashed icon when nothing is connected)
- Popover with a searchable list of connected devices
- Per-device details: name, vendor, connection type (USB 1.1/2.0/3.x, Thunderbolt), negotiated speed, and power draw
- Pin devices to the top of the list (right-click or hover pin button)
- Custom display names per device (right-click → Rename…)
- Live updates on connect/disconnect via IOKit matching notifications — no polling, no manual refresh
- Settings: launch at login, choose which detail columns to show
- Connection/disconnect history log (clock icon; persisted, capped at 200 events)
- Safe eject for USB storage (hover eject button or right-click → Eject; unmounts all volumes then ejects via DiskArbitration)
- Hub hierarchy view — devices plugged into a hub are shown indented beneath it

## Build

```sh
./build.sh
open "build/USB Status Hub.app"
```

The script compiles with `swiftc` and assembles the app bundle in `build/`. For launch-at-login to work reliably, move the built app to `/Applications` first.

A `Package.swift` is also included if you prefer `swift build` or opening the package in Xcode.

## Diagnostics

Run the binary with `--dump` to print the enumerated device list to stdout and exit:

```sh
"build/USB Status Hub.app/Contents/MacOS/USB Status Hub" --dump
```

## Implementation notes

- USB devices are enumerated by matching `IOUSBHostDevice` in the IORegistry; Thunderbolt devices by matching `IOThunderboltSwitch` (the Mac's own controller at depth 0 is filtered out).
- Speed and power draw are read through the classic `IOUSBDeviceInterface` plug-in (`GetDeviceSpeed`, `GetConfigurationDescriptorPtr` → `bMaxPower`), with registry properties as fallback.
- Pins and custom names persist in `UserDefaults`, keyed by vendor ID + product ID + serial number so they survive reconnects and port changes.
- Hub hierarchy comes from walking each device's IORegistry parent chain to the nearest `IOUSBHostDevice` ancestor; hubs are identified by `bDeviceClass == 9`.
- Safe eject finds the device's whole-disk `IOMedia` child (verifying it belongs to that device, not one downstream of a hub), then unmounts and ejects it with DiskArbitration.
- The history log diffs device snapshots on each IOKit notification and persists the last 200 events in `UserDefaults`.
