import Foundation

@MainActor
private final class TimerFixture {
    final class Scheduled {
        let seconds: TimeInterval
        let tolerance: TimeInterval
        let fire: @MainActor () -> Void
        var cancellations = 0

        init(seconds: TimeInterval, tolerance: TimeInterval, fire: @escaping @MainActor () -> Void) {
            self.seconds = seconds
            self.tolerance = tolerance
            self.fire = fire
        }
    }

    var scheduled: [Scheduled] = []

    func schedule(seconds: TimeInterval, tolerance: TimeInterval,
                  fire: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let timer = Scheduled(seconds: seconds, tolerance: tolerance, fire: fire)
        scheduled.append(timer)
        return { timer.cancellations += 1 }
    }
}

@main
struct OverlayTimerCancellationCheck {
    @MainActor
    static func main() {
        let fixture = TimerFixture()
        var enabled = true
        var requests: [Bool] = []
        let timers = OverlayTimers(isEnabled: { enabled }, requestEnabled: {
            enabled = $0
            requests.append($0)
        }, scheduleTimer: fixture.schedule)

        timers.pause(for: 300)
        let paused = fixture.scheduled[0]
        precondition(!enabled && timers.userDisabledOverlay)
        precondition(paused.seconds == 300 && paused.tolerance == 5)
        // The overlay is already off, so no state-change notification occurs.
        timers.setEnabled(false)
        precondition(paused.cancellations == 1)
        let requestCount = requests.count
        paused.fire() // Simulate a callback queued before cancellation.
        precondition(!enabled && requests.count == requestCount)

        timers.setEnabled(true)
        timers.pause(for: 300)
        let manuallyResumed = fixture.scheduled[1]
        timers.setEnabled(true)
        precondition(manuallyResumed.cancellations == 1 && !timers.userDisabledOverlay)
        let resumedCount = requests.count
        manuallyResumed.fire()
        precondition(enabled && requests.count == resumedCount)

        timers.pause(for: 300)
        let normalPause = fixture.scheduled[2]
        normalPause.fire()
        precondition(enabled && !timers.userDisabledOverlay && normalPause.cancellations == 1)
        let completedCount = requests.count
        normalPause.fire()
        precondition(requests.count == completedCount)

        timers.scheduleAutoDisable(enabled: true, after: 300)
        let replaced = fixture.scheduled[3]
        timers.scheduleAutoDisable(enabled: true, after: 600)
        let replacement = fixture.scheduled[4]
        precondition(replaced.cancellations == 1)
        precondition(replacement.seconds == 600 && replacement.tolerance == 30)
        replaced.fire()
        precondition(enabled)
        replacement.fire()
        precondition(!enabled && timers.userDisabledOverlay && replacement.cancellations == 1)
        let autoDisabledCount = requests.count
        replacement.fire()
        precondition(requests.count == autoDisabledCount)

        timers.setEnabled(true)
        timers.scheduleAutoDisable(enabled: true, after: 300)
        let changedToNever = fixture.scheduled[5]
        timers.scheduleAutoDisable(enabled: true, after: nil)
        changedToNever.fire()
        precondition(enabled && changedToNever.cancellations == 1)

        timers.scheduleAutoDisable(enabled: true, after: 300)
        let olderEnable = fixture.scheduled[6]
        timers.setEnabled(false)
        timers.setEnabled(true)
        timers.scheduleAutoDisable(enabled: true, after: 600)
        let newerEnable = fixture.scheduled[7]
        olderEnable.fire()
        precondition(enabled && olderEnable.cancellations == 1)
        timers.cancelAll()
        newerEnable.fire()
        precondition(enabled && newerEnable.cancellations == 1)

        let scheduledCount = fixture.scheduled.count
        timers.setEnabled(false)
        timers.scheduleAutoDisable(enabled: false, after: 300)
        timers.pause(for: 300)
        precondition(fixture.scheduled.count == scheduledCount)
        print("Pause intent, timer replacement, queued canceled callbacks, and auto-disable: passed")
    }
}
