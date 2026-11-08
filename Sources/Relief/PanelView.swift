import AppKit
import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case sound, equalizer, apps
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sound: return S.tabSound
        case .equalizer: return S.tabEqualizer
        case .apps: return S.tabApps
        }
    }
}

/// The window that opens from the menu bar.
struct PanelView: View {
    @ObservedObject var model: ReliefModel
    @State private var tab: PanelTab = .sound

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            status
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            Picker("", selection: $tab) {
                ForEach(PanelTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Group {
                switch tab {
                case .sound: SoundTab(model: model)
                case .equalizer: EqualizerTab(model: model)
                case .apps: AppsTab(model: model)
                }
            }
            .padding(.horizontal, 16)
            .disabled(!model.isOn)
            .opacity(model.isOn ? 1 : 0.45)
            .animation(.easeOut(duration: 0.15), value: model.isOn)

            Divider().padding(.top, 12)
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 360)
        .background {
            // ⌘, opens the settings while the panel is open.
            Button("") { SettingsWindow.shared.show() }
                .keyboardShortcut(",", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppIconView(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Relief").font(.system(size: 15, weight: .semibold))
                Text(S.tagline).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $model.isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .help(model.isOn ? S.turnOff : S.turnOn)
        }
    }

    @ViewBuilder private var status: some View {
        switch model.engine.state {
        case .off:
            StatusLine(symbol: "speaker.slash", text: S.statusOff, color: .secondary)
        case .running where model.engine.isSleeping:
            StatusLine(symbol: "moon.zzz", text: S.statusStandby, color: .secondary)
        case .running:
            StatusLine(symbol: "hifispeaker", text: S.playingOn(model.engine.outputDeviceName), color: .secondary)
        case .needsPermission:
            VStack(alignment: .leading, spacing: 6) {
                StatusLine(symbol: "exclamationmark.triangle.fill", text: S.permissionNeeded, color: .orange)
                Button(S.openPrivacySettings) { AudioPermission.openSettings() }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                StatusLine(symbol: "exclamationmark.triangle.fill", text: message, color: .orange)
                Button(S.tryAgain) {
                    model.engine.stop()
                    model.engine.start()
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            Menu {
                Button(S.settingsMenu) { SettingsWindow.shared.show() }
                    .keyboardShortcut(",", modifiers: .command)
                Button(S.checkForUpdates) { Updater.checkNow() }
                    .disabled(!Updater.isConfigured)
                Divider()
                Toggle(S.autoStandby, isOn: $model.autoStandby)
                Toggle(S.launchAtLogin, isOn: Binding(get: { model.launchAtLogin },
                                                      set: { model.launchAtLogin = $0 }))
                Divider()
                Button(S.website) {
                    if let url = URL(string: "https://lightmaster00.github.io/relief/") { NSWorkspace.shared.open(url) }
                }
                Button(S.about) { AppDelegate.showAbout() }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(S.settings)

            Spacer()
            Text("v\(Updater.currentVersion)").font(.system(size: 11)).foregroundStyle(.tertiary)
            Spacer()
            Button(S.quit) { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
        }
    }
}

private struct StatusLine: View {
    let symbol: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11))
            Text(text).font(.system(size: 11)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
    }
}

// MARK: - Sound

private struct SoundTab: View {
    @ObservedObject var model: ReliefModel

    var body: some View {
        VStack(spacing: 14) {
            OutputCard(devices: model.devices)
            Card {
                LabeledSlider(title: S.booster, symbol: "speaker.wave.3.fill",
                              value: $model.settings.boost,
                              valueText: model.settings.boost == 0 ? S.off : String(format: "+%.1f dB", model.settings.boost * 12))
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledSlider(title: S.surround, symbol: "dot.radiowaves.left.and.right",
                                  value: $model.settings.surround,
                                  valueText: model.settings.surround == 0 ? S.off : percent(model.settings.surround))
                    Picker("", selection: Binding(get: { model.settings.outputMode },
                                                  set: { model.setOutputMode($0) })) {
                        Label(S.speakers, systemImage: "hifispeaker.2").tag(OutputMode.speakers)
                        Label(S.headphones, systemImage: "headphones").tag(OutputMode.headphones)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if model.settings.outputMode == .headphones {
                        HeadphoneRow(model: model)
                    }
                }
            }
            Card {
                VStack(spacing: 10) {
                    LabeledSlider(title: S.ambience, symbol: "sparkles",
                                  value: $model.settings.ambience,
                                  valueText: model.settings.ambience == 0 ? S.off : percent(model.settings.ambience))
                    LabeledSlider(title: S.clarity, symbol: "waveform",
                                  value: $model.settings.clarity,
                                  valueText: model.settings.clarity == 0 ? S.off : percent(model.settings.clarity))
                    LabeledSlider(title: S.bass, symbol: "waveform.path",
                                  value: $model.settings.bass,
                                  valueText: model.settings.bass == 0 ? S.off : String(format: "+%.1f dB", model.settings.bass * 10))
                    HStack {
                        Label(S.nightMode, systemImage: "moon.fill")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $model.settings.nightMode)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                                }
                    .help(S.nightModeHelp)
                }
            }
        }
    }

    private func percent(_ v: Float) -> String { "\(Int((v * 100).rounded())) %" }
}

/// The headphone model in use, corrected to a neutral sound.
private struct HeadphoneRow: View {
    @ObservedObject var model: ReliefModel
    @State private var picking = false

    var body: some View {
        HStack(spacing: 6) {
            Label(S.headphoneModel, systemImage: "slider.horizontal.below.square.filled.and.square")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button {
                picking = true
            } label: {
                HStack(spacing: 3) {
                    Text(model.settings.headphoneProfile ?? S.noCorrection).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 12))
                .frame(maxWidth: 170, alignment: .trailing)
            }
            .buttonStyle(.borderless)
            .help(S.headphoneHelp)
            .popover(isPresented: $picking, arrowEdge: .trailing) {
                HeadphonePicker(model: model, isPresented: $picking)
            }
        }
    }
}

private struct HeadphonePicker: View {
    @ObservedObject var model: ReliefModel
    @Binding var isPresented: Bool
    @State private var query = ""

    var body: some View {
        let results = HeadphoneLibrary.search(query)
        VStack(alignment: .leading, spacing: 8) {
            TextField(S.searchHeadphones, text: $query)
                .textFieldStyle(.roundedBorder)
            List {
                Button {
                    choose(nil)
                } label: {
                    row(S.noCorrection, symbol: "nosign", selected: model.settings.headphoneProfile == nil)
                }
                .buttonStyle(.plain)
                ForEach(results) { p in
                    Button { choose(p.name) } label: {
                        row(p.name, symbol: p.kind.symbol, selected: model.settings.headphoneProfile == p.name)
                    }
                    .buttonStyle(.plain)
                }
                if results.isEmpty {
                    Text(S.noHeadphoneFound).foregroundStyle(.secondary).font(.callout)
                }
            }
            .listStyle(.plain)
            .frame(height: 300)
            Text(S.headphoneCredit).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 320)
    }

    private func row(_ title: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(title).lineLimit(1)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func choose(_ name: String?) {
        model.setHeadphoneProfile(name)
        isPresented = false
    }
}

/// The current output, its system volume, and the list of outputs.
private struct OutputCard: View {
    @ObservedObject var devices: OutputDevices

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(S.output, systemImage: devices.current?.symbol ?? "speaker.wave.2")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Menu(devices.current?.name ?? S.noOutput) {
                        ForEach(devices.devices) { device in
                            Button {
                                devices.select(device)
                            } label: {
                                if device.id == devices.current?.id {
                                    Label(device.name, systemImage: "checkmark")
                                } else {
                                    Text(device.name)
                                }
                            }
                        }
                        Divider()
                        Button(S.soundSettings) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(.system(size: 12))
                }
                if let volume = devices.volume {
                    HStack(spacing: 8) {
                        Button {
                            devices.setMuted(!devices.isMuted)
                        } label: {
                            Image(systemName: devices.isMuted || volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                                .frame(width: 16)
                        }
                        .buttonStyle(.borderless)
                        .help(devices.isMuted ? S.unmute : S.mute)
                        Slider(value: Binding(get: { Double(devices.isMuted ? 0 : volume) },
                                              set: { devices.setVolume(Float($0)) }), in: 0...1)
                            .controlSize(.small)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(S.systemVolume)
                }
            }
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05)))
    }
}

struct LabeledSlider: View {
    let title: String
    let symbol: String
    @Binding var value: Float
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(valueText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = Float($0) }), in: 0...1)
                .controlSize(.small)
        }
    }
}

// MARK: - Equalizer

private struct EqualizerTab: View {
    @ObservedObject var model: ReliefModel
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Toggle(S.equalizer, isOn: $model.settings.equalizerEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                        .font(.system(size: 12, weight: .medium))
                Spacer()
                Menu(model.currentPreset?.localizedName ?? S.customPreset) {
                    ForEach(EQPreset.builtIn) { preset in
                        Button(preset.localizedName) { model.apply(preset) }
                    }
                    if !model.customPresets.isEmpty {
                        Divider()
                        ForEach(model.customPresets) { preset in
                            Button(preset.name) { model.apply(preset) }
                        }
                    }
                    Divider()
                    Button(S.savePreset) {
                        newName = ""
                        naming = true
                    }
                    if let current = model.currentPreset, current.isCustom {
                        Button(S.deletePreset(current.name)) { model.deletePreset(current) }
                    }
                }
                .fixedSize()
                .controlSize(.small)
            }

            if naming {
                HStack(spacing: 6) {
                    TextField(S.presetNamePlaceholder, text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit(save)
                    Button(S.save, action: save)
                        .controlSize(.small)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button(S.cancel) { naming = false }
                        .controlSize(.small)
                }
            }

            Card {
                VStack(spacing: 6) {
                    EQCurve(gains: model.settings.equalizerGains, enabled: model.settings.equalizerEnabled)
                        .frame(height: 44)
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<SoundSettings.bandCount, id: \.self) { i in
                            VStack(spacing: 4) {
                                Text(gainText(model.settings.equalizerGains[i]))
                                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                VerticalSlider(value: model.settings.equalizerGains[i],
                                               range: SoundSettings.bandRange) { model.setBand(i, $0) }
                                    .accessibilityLabel(frequencyText(SoundSettings.bandFrequencies[i]) + " Hz")
                                    .frame(width: 22, height: 128)
                                Text(frequencyText(SoundSettings.bandFrequencies[i]))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .disabled(!model.settings.equalizerEnabled)
                .opacity(model.settings.equalizerEnabled ? 1 : 0.5)
            }
        }
    }

    private func save() {
        model.saveCurrentAsPreset(named: newName)
        naming = false
    }

    private func gainText(_ g: Float) -> String {
        g == 0 ? "0" : String(format: "%+.0f", g)
    }

    private func frequencyText(_ f: Double) -> String {
        f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
    }
}

/// A vertical fader: drag to change, double-click to reset to 0.
struct VerticalSlider: View {
    let value: Float
    let range: ClosedRange<Float>
    let onChange: (Float) -> Void
    @State private var dragStart: Float?

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let knob: CGFloat = 14
            let span = range.upperBound - range.lowerBound
            let fraction = CGFloat((value - range.lowerBound) / span)
            let zeroFraction = CGFloat((0 - range.lowerBound) / span)
            let y = (1 - fraction) * (h - knob) + knob / 2
            let zeroY = (1 - zeroFraction) * (h - knob) + knob / 2
            ZStack(alignment: .top) {
                Capsule().fill(Color.primary.opacity(0.12))
                    .frame(width: 4)
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: abs(zeroY - y))
                    .offset(y: min(zeroY, y))
                    .frame(maxWidth: .infinity)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                    .frame(width: knob, height: knob)
                    .offset(y: y - knob / 2)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let start = dragStart ?? value
                    if dragStart == nil { dragStart = value }
                    let delta = Float(-drag.translation.height / max(h - knob, 1)) * span
                    onChange(min(max(start + delta, range.lowerBound), range.upperBound))
                }
                .onEnded { _ in dragStart = nil })
            .simultaneousGesture(TapGesture(count: 2).onEnded { onChange(0) })
        }
        .accessibilityElement()
        .accessibilityValue(String(format: "%.1f dB", value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 1, range.upperBound))
            case .decrement: onChange(max(value - 1, range.lowerBound))
            @unknown default: break
            }
        }
    }
}

/// Frequency response of the equalizer, computed from the real filters.
struct EQCurve: View {
    let gains: [Float]
    let enabled: Bool

    var body: some View {
        Canvas { context, size in
            let sr = 48000.0
            var filters: [Biquad] = []
            for i in 0..<min(gains.count, SoundSettings.bandCount) {
                let g = Double(gains[i]), f = SoundSettings.bandFrequencies[i]
                switch i {
                case 0: filters.append(.lowShelf(frequency: f * 1.4, gainDB: g, sampleRate: sr, slope: 0.8))
                case SoundSettings.bandCount - 1: filters.append(.highShelf(frequency: f * 0.7, gainDB: g, sampleRate: sr, slope: 0.8))
                default: filters.append(.peaking(frequency: f, q: 1.25, gainDB: g, sampleRate: sr))
                }
            }
            let mid = size.height / 2
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: mid))
            zero.addLine(to: CGPoint(x: size.width, y: mid))
            context.stroke(zero, with: .color(.primary.opacity(0.15)), lineWidth: 1)

            var curve = Path()
            let steps = 120
            for s in 0...steps {
                let t = Double(s) / Double(steps)
                let f = 20 * pow(1000, t) // 20 Hz … 20 kHz, logarithmic
                let db = filters.reduce(0) { $0 + $1.responseDB(at: f, sampleRate: sr) }
                let y = mid - CGFloat(max(min(db, 15), -15) / 15) * (mid - 3)
                let p = CGPoint(x: CGFloat(t) * size.width, y: y)
                if s == 0 { curve.move(to: p) } else { curve.addLine(to: p) }
            }
            context.stroke(curve, with: enabled ? .linearGradient(Gradient(colors: [Brand.lagoon, Brand.violet, Brand.rose]),
                                                                  startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
                                                : .color(.secondary),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Apps

private struct AppsTab: View {
    @ObservedObject var model: ReliefModel

    var body: some View {
        let apps = model.visibleApps
        VStack(alignment: .leading, spacing: 8) {
            if apps.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "music.note.list").font(.system(size: 24)).foregroundStyle(.tertiary)
                    Text(S.noApps).font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else if apps.count <= 5 {
                VStack(spacing: 6) {
                    ForEach(apps) { app in AppRow(model: model, app: app) }
                }
            } else {
                // A scroll view has no natural height in a popover: give it one.
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(apps) { app in AppRow(model: model, app: app) }
                    }
                }
                .frame(height: 300)
            }
            Text(S.appsHint).font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AppRow: View {
    @ObservedObject var model: ReliefModel
    let app: AudioApp

    var body: some View {
        let volume = model.volume(of: app)
        let custom = model.appVolumes[app.id] != nil
        HStack(spacing: 8) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "app").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if app.isPlaying {
                        Image(systemName: "waveform").font(.system(size: 9)).foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Text("\(Int((volume * 100).rounded())) %")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { Double(volume) }, set: { model.setVolume(Float($0), for: app) }),
                       in: 0...1.5)
                    .controlSize(.mini)
                }
            Button {
                model.toggleMute(app)
            } label: {
                Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help(volume == 0 ? S.unmute : S.mute)
            Button {
                model.resetVolume(for: app)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .opacity(custom ? 1 : 0)
            .disabled(!custom)
            .help(S.resetVolume)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
