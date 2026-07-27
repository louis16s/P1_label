import AppKit
import SwiftUI

@main
struct P1LabelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(model: model)
                .frame(minWidth: 1_000, minHeight: 680)
        }
        .defaultSize(width: 1_260, height: 820)
        .commands {
            P1LabelCommands(model: model)
        }

        Window("打印机", id: "printer") {
            PrinterView(model: model)
                .frame(minWidth: 520, minHeight: 520)
        }
        .defaultSize(width: 580, height: 620)

        Window("关于 P1 Label", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("SDK 功能支持", id: "sdk-support") {
            SDKSupportView()
        }
        .defaultSize(width: 720, height: 620)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.tabbingMode = .disallowed
        }
    }
}
