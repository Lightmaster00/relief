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

        model.showPanel = { [weak self] in self?.togglePopover(nil) }
        model.registerShortcuts()
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
        // Right-click or Control-click: the quick menu.
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            showQuickMenu()
            return
        }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        model.monitor.setVisible(true)
        model.engine.recheckPermission()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showQuickMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        let power = NSMenuItem(title: model.isOn ? S.turnOff : S.turnOn, action: #selector(menuToggle), keyEquivalent: "")
        power.target = self
        menu.addItem(power)
        menu.addItem(.separator())

        let presets = NSMenuItem(title: S.equalizer, action: nil, keyEquivalent: "")
        let presetMenu = NSMenu()
        let eq = NSMenuItem(title: S.equalizerEnabled, action: #selector(menuToggleEqualizer), keyEquivalent: "")
        eq.target = self
        eq.state = model.settings.equalizerEnabled ? .on : .off
        presetMenu.addItem(eq)
        presetMenu.addItem(.separator())
        for preset in model.allPresets {
            let item = NSMenuItem(title: preset.localizedName, action: #selector(menuPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id
            item.state = model.settings.presetID == preset.id ? .on : .off
            presetMenu.addItem(item)
        }
        presets.submenu = presetMenu
        menu.addItem(presets)

        for mode in OutputMode.allCases {
            let item = NSMenuItem(title: mode == .speakers ? S.speakers : S.headphones,
                                  action: #selector(menuOutputMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = model.settings.outputMode == mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: S.settingsMenu, action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: S.quitRelief, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func menuToggle() { model.isOn.toggle() }
    @objc private func menuToggleEqualizer() { model.settings.equalizerEnabled.toggle() }
    @objc private func menuSettings() { SettingsWindow.shared.show() }

    @objc private func menuPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let preset = model.allPresets.first(where: { $0.id == id }) else { return }
        model.apply(preset)
    }

    @objc private func menuOutputMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = OutputMode(rawValue: raw) else { return }
        model.setOutputMode(mode)
    }

    func popoverDidClose(_ notification: Notification) {
        model.monitor.setVisible(false)
    }

    static func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Relief",
            .credits: NSAttributedString(string: S.aboutCredits,
                                         attributes: [.font: NSFont.systemFont(ofSize: 11),
                                                      .foregroundColor: NSColor.secondaryLabelColor]),
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
