import AppKit

/// Identifies the Dock process used by each asynchronous overview snapshot.
/// A result from an earlier Dock instance or detector run must not change the
/// current phase, even if its window query completes after a replacement.
struct OverviewDockIdentity {
    private(set) var pid: pid_t?
    private(set) var generation = 0

    mutating func start(pid: pid_t?) {
        generation += 1
        self.pid = pid
    }

    mutating func stop() {
        generation += 1
        pid = nil
    }

    mutating func didLaunch(pid: pid_t) -> Bool {
        guard self.pid != pid else { return false }
        generation += 1
        self.pid = pid
        return true
    }

    mutating func didTerminate(pid: pid_t) -> Bool {
        guard self.pid == pid else { return false }
        generation += 1
        self.pid = nil
        return true
    }

    func accepts(pid: pid_t, generation: Int) -> Bool {
        self.pid == pid && self.generation == generation
    }
}

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
    private var dockIdentity = OverviewDockIdentity()
    private var lifecycleGeneration = 0
    private var timer: Timer?
    private var evaluationPending = false
    private var clickMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var dockLaunchObserver: NSObjectProtocol?
    private var dockTerminationObserver: NSObjectProtocol?
    private var phase: Phase = .inactive
    private var overviewBeganAt: TimeInterval = 0
    private var exitBeganAt: TimeInterval = 0
    private var exitWasHinted = false
    private(set) var exitSelectionLocation: CGPoint?

    init(onChange: @escaping (Phase) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard timer == nil else { return }
        lifecycleGeneration += 1
        observeDockLifecycle(generation: lifecycleGeneration)
        dockIdentity.start(pid: Self.currentDockPID())
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        timer.tolerance = 0.01
        self.timer = timer
        evaluate()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let location = event.locationInWindow
            Task { @MainActor in self?.noteSelectionStarted(at: location) }
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
        lifecycleGeneration += 1
        dockIdentity.stop()
        evaluationPending = false
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
        if let dockLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(dockLaunchObserver)
            self.dockLaunchObserver = nil
        }
        if let dockTerminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(dockTerminationObserver)
            self.dockTerminationObserver = nil
        }
        transition(to: .inactive)
    }

    private static func currentDockPID() -> pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .max { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }?
            .processIdentifier
    }

    private static func isDockRunning(pid: pid_t) -> Bool {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .contains { $0.processIdentifier == pid }
    }

    private func observeDockLifecycle(generation: Int) {
        let center = NSWorkspace.shared.notificationCenter
        dockLaunchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.dock" else { return }
            let pid = app.processIdentifier
            Task { @MainActor in
                guard self?.lifecycleGeneration == generation else { return }
                self?.dockDidLaunch(pid: pid)
            }
        }
        dockTerminationObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.dock" else { return }
            let pid = app.processIdentifier
            Task { @MainActor in
                guard self?.lifecycleGeneration == generation else { return }
                self?.dockDidTerminate(pid: pid)
            }
        }
    }

    private func dockDidLaunch(pid: pid_t) {
        guard timer != nil, Self.isDockRunning(pid: pid),
              dockIdentity.didLaunch(pid: pid) else { return }
        evaluationPending = false
        transition(to: .inactive)
        evaluate()
    }

    private func dockDidTerminate(pid: pid_t) {
        guard timer != nil, dockIdentity.didTerminate(pid: pid) else { return }
        evaluationPending = false
        transition(to: .inactive)
    }

    /// A click, app activation, or focused-window change while the overview
    /// still exists marks the beginning of its return animation.
    func noteSelectionStarted(at location: CGPoint? = nil) {
        guard phase == .active,
              ProcessInfo.processInfo.systemUptime - overviewBeganAt >= 0.12 else { return }
        beginExit(hinted: true, selectionLocation: location)
    }

    private func evaluate() {
        guard !evaluationPending, let dockPID = dockIdentity.pid else { return }
        evaluationPending = true
        let generation = dockIdentity.generation
        DispatchQueue.global(qos: .userInitiated).async {
            let overviewExists = Self.isOverviewActive(dockPID: dockPID)
            DispatchQueue.main.async { [weak self] in
                self?.finishEvaluation(overviewExists, dockPID: dockPID, generation: generation)
            }
        }
    }

    private func finishEvaluation(_ overviewExists: Bool, dockPID: pid_t, generation: Int) {
        guard dockIdentity.accepts(pid: dockPID, generation: generation), timer != nil else { return }
        evaluationPending = false
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
                beginExit(hinted: false, selectionLocation: nil)
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

    private func beginExit(hinted: Bool, selectionLocation: CGPoint?) {
        guard phase == .active else { return }
        exitBeganAt = ProcessInfo.processInfo.systemUptime
        exitWasHinted = hinted
        exitSelectionLocation = selectionLocation
        transition(to: .exiting)
    }

    private func transition(to newPhase: Phase) {
        guard phase != newPhase else { return }
        phase = newPhase
        if newPhase != .exiting {
            exitSelectionLocation = nil
        }
        onChange(newPhase)
    }

    private nonisolated static func isOverviewActive(dockPID: pid_t?) -> Bool {
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
