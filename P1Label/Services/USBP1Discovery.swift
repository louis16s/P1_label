import Foundation
import IOKit
import IOKit.usb
import P1USBBridge

struct P1USBDevice: Identifiable, Equatable, Sendable {
    let registryID: UInt64
    let productName: String
    let locationID: UInt32?

    var id: UInt64 { registryID }
}

/// User-space discovery for P1's confirmed USB vendor/product identifiers.
/// Bulk-pipe claim and writes are intentionally kept separate from discovery.
enum P1USBDiscovery {
    static func connectedDevices() -> [P1USBDevice] {
        guard let matching = IOServiceMatching("IOUSBHostDevice") else {
            return libUSBOnlyFallback()
        }
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return libUSBOnlyFallback() }
        defer { IOObjectRelease(iterator) }

        var devices: [P1USBDevice] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            // On current macOS USB registry entries expose these numeric keys as
            // `idVendor` and `idProduct` (rather than the older kUSB* names).
            let vendorID = property("idVendor", from: service) as? NSNumber
            let productID = property("idProduct", from: service) as? NSNumber
            if vendorID?.uint16Value == P1Protocol.vendorID, productID?.uint16Value == P1Protocol.productID {
                let name = (property(kUSBProductString, from: service) as? String) ?? "德佟 P1"
                let locationID = (property(kUSBDevicePropertyLocationID, from: service) as? NSNumber)?.uint32Value
                var registryID: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(service, &registryID)
                devices.append(.init(registryID: registryID, productName: name, locationID: locationID))
            }
            service = IOIteratorNext(iterator)
        }
        return devices.isEmpty ? libUSBOnlyFallback() : devices
    }

    private static func libUSBOnlyFallback() -> [P1USBDevice] {
        guard p1_usb_is_present() != 0 else { return [] }
        let fallbackID = UInt64(P1Protocol.vendorID) << 32 | UInt64(P1Protocol.productID)
        return [
            .init(
                registryID: fallbackID,
                productName: "DeTong P1 Label Printer",
                locationID: nil
            )
        ]
    }

    private static func property(_ key: String, from service: io_registry_entry_t) -> AnyObject? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
