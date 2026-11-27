import SwiftUI

/// Settings: how the buttons look, which shortcuts are on, and Start at Login.
struct SettingsView: View {
    @ObservedObject var state: AppState
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Window buttons") {
                Toggle("Show buttons on windows in Mission Control", isOn: Binding(
                    get: { state.showCloseButton }, set: { state.setShowCloseButton($0) }))
                HStack(spacing: 12) {
                    Picker("Colours", selection: Binding(get: { state.buttonTheme }, set: { state.setButtonTheme($0) })) {
                        ForEach(ButtonTheme.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                    Preview(theme: state.buttonTheme, actions: state.buttons.visible)
                }
                Text("Match System follows your Mac: grey with the Graphite accent colour, red, yellow and green otherwise.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Move buttons with the windows", isOn: Binding(
                    get: { state.moveWithWindows }, set: { state.setMoveWithWindows($0) }))
                Text("As Mission Control opens and closes, and as its thumbnails move, the buttons travel with the windows. Turn this off to have them simply fade in and out and jump to the thumbnails' new places. MC Close also follows Reduce motion in your Mac's Accessibility settings.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("Buttons on each window") {
                Text("Tick the buttons you want and drag them into any order. The row starts over the window's own controls.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                List {
                    ForEach(Array(state.buttons.items.enumerated()), id: \.element.action) { index, item in
                        HStack(spacing: 10) {
                            Toggle("Show \(item.action.label)", isOn: Binding(
                                get: { item.shown },
                                set: { on in var c = state.buttons; c.setShown(item.action, on); state.setButtons(c) }))
                                .labelsHidden()
                            Swatch(action: item.action, theme: state.buttonTheme)
                            Text(item.action.label)
                            Spacer()
                            Text(Shortcut.keys(for: item.action)).foregroundStyle(.secondary)
                            Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.borderless).disabled(index == 0)
                                .accessibilityLabel("Move \(item.action.label) up")
                            Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.borderless).disabled(index == state.buttons.items.count - 1)
                                .accessibilityLabel("Move \(item.action.label) down")
                        }
                    }
                    .onMove { from, to in
                        guard let f = from.first else { return }
                        var c = state.buttons
                        c.move(from: f, to: to > f ? to - 1 : to)
                        state.setButtons(c)
                    }
                }
                .frame(height: 196)
                HStack {
                    if state.buttons.visible.isEmpty {
                        Text("No buttons ticked: only the shortcuts work.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset to Standard") { state.setButtons(.standard) }
                        .disabled(state.buttons == .standard)
                }
            }

            section("Shortcuts in Mission Control") {
                Text("They act on the window under the pointer, and only while Mission Control is open.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(WindowAction.allCases, id: \.self) { action in
                        GridRow {
                            Toggle(isOn: Binding(get: { state.isShortcutEnabled(action) },
                                                 set: { state.setShortcut(action, enabled: $0) })) {
                                Text(action.label)
                            }
                            Text(Shortcut.keys(for: action)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }

            section("General") {
                Toggle("Start MC Close when I log in", isOn: Binding(
                    get: { state.startAtLogin }, set: { state.setStartAtLogin($0) }))
                HStack {
                    Text("Version \(AppState.version)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for Updates") { state.checkForUpdates(userInitiated: true) }
                }
            }

            HStack {
                Spacer()
                Button("Done") { close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func move(_ index: Int, by step: Int) {
        var c = state.buttons
        c.move(from: index, to: index + step)
        state.setButtons(c)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}

/// One button with its symbol, in the chosen colours (for the Buttons list).
private struct Swatch: View {
    let action: WindowAction
    let theme: ButtonTheme
    @Environment(\.colorScheme) private var scheme

    private var symbol: String {
        switch action {
        case .close: return "xmark"
        case .minimize: return "minus"
        case .fullScreen: return "arrow.up.left.and.arrow.down.right"
        case .zoom: return "plus"
        case .hideApp: return "eye.slash"
        case .quitApp: return "power"
        }
    }

    var body: some View {
        let resolved = theme.resolved(systemAccent: UserDefaults.standard.object(forKey: "AppleAccentColor") as? Int)
        let c = ButtonPalette.colors(action, theme: resolved, dark: scheme == .dark)
        ZStack {
            Circle().fill(Color(nsColor: c.fill))
            Circle().strokeBorder(Color(nsColor: c.rim), lineWidth: 0.5)
            Image(systemName: symbol).font(.system(size: 8, weight: .bold)).foregroundStyle(Color(nsColor: c.glyph))
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

/// The chosen buttons in the chosen colours, as they'll look in Mission Control.
private struct Preview: View {
    let theme: ButtonTheme
    let actions: [WindowAction]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let resolved = theme.resolved(systemAccent: UserDefaults.standard.object(forKey: "AppleAccentColor") as? Int)
        HStack(spacing: 6) {
            ForEach(actions, id: \.self) { action in
                let c = ButtonPalette.colors(action, theme: resolved, dark: scheme == .dark)
                Circle()
                    .fill(Color(nsColor: c.fill))
                    .overlay(Circle().strokeBorder(Color(nsColor: c.rim), lineWidth: 0.5))
                    .frame(width: 13, height: 13)
            }
        }
        .accessibilityLabel("Preview of the buttons in \(theme.label)")
    }
}
