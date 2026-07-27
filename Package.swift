// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "P1Label",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "P1Label", targets: ["P1Label"]),
        .executable(name: "P1USBProbe", targets: ["P1USBProbe"])
    ],
    targets: [
        .systemLibrary(
            name: "CLibUSB",
            path: "P1Label/CLibUSB"
        ),
        .target(
            name: "P1USBBridge",
            dependencies: ["CLibUSB"],
            path: "P1Label/P1USBBridge",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-I/opt/homebrew/opt/libusb/include"])],
            linkerSettings: [.unsafeFlags(["-L/opt/homebrew/opt/libusb/lib"])]
        ),
        .executableTarget(
            name: "P1Label",
            dependencies: ["P1USBBridge"],
            path: "P1Label",
            exclude: ["Tests", "CLibUSB", "P1USBBridge", "P1USBProbe", "Resources"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Vision")
            ]
        ),
        .executableTarget(
            name: "P1USBProbe",
            dependencies: ["P1USBBridge"],
            path: "P1Label/P1USBProbe"
        ),
        .testTarget(
            name: "P1LabelTests",
            dependencies: ["P1Label"],
            path: "P1Label/Tests/P1LabelTests"
        )
    ]
)
