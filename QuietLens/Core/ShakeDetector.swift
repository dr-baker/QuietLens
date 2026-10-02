import AppKit
import Combine

@MainActor
final class ShakeDetector {
    struct EventMonitors {
        var addGlobal: (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
        var addLocal: (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?
        var remove: (Any) -> Void

        static let system = EventMonitors(
            addGlobal: { NSEvent.addGlobalMonitorForEvents(matching: $0, handler: $1) },
            addLocal: { NSEvent.addLocalMonitorForEvents(matching: $0, handler: $1) },
            remove: { NSEvent.removeMonitor($0) }
        )
    }

    var onShake: (() -> Void)?
    var onPeekStart: (() -> Void)?
    var onPeekEnd: (() -> Void)?

    private let settings: QuietLensSettings
    private let eventMonitors: EventMonitors
    private let currentTime: () -> TimeInterval
    private let mouseLocation: () -> CGPoint
    private let modifierFlags: () -> NSEvent.ModifierFlags
    private var monitors: [Any] = []
    private var started = false
    private var monitoring = false
    private var settingsSubscription: AnyCancellable?
    private var monitorGeneration: UInt64 = 0
    private var samples: [(t: TimeInterval, p: CGPoint)] = []
    private var lastSampleTime: TimeInterval = 0
    private var lastTriggerTime: TimeInterval = 0
    private var currentFlags: NSEvent.ModifierFlags = []
    private var peeking: Bool = false
    private var peekResetWork: DispatchWorkItem?
    private var peekGeneration: UInt64 = 0

    init(settings: QuietLensSettings,
         eventMonitors: EventMonitors = .system,
         currentTime: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
         mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
         modifierFlags: @escaping () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }) {
        self.settings = settings
        self.eventMonitors = eventMonitors
        self.currentTime = currentTime
        self.mouseLocation = mouseLocation
        self.modifierFlags = modifierFlags
    }

    deinit {
        for monitor in monitors { eventMonitors.remove(monitor) }
        peekResetWork?.cancel()
    }

    func start() {
        guard !started else { return }
        started = true
        settingsSubscription = settings.$shakeEnabled.removeDuplicates().sink { [weak self] enabled in
            if enabled {
                self?.startMonitoring()
            } else {
                self?.stopMonitoring()
            }
        }
    }

    private func startMonitoring() {
        guard started, !monitoring else { return }
        monitoring = true
        monitorGeneration &+= 1
        let generation = monitorGeneration
        currentFlags = modifierFlags()
        // Event-driven sampling instead of a 60 Hz polling timer: zero CPU
        // while the pointer is idle. Global monitors cover other apps; local
        // monitors cover our own windows (global monitors skip the active app).
        // Mouse-move global monitors need no extra TCC permission.
        let moveEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        // NSEvent delivers both monitor kinds on the main thread. Sample
        // directly so high-rate mouse events do not enqueue one task each.
        if let m = eventMonitors.addGlobal(moveEvents, { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.monitoring, self.monitorGeneration == generation else { return }
                self.sample()
            }
        }) { monitors.append(m) }
        if let m = eventMonitors.addLocal(moveEvents, { [weak self] ev in
            MainActor.assumeIsolated {
                guard let self, self.monitoring, self.monitorGeneration == generation else { return }
                self.sample()
            }
            return ev
        }) { monitors.append(m) }
        if let m = eventMonitors.addGlobal(.flagsChanged, { [weak self] ev in
            let flags = ev.modifierFlags
            MainActor.assumeIsolated {
                guard let self, self.monitoring, self.monitorGeneration == generation else { return }
                self.currentFlags = flags
            }
        }) { monitors.append(m) }
        if let m = eventMonitors.addLocal(.flagsChanged, { [weak self] ev in
            let flags = ev.modifierFlags
            MainActor.assumeIsolated {
                guard let self, self.monitoring, self.monitorGeneration == generation else { return }
                self.currentFlags = flags
            }
            return ev
        }) { monitors.append(m) }
    }

    func stop() {
        started = false
        settingsSubscription = nil
        stopMonitoring()
    }

    private func stopMonitoring() {
        monitoring = false
        monitorGeneration &+= 1
        for monitor in monitors { eventMonitors.remove(monitor) }
        monitors.removeAll()
        reset()
        lastSampleTime = 0
        lastTriggerTime = 0
        currentFlags = []
        peekGeneration &+= 1
        peekResetWork?.cancel()
        peekResetWork = nil
        if peeking {
            peeking = false
            onPeekEnd?()
        }
    }

    private func sample() {
        guard settings.shakeEnabled else {
            if !samples.isEmpty { reset() }
            return
        }
        let modifierWanted = settings.shakeModifier.flags
        if !modifierWanted.isEmpty && !currentFlags.contains(modifierWanted) {
            if !samples.isEmpty { reset() }
            return
        }
        let now = currentTime()
        // Cap the sampling rate so high-report-rate mice don't burn CPU.
        if now - lastSampleTime < 0.008 { return }
        lastSampleTime = now
        samples.append((now, mouseLocation()))
        samples.removeAll { now - $0.t > 0.6 }
        guard samples.count >= 3 else { return }

        var travel: CGFloat = 0
        var reversalCount = 0
        var lastVec = CGVector(dx: 0, dy: 0)
        for i in 1..<samples.count {
            let dx = samples[i].p.x - samples[i - 1].p.x
            let dy = samples[i].p.y - samples[i - 1].p.y
            let mag = sqrt(dx * dx + dy * dy)
            travel += mag
            guard mag > 1 else { continue }
            let nx = dx / mag, ny = dy / mag
            if lastVec.dx != 0 || lastVec.dy != 0 {
                let dot = nx * lastVec.dx + ny * lastVec.dy
                if dot < -0.3 { reversalCount += 1 }
            }
            lastVec = CGVector(dx: nx, dy: ny)
        }

        let sensitivity = settings.shakeSensitivity
        let requiredReversals = max(3, Int(7 - sensitivity * 4))
        let minTravel: CGFloat = CGFloat(500 - sensitivity * 300)

        if reversalCount >= requiredReversals && travel >= minTravel && (now - lastTriggerTime) > 0.6 {
            lastTriggerTime = now
            samples.removeAll()
            if !modifierWanted.isEmpty {
                if !peeking {
                    peeking = true
                    onPeekStart?()
                }
                schedulePeekEnd()
            } else {
                onShake?()
            }
        }
    }

    private func schedulePeekEnd() {
        peekResetWork?.cancel()
        peekGeneration &+= 1
        let generation = peekGeneration
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.monitoring, self.peeking, self.peekGeneration == generation else { return }
                self.peekGeneration &+= 1
                self.peekResetWork = nil
                self.peeking = false
                self.onPeekEnd?()
            }
        }
        peekResetWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    private func reset() {
        samples.removeAll()
    }
}
