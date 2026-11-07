import AppKit
import SwiftUI

/// The Settings window (⌘,), with the usual macOS toolbar tabs.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: ReliefModel.shared))
            let w = NSWindow(contentViewController: controller)
            w.title = S.settings
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: ReliefModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label(S.general, systemImage: "gearshape") }
            ShortcutSettings()
                .tabItem { Label(S.shortcuts, systemImage: "command") }
            UpdateSettings(model: model)
                .tabItem { Label(S.updates, systemImage: "arrow.down.circle") }
            AboutSettings()
                .tabItem { Label(S.aboutTab, systemImage: "info.circle") }
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: ReliefModel
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Toggle(S.launchAtLogin, isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                Toggle(isOn: $model.autoStandby) {
                    Text(S.autoStandby)
                    Text(S.autoStandbyHelp)
                }
                Toggle(isOn: $model.autoOutputMode) {
                    Text(S.autoOutputMode)
                    Text(S.autoOutputModeHelp)
                }
            }
            Section(S.permissions) {
                LabeledContent(S.systemAudioRecording) {
                    Button(S.openPrivacySettings) { AudioPermission.openSettings() }
                }
            }
            Section(S.reset) {
                LabeledContent(S.resetSound) {
                    Button(S.resetButton) { confirmReset = true }
                }
                LabeledContent(S.resetAppVolumes) {
                    Button(S.resetButton) { model.resetAllAppVolumes() }
                        .disabled(model.appVolumes.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(S.resetSoundConfirm, isPresented: $confirmReset) {
            Button(S.resetButton, role: .destructive) { model.resetAll() }
        }
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent {
                        ShortcutRecorder(action: action)
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                }
            } footer: {
                HStack {
                    Text(S.shortcutsHelp).foregroundStyle(.secondary)
                    Spacer()
                    Button(S.restoreDefaults) { ShortcutStore.resetAll() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdateSettings: View {
    @ObservedObject var model: ReliefModel

    var body: some View {
        Form {
            Section {
                Toggle(S.autoCheckUpdates, isOn: $model.autoCheckUpdates)
                LabeledContent(S.currentVersion, value: Updater.currentVersion)
                LabeledContent(S.checkNow) {
                    Button(S.checkForUpdates) { Updater.checkNow() }
                        .disabled(!Updater.isConfigured)
                }
            }
            Section {
                Link(S.releaseNotes, destination: URL(string: "https://github.com/Lightmaster00/relief/releases")!)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            AppIconView(size: 96)
            Text("Relief").font(.system(size: 22, weight: .semibold))
            Text(S.tagline).foregroundStyle(.secondary)
            Text(S.versionLabel(Updater.currentVersion)).font(.callout).foregroundStyle(.secondary)
            Text(S.aboutCredits).font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link(S.website, destination: URL(string: "https://lightmaster00.github.io/relief/")!)
                Link("GitHub", destination: URL(string: "https://github.com/Lightmaster00/relief")!)
                Link(S.reportIssue, destination: URL(string: "https://github.com/Lightmaster00/relief/issues")!)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}
