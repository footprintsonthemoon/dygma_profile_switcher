import Foundation
import IOKit
import IOKit.serial

/// Discovers the Dygma Defy's serial port via IOKit enumeration + Focus API probe.
/// Monitors USB attach/detach events via IOServiceAddMatchingNotification (no polling).
final class DeviceDiscovery {

    var onDeviceAttached: (() -> Void)?
    var onDeviceDetached: (() -> Void)?

    private var notificationPort: IONotificationPortRef?
    private var attachIterator: io_iterator_t = 0
    private var detachIterator: io_iterator_t = 0
    private let focusClient: FocusAPIClient

    init(focusClient: FocusAPIClient) {
        self.focusClient = focusClient
    }

    // MARK: - Discovery

    /// Enumerates available serial ports and probes each with the Focus API.
    /// Returns the first matching port path, or nil if none found.
    func discoverDevice(baudRate: Int = 115_200) async -> String? {
        let candidates = enumerateSerialPorts()
        AppLogger.shared.log("Device discovery: found \(candidates.count) serial port(s)", level: .debug)

        for portPath in candidates {
            AppLogger.shared.log("Probing \(portPath)…", level: .debug)
            do {
                try await focusClient.connect(portPath: portPath, baudRate: baudRate)
                let isMatch = try await focusClient.probe()
                if isMatch {
                    AppLogger.shared.log("Dygma Defy found at \(portPath)", level: .info)
                    return portPath
                }
                await focusClient.disconnect()
            } catch {
                await focusClient.disconnect()
                AppLogger.shared.log("Probe failed for \(portPath): \(error.localizedDescription)", level: .debug)
            }
        }
        return nil
    }

    // MARK: - IOKit Enumeration

    // Dygma USB Vendor ID (all models: Raise, Raise 2, Defy)
    private static let dygmaVendorID: Int = 0x35ef

    private func enumerateSerialPorts() -> [String] {
        var ports: [String] = []
        let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        matchingDict[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault,
                                                  matchingDict as CFDictionary,
                                                  &iterator)
        guard result == KERN_SUCCESS else { return ports }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path = IORegistryEntryCreateCFProperty(
                service,
                kIOCalloutDeviceKey as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String else { continue }

            // Walk up the IORegistry to find the USB device and check Vendor ID
            if isDygmaDevice(service: service) {
                AppLogger.shared.log("Found Dygma serial port: \(path)", level: .info)
                ports.append(path)
            }
        }
        return ports
    }

    /// Walks the IORegistry parent chain to find the USB device entry and check its Vendor ID.
    private func isDygmaDevice(service: io_object_t) -> Bool {
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        for _ in 0..<6 {   // max 6 levels up the tree
            var parent: io_object_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS,
                  parent != 0 else { break }
            IOObjectRelease(current)
            current = parent

            if let vid = IORegistryEntryCreateCFProperty(
                current,
                "idVendor" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? Int, vid == Self.dygmaVendorID {
                return true
            }
        }
        return false
    }

    // MARK: - Hotplug Monitoring

    func startMonitoring() {
        guard notificationPort == nil else { return }

        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notificationPort else { return }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)

        let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue) as CFDictionary

        // Attach
        IOServiceAddMatchingNotification(
            port,
            kIOMatchedNotification,
            matchingDict,
            { context, iterator in
                // Drain iterator (required by IOKit)
                var service: io_object_t
                repeat {
                    service = IOIteratorNext(iterator)
                    if service != 0 { IOObjectRelease(service) }
                } while service != 0
                guard let ctx = context else { return }
                let discovery = Unmanaged<DeviceDiscovery>.fromOpaque(ctx).takeUnretainedValue()
                discovery.onDeviceAttached?()
            },
            Unmanaged.passUnretained(self).toOpaque(),
            &attachIterator
        )
        // Drain initial matches
        drainIterator(attachIterator)

        // Detach
        IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            matchingDict,
            { context, iterator in
                var service: io_object_t
                repeat {
                    service = IOIteratorNext(iterator)
                    if service != 0 { IOObjectRelease(service) }
                } while service != 0
                guard let ctx = context else { return }
                let discovery = Unmanaged<DeviceDiscovery>.fromOpaque(ctx).takeUnretainedValue()
                discovery.onDeviceDetached?()
            },
            Unmanaged.passUnretained(self).toOpaque(),
            &detachIterator
        )
        drainIterator(detachIterator)

        AppLogger.shared.log("USB hotplug monitoring started", level: .debug)
    }

    func stopMonitoring() {
        if attachIterator != 0 { IOObjectRelease(attachIterator); attachIterator = 0 }
        if detachIterator != 0 { IOObjectRelease(detachIterator); detachIterator = 0 }
        if let port = notificationPort { IONotificationPortDestroy(port) }
        notificationPort = nil
    }

    private func drainIterator(_ iterator: io_iterator_t) {
        var service: io_object_t
        repeat {
            service = IOIteratorNext(iterator)
            if service != 0 { IOObjectRelease(service) }
        } while service != 0
    }

    deinit { stopMonitoring() }
}
