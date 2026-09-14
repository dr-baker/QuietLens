import AppKit

/// Detects the Dock-owned windows macOS creates for Mission Control and
/// App Expose. AppKit publishes space changes, but it has no public lifecycle
/// notification for entering and leaving these overview modes.
@MainActor
final class OverviewDetector {
    enum Phase: Equatable {
        case inactive
        case active
        case exiting
    }

    nonisolated static let exitBlendDuration: TimeInterval = 0.18

    private let onChange: (Phase) -> Void
    private let dockPID: pid_t?
    private var timer: Timer?
    private var clickMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var phase: Phase = .inactive
    private var overviewBeganAt: TimeInterval = 0
    private var exitBeganAt: TimeInterval = 0
    private var exitWasHinted = false

    init(onChange: @escaping (Phase) -> Void) {
        self.onChange = onChange
        dockPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?
            .processIdentifier
    }

    func start() {
        guard timer == nil else { return }
        evaluate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        timer.tolerance = 0.01
        self.timer = timer

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.noteSelectionStarted() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.noteSelectionStarted() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        transition(to: .inactive)
    }

    /// A click, app activation, or focused-window change while the overview
    /// still exists marks the beginning of its return animation.
    func noteSelectionStarted() {
        guard phase == .active,
              ProcessInfo.processInfo.systemUptime - overviewBeganAt >= 0.12 else { return }
        beginExit(hinted: true)
    }

    private func evaluate() {
        let overviewExists = Self.isOverviewActive(dockPID: dockPID)
        let now = ProcessInfo.processInfo.systemUptime

        switch phase {
        case .inactive:
            if overviewExists {
                overviewBeganAt = now
                transition(to: .active)
            }
        case .active:
            if !overviewExists {
                // A keyboard or gesture exit can avoid both public hints. In
                // that case, hold a short full-screen transition after the
                // Dock surfaces disappear instead of flashing the final mask.
                beginExit(hinted: false)
            }
        case .exiting:
            if !overviewExists {
                let minimumHold = exitWasHinted ? Self.exitBlendDuration : 0.16
                if now - exitBeganAt >= minimumHold {
                    transition(to: .inactive)
                }
            } else if now - exitBeganAt > 0.8 {
                // A click can select or drag an overview window without
                // leaving the overview. Return to the settled state.
                overviewBeganAt = now - 0.12
                transition(to: .active)
            }
        }
    }

    private func beginExit(hinted: Bool) {
        guard phase == .active else { return }
        exitBeganAt = ProcessInfo.processInfo.systemUptime
        exitWasHinted = hinted
        transition(to: .exiting)
    }

    private func transition(to newPhase: Phase) {
        guard phase != newPhase else { return }
        phase = newPhase
        onChange(newPhase)
    }

    private static func isOverviewActive(dockPID: pid_t?) -> Bool {
        guard let dockPID else { return false }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else { return false }

        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == dockPID,
                  let layer = window[kCGWindowLayer as String] as? Int else { return false }

            // Mission Control and App Expose create Dock-owned app-icon
            // windows on layer 17 and large overview surfaces on layer 18.
            let name = window[kCGWindowName as String] as? String
            return (layer == 17 && name == "appicon") || layer == 18
        }
    }
}
