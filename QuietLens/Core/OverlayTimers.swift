import Foundation

/// Owns delayed enable/disable requests independently of whether an overlay
/// transition actually changes state. Canceled callbacks can already be queued.
@MainActor
final class OverlayTimers {
    typealias Scheduler = @MainActor (
        _ seconds: TimeInterval,
        _ tolerance: TimeInterval,
        _ fire: @escaping @MainActor () -> Void
    ) -> (@MainActor () -> Void)

    private let isEnabled: () -> Bool
    private let requestEnabled: (Bool) -> Void
    private let scheduleTimer: Scheduler
    private var cancelPauseTimer: (() -> Void)?
    private var cancelAutoDisableTimer: (() -> Void)?
    private var pauseGeneration: UInt64 = 0
    private var autoDisableGeneration: UInt64 = 0
    /// Explicit off requests and pauses suppress automatic enable on focus.
    private(set) var userDisabledOverlay = false

    init(isEnabled: @escaping () -> Bool,
         requestEnabled: @escaping (Bool) -> Void,
         scheduleTimer: @escaping Scheduler = OverlayTimers.scheduleOnMainRunLoop) {
        self.isEnabled = isEnabled
        self.requestEnabled = requestEnabled
        self.scheduleTimer = scheduleTimer
    }

    func setEnabled(_ on: Bool) {
        cancelPause()
        if !on { cancelAutoDisable() }
        userDisabledOverlay = !on
        requestEnabled(on)
    }

    func pause(for seconds: TimeInterval) {
        guard isEnabled() else { return }
        cancelPause()
        cancelAutoDisable()
        userDisabledOverlay = true
        requestEnabled(false)

        let generation = pauseGeneration
        cancelPauseTimer = scheduleTimer(seconds, 5) { [weak self] in
            guard let self, self.pauseGeneration == generation else { return }
            self.setEnabled(true)
        }
    }

    func scheduleAutoDisable(enabled: Bool, after seconds: TimeInterval?) {
        cancelAutoDisable()
        guard enabled, let seconds else { return }

        let generation = autoDisableGeneration
        cancelAutoDisableTimer = scheduleTimer(seconds, min(30, seconds * 0.05)) { [weak self] in
            guard let self, self.autoDisableGeneration == generation,
                  self.isEnabled() else { return }
            self.cancelAutoDisable()
            self.setEnabled(false)
        }
    }

    func cancelPause() {
        pauseGeneration &+= 1
        cancelPauseTimer?()
        cancelPauseTimer = nil
    }

    private func cancelAutoDisable() {
        autoDisableGeneration &+= 1
        cancelAutoDisableTimer?()
        cancelAutoDisableTimer = nil
    }

    func cancelAll() {
        cancelPause()
        cancelAutoDisable()
    }

    static func scheduleOnMainRunLoop(seconds: TimeInterval,
                                      tolerance: TimeInterval,
                                      fire: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in fire() }
        }
        timer.tolerance = tolerance
        return { timer.invalidate() }
    }
}
