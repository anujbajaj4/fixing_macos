import SwiftUI
import ServiceManagement

// Entry point. A menu bar–only app: LSUIElement = YES in Info.plist, so no Dock icon.
@main
struct MCCloseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(systemName: state.trusted ? "xmark.rectangle" : "exclamationmark.triangle")
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        Text(state.headline)
        Text("In Mission Control, point at a window, then use its buttons or:")
        Text(Shortcut.summary)
        if let update = state.updateVersion {
            Button("Update to \(update)…") { state.installUpdate() }
        }
        Divider()
        if !state.trusted {
            Button("Set Up…") { AppDelegate.showWelcome() }
        }
        Toggle("Show Window Buttons", isOn: Binding(get: { state.showCloseButton },
                                                    set: { state.setShowCloseButton($0) }))
        Toggle("Start at Login", isOn: Binding(get: { state.startAtLogin },
                                               set: { state.setStartAtLogin($0) }))
        Divider()
        Button("Open Log") { NSWorkspace.shared.open(Log.url) }
        Button("Diagnose Mission Control…") { AppDelegate.diagnose() }
        Button("Check for Updates") { state.checkForUpdates(userInitiated: true) }
        if state.trusted {
            Button("Set Up…") { AppDelegate.showWelcome() }
        }
        Divider()
        Text("Version \(AppState.version)")
        Button("Quit MC Close") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

// MARK: - State shared by the menu, the welcome window and the delegate

final class AppState: ObservableObject {
    static let shared = AppState()
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    static let bundleID = Bundle.main.bundleIdentifier ?? "io.github.anujbajaj4.MCClose"
    static let repo = "anujbajaj4/fixing_macos"
    /// The installer from the Pages mirror, or from the release if the mirror isn't reachable.
    static let installCommand = "(curl -fsSL --connect-timeout 10 https://anujbajaj4.github.io/fixing_macos/install.sh"
        + " || curl -fsSL --connect-timeout 10 https://github.com/\(repo)/releases/latest/download/install.sh) | /bin/bash"

    @Published var trusted = AX.isTrusted(prompt: false)
    @Published var missionControlOpen = false
    @Published var startAtLogin = SMAppService.mainApp.status == .enabled
    @Published var showCloseButton = !UserDefaults.standard.bool(forKey: "HideCloseButton")
    @Published var updateVersion: String? = UserDefaults.standard.string(forKey: "UpdateAvailable")
        .flatMap { Version.isNewer($0, than: AppState.version) ? $0 : nil }

    var onShowCloseButtonChange: ((Bool) -> Void)?

    var headline: String {
        if !trusted { return "Needs Accessibility permission" }
        return missionControlOpen ? "Mission Control is open" : "MC Close is on"
    }

    func setShowCloseButton(_ on: Bool) {
        showCloseButton = on
        onShowCloseButtonChange?(on)
    }

    func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("Start at Login \(on ? "on" : "off") failed: \(error.localizedDescription)")
        }
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Opens System Settings at Accessibility and adds MC Close to the list (switched off).
    func requestAccessibility() {
        _ = AX.isTrusted(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Each new build has a new signature, and macOS keeps the old, now-useless entry
    /// switched on. Removing it lets macOS ask again for this build.
    func resetAccessibility() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", AppState.bundleID]
        try? p.run()
        p.waitUntilExit()
        Log.write("tccutil reset Accessibility exited \(p.terminationStatus)")
        requestAccessibility()
    }

    // MARK: Update check (GitHub, at most once every 30 days)

    func checkForUpdates(userInitiated: Bool = false) {
        let defaults = UserDefaults.standard
        if !userInitiated, let last = defaults.object(forKey: "LastUpdateCheck") as? Date,
           Date().timeIntervalSince(last) < 30 * 24 * 3600 { return }

        guard let url = URL(string: "https://api.github.com/repos/\(AppState.repo)/releases/latest") else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let tag = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["tag_name"] as? String
            DispatchQueue.main.async {
                guard let tag else {
                    // Offline or rate-limited: try again next launch, don't stamp.
                    if userInitiated { Self.alert("Couldn't check for updates", "Check your internet connection and try again.") }
                    return
                }
                defaults.set(Date(), forKey: "LastUpdateCheck")
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                if Version.isNewer(latest, than: AppState.version) {
                    let isNew = defaults.string(forKey: "UpdateAvailable") != latest
                    defaults.set(latest, forKey: "UpdateAvailable")
                    self.updateVersion = latest
                    Log.write("update available: \(latest)")
                    if userInitiated || isNew {
                        self.offerUpdate(latest)
                    }
                } else {
                    defaults.removeObject(forKey: "UpdateAvailable")
                    self.updateVersion = nil
                    if userInitiated { Self.alert("MC Close is up to date", "You have version \(AppState.version), the latest.") }
                }
            }
        }.resume()
    }

    private func offerUpdate(_ latest: String) {
        let alert = NSAlert()
        alert.messageText = "MC Close \(latest) is available"
        alert.informativeText = "You have \(AppState.version). Updating takes a few seconds and reopens MC Close."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { installUpdate() }
    }

    /// Runs the same one-line installer as a first install. It quits this app,
    /// replaces it, and opens the new version.
    func installUpdate() {
        Log.write("installing update via installer")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", AppState.installCommand + " >> \"$HOME/Library/Logs/MCClose-update.log\" 2>&1"]
        do { try p.run() } catch {
            Self.alert("Update failed to start", "Paste this into Terminal instead:\n\n\(AppState.installCommand)")
        }
    }

    static func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - App delegate: wires the pieces together

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static weak var current: AppDelegate?
    private let watcher = MissionControlWatcher()
    private let keyTap = KeyTap()
    private let overlay = WindowButtonsOverlay()
    private var permissionTimer: Timer?
    private var started = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.current = self
        let state = AppState.shared
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        Log.write("MC Close \(AppState.version) launched on macOS \(os); Accessibility \(state.trusted ? "granted" : "not granted")")

        state.onShowCloseButtonChange = { [weak self] on in
            guard let self else { return }
            self.overlay.showButtons = on
        }

        if state.trusted {
            startEverything()
        } else {
            AppDelegate.showWelcome()
        }
        // Keep an eye on the permission: it can be granted, or revoked, at any time.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }
        state.checkForUpdates()
    }

    private func checkPermission() {
        let state = AppState.shared
        let trusted = AX.isTrusted(prompt: false)
        if trusted != state.trusted {
            state.trusted = trusted
            Log.write("Accessibility permission \(trusted ? "granted" : "removed")")
        }
        if trusted && !started { startEverything() }
    }

    private func startEverything() {
        guard !started else { return }
        started = true

        // Shortcuts act only while Mission Control is open and the pointer is on a window.
        keyTap.isActive = { [weak self] in self?.watcher.isActive ?? false }
        keyTap.isPointerOnThumbnail = { [weak self] in self?.overlay.isPointerOnThumbnail() ?? false }
        keyTap.onShortcut = { action in WindowCloser.performUnderMouse(action) }
        // Clicks on the buttons are caught by the tap: Mission Control would take them otherwise.
        keyTap.buttonAt = { [weak self] point in self?.overlay.button(at: point) }
        keyTap.onButton = { [weak self] action in self?.overlay.perform(action) }
        if !keyTap.start() {
            // The permission can take a moment to apply to a running app; try again shortly.
            started = false
            return
        }

        // Track thumbnails (and show the buttons) while Mission Control is open.
        watcher.onChange = { [weak self] active in
            AppState.shared.missionControlOpen = active
            if active { self?.overlay.start() } else { self?.overlay.stop() }
        }
        watcher.start()
    }

    static func diagnose() {
        guard let d = current else { return }
        Diagnostics.run(watcherActive: { [weak d] in d?.watcher.isActive ?? false },
                        watcherSource: { [weak d] in d?.watcher.lastSource ?? "" })
    }

    static func showWelcome() {
        AppWindow.welcome.show { close in WelcomeView(state: AppState.shared, close: close) }
    }
}

// MARK: - Windows hosted in AppKit (SwiftUI Window scenes don't open reliably in menu-bar apps)

final class AppWindow {
    static let welcome = AppWindow(title: "Welcome to MC Close")
    private let title: String
    private var window: NSWindow?
    init(title: String) { self.title = title }

    func show<Content: View>(_ content: (_ close: @escaping () -> Void) -> Content) {
        if window?.isVisible != true {
            let hosting = NSHostingController(rootView: content { [weak self] in self?.window?.close() })
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.title = title
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()   // macOS 14+ won't take focus from Terminal; this still puts it on top
    }
}

struct WelcomeView: View {
    @ObservedObject var state: AppState
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Control windows from Mission Control")
                .font(.title2.bold())
            Text("Open Mission Control and point at a window. Buttons appear on its corner: close, minimize, full screen and zoom (+ fills the screen without a separate space, like Option-clicking the green button).")
                .fixedSize(horizontal: false, vertical: true)
            Text("Shortcuts: " + Shortcut.summary)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    StepIcon(done: state.trusted)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Allow Accessibility").bold()
                        if state.trusted {
                            Text("Done. MC Close can see Mission Control and close windows.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("In System Settings, switch on MC Close under Privacy & Security ▸ Accessibility. This step ticks by itself.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("Open Accessibility Settings") { state.requestAccessibility() }
                                    .keyboardShortcut(.defaultAction)
                                Button("Reset Permission") { state.resetAccessibility() }
                                    .help("Use this if MC Close is already switched on but this step doesn't tick.")
                            }
                            Text("Already switched on but no tick? Click Reset Permission, then switch it on again.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                GridRow {
                    StepIcon(done: state.startAtLogin)
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Start MC Close when I log in", isOn: Binding(
                            get: { state.startAtLogin }, set: { state.setStartAtLogin($0) }))
                            .bold()
                        Text("Optional. You can change this later from the menu bar icon.")
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Image(systemName: "rectangle.3.group").frame(width: 20)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Try it").bold()
                        Text("Press F3 or swipe up with three fingers, point at a window, click a button or press ⌘M.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()
            HStack(alignment: .top) {
                Image(systemName: "xmark.rectangle")
                Text("MC Close lives in the menu bar at the top right. If you can't see it, the notch may be hiding it.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(state.trusted ? "Done" : "Later") { close() }
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct StepIcon: View {
    let done: Bool
    var body: some View {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? Color.green : Color.secondary)
            .frame(width: 20)
    }
}
