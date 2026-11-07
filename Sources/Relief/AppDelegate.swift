import AppKit
import Combine
import SwiftUI

@main
struct ReliefMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) {
                app.run()
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var model: ReliefModel { ReliefModel.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Brand.menuBarIcon()
        item.button?.setAccessibilityLabel("Relief")
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let controller = NSHostingController(rootView: PanelView(model: model))
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller

        model.$isOn
            .sink { [weak self] on in self?.statusItem?.button?.appearsDisabled = !on }
            .store(in: &cancellables)

        model.startIfEnabled()
        Updater.startAutomaticChecks()

        // First launch: show the panel so people see where Relief lives.
        if !UserDefaults.standard.bool(forKey: PrefKey.launchedBefore) {
            UserDefaults.standard.set(true, forKey: PrefKey.launchedBefore)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                MainActor.assumeIsolated { self?.showPopover() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    /// Opening the app again (Finder, Spotlight) shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        model.monitor.setVisible(true)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        model.monitor.setVisible(false)
    }

    static func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Relief",
            .credits: NSAttributedString(string: S.aboutCredits),
        ])
    }
}

@MainActor
func showError(_ title: String, _ error: Error) {
    NSLog("Relief: \(title): \(error)")
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = error.localizedDescription
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}
