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
                    Preview(theme: state.buttonTheme)
                }
                Text("Match System follows your Mac: grey with the Graphite accent colour, red, yellow and green otherwise.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Move buttons with the windows", isOn: Binding(
                    get: { state.moveWithWindows }, set: { state.setMoveWithWindows($0) }))
                Text("As Mission Control opens and closes, the buttons travel with the windows. Turn this off to have them simply fade in and out. MC Close also follows Reduce motion in your Mac's Accessibility settings.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}

/// The four buttons in the chosen colours, as they'll look in Mission Control.
private struct Preview: View {
    let theme: ButtonTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let resolved = theme.resolved(systemAccent: UserDefaults.standard.object(forKey: "AppleAccentColor") as? Int)
        HStack(spacing: 6) {
            ForEach(WindowAction.buttons, id: \.self) { action in
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
