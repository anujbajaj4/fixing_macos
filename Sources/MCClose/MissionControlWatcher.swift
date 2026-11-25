import Cocoa
import ApplicationServices

/// Detects when Mission Control opens and closes.
///
/// Mission Control is drawn by the Dock process. The Dock posts (undocumented) accessibility
/// notifications when it enters and leaves Mission Control, so we subscribe to those.
/// Nothing here polls: the app sits idle until the Dock sends a notification.
final class MissionControlWatcher {
    private(set) var isActive = false
    var onChange: ((Bool) -> Void)?
    /// How many of the notifications the Dock accepted (shown in the menu, for diagnosis).
    private(set) var subscribed = 0

    private var observer: AXObserver?
    private var launchObserver: NSObjectProtocol?
    private let notifications = [
        "AXExposeShowAllWindows",   // Mission Control opened
        "AXExposeShowFrontWindows", // App Exposé opened
        "AXExposeShowDesktop",      // Show Desktop
        "AXExposeExit",             // Mission Control closed
    ]

    func start() {
        attachToDock()

        // The Dock restarts sometimes (e.g. `killall Dock`). Re-attach when it does.
        guard launchObserver == nil else { return }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == "com.apple.dock" {
                Log.write("Dock relaunched; re-attaching")
                self?.setActive(false)
                // Give the Dock a moment to finish launching.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.attachToDock() }
            }
        }
    }

    private func attachToDock() {
        if let old = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .commonModes)
            observer = nil
        }
        subscribed = 0
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            Log.write("Dock is not running; can't watch Mission Control")
            return
        }

        let pid = dock.processIdentifier
        let dockElement = AXUIElementCreateApplication(pid)

        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<MissionControlWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.handle(notification as String)
        }

        var newObserver: AXObserver?
        let err = AXObserverCreate(pid, callback, &newObserver)
        guard err == .success, let newObserver else {
            Log.write("could not observe the Dock (AX error \(err.rawValue))")
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var results: [String] = []
        for name in notifications {
            let r = AXObserverAddNotification(newObserver, dockElement, name as CFString, refcon)
            if r == .success { subscribed += 1 }
            results.append("\(name)=\(r == .success ? "ok" : "error \(r.rawValue)")")
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        observer = newObserver
        Log.write("watching Dock pid \(pid): " + results.joined(separator: ", "))
    }

    private func handle(_ name: String) {
        Log.write("Dock says \(name)")
        setActive(name == "AXExposeShowAllWindows" || name == "AXExposeShowFrontWindows")
    }

    private func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        onChange?(active)
    }
}
