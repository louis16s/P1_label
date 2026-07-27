import Foundation
import P1USBBridge

guard p1_usb_is_present() != 0 else {
    FileHandle.standardError.write(Data("P1 USB probe: device not present.\n".utf8))
    exit(1)
}
print("P1 USB probe: device detected without claiming the interface.")

var result = P1USBResultOK
guard let connection = p1_usb_open(&result) else {
    FileHandle.standardError.write(Data("P1 USB probe failed: \(result.rawValue)\n".utf8))
    exit(Int32(result.rawValue))
}
var portStatus: UInt8 = 0
let statusResult = p1_usb_get_port_status(connection, &portStatus)
p1_usb_close(connection)
print("P1 USB Printer Class interface opened and released successfully.")
if statusResult == P1USBResultOK {
    print(String(format: "P1 USB port status: 0x%02X (paperEmpty=%@, selected=%@, noError=%@).",
                 portStatus,
                 portStatus & 0x20 != 0 ? "yes" : "no",
                 portStatus & 0x10 != 0 ? "yes" : "no",
                 portStatus & 0x08 != 0 ? "yes" : "no"))
} else {
    print("P1 USB port status is not supported by this firmware (\(statusResult.rawValue)).")
}
