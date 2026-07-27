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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        disableTabbingForAllWindows()
        removeWindowTabCommands()
        DispatchQueue.main.async { [weak self] in
            self?.removeWindowTabCommands()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        disableTabbingForAllWindows()
        removeWindowTabCommands()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        disableTabbing(for: window)
    }

    private func disableTabbingForAllWindows() {
        for window in NSApp.windows {
            disableTabbing(for: window)
        }
    }

    private func disableTabbing(for window: NSWindow) {
        window.tabbingMode = .disallowed
        window.tabbingIdentifier = ""
        if window.tabbedWindows?.count == 1 {
            window.toggleTabBar(nil)
        }
    }

    private func removeWindowTabCommands() {
        let tabActions: Set<Selector> = [
            #selector(NSWindow.selectNextTab(_:)),
            #selector(NSWindow.selectPreviousTab(_:)),
            #selector(NSWindow.moveTabToNewWindow(_:)),
            #selector(NSWindow.mergeAllWindows(_:)),
            #selector(NSWindow.toggleTabBar(_:)),
            #selector(NSWindow.toggleTabOverview(_:))
        ]
        removeMenuItems(with: tabActions, from: NSApp.mainMenu)
    }

    private func removeMenuItems(with actions: Set<Selector>, from menu: NSMenu?) {
        guard let menu else { return }
        for item in menu.items.reversed() {
            if let submenu = item.submenu {
                removeMenuItems(with: actions, from: submenu)
            }
            if let action = item.action, actions.contains(action) {
                menu.removeItem(item)
            }
        }
    }
}
