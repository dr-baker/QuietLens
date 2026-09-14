import AppKit

/// Detects the Dock-owned windows macOS creates for Mission Control and
/// App Expose. AppKit publishes space changes, but it has no public lifecycle
/// notification for entering and leaving these overview modes.
@MainActor
final class OverviewDetector {
    private let onChange: (Bool) -> Void
    private let dockPID: pid_t?
    private var timer: Timer?
    private var lastValue = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        dockPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?
            .processIdentifier
    }

    func start() {
        guard timer == nil else { return }
        evaluate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        timer.tolerance = 0.02
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if lastValue {
            lastValue = false
            onChange(false)
        }
    }

    private func evaluate() {
        let currentValue = Self.isOverviewActive(dockPID: dockPID)
        guard currentValue != lastValue else { return }
        lastValue = currentValue
        onChange(currentValue)
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
