import AppKit
import Carbon
import Combine

// Monitor tests do not read or write the user's persistent settings.
@MainActor
final class QuietLensSettings: ObservableObject {
    @Published var shakeEnabled = false
    var shakeSensitivity = 1.0
    var shakeModifier = ShakeModifier.none
    var toggleShortcutKey: UInt16?
    var toggleShortcutMods: UInt = 0
    var settingsShortcutKey: UInt16?
    var settingsShortcutMods: UInt = 0
    var excludeAppShortcutKey: UInt16?
    var excludeAppShortcutMods: UInt = 0
    var pinShortcutKey: UInt16?
    var pinShortcutMods: UInt = 0
}

enum ShakeModifier {
    case none, shift
    var flags: NSEvent.ModifierFlags { self == .shift ? .shift : [] }
}

@MainActor
private final class MonitorFixture {
    struct Registration {
        let token: UUID
        let events: NSEvent.EventTypeMask
        let deliver: (NSEvent) -> Void
    }

    var active: [UUID: Registration] = [:]
    var registrations: [Registration] = []
    var removals = 0

    var dependencies: ShakeDetector.EventMonitors {
        ShakeDetector.EventMonitors(
            addGlobal: { [self] events, handler in add(events: events, deliver: handler) },
            addLocal: { [self] events, handler in
                add(events: events, deliver: { event in precondition(handler(event) === event) })
            },
            remove: { [self] token in
                guard let token = token as? UUID else { preconditionFailure("Unexpected monitor token") }
                precondition(active.removeValue(forKey: token) != nil)
                removals += 1
            }
        )
    }

    private func add(events: NSEvent.EventTypeMask, deliver: @escaping (NSEvent) -> Void) -> UUID {
        let registration = Registration(token: UUID(), events: events, deliver: deliver)
        registrations.append(registration)
        active[registration.token] = registration
        return registration.token
    }

    func deliverMove(_ event: NSEvent) {
        guard let monitor = active.values.first(where: { $0.events.contains(.mouseMoved) }) else {
            preconditionFailure("Expected an active mouse monitor")
        }
        monitor.deliver(event)
    }
}

private final class CountingNotificationCenter: NotificationCenter, @unchecked Sendable {
    var additions = 0
    var removals = 0
    var deliveries = 0

    override func addObserver(forName name: NSNotification.Name?, object obj: Any?,
                              queue: OperationQueue?, using block: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        additions += 1
        return super.addObserver(forName: name, object: obj, queue: queue) { [weak self] notification in
            self?.deliveries += 1
            block(notification)
        }
    }

    override func removeObserver(_ observer: Any) {
        removals += 1
        super.removeObserver(observer)
    }
}

@main
struct InputMonitorLifecycleCheck {
    @MainActor
    static func main() async {
        let settings = QuietLensSettings()
        let fixture = MonitorFixture()
        var time: TimeInterval = 100
        var point = CGPoint.zero
        var flags: NSEvent.ModifierFlags = []
        var positionReads = 0
        let detector = ShakeDetector(settings: settings, eventMonitors: fixture.dependencies,
                                     currentTime: { time }, mouseLocation: {
            positionReads += 1
            return point
        }, modifierFlags: { flags })
        var overlayEnabled = false
        var shakes = 0
        var peekStarts = 0
        var peekEnds = 0
        detector.onShake = { overlayEnabled.toggle(); shakes += 1 }
        detector.onPeekStart = { peekStarts += 1 }
        detector.onPeekEnd = { peekEnds += 1 }
        guard let move = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
                                            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                            clickCount: 0, pressure: 0) else {
            preconditionFailure("Could not construct mouse event")
        }

        detector.start()
        detector.start()
        precondition(fixture.active.isEmpty && fixture.registrations.isEmpty)
        settings.shakeEnabled = true
        precondition(fixture.active.count == 4 && fixture.registrations.count == 4)
        detector.start()
        settings.shakeEnabled = true
        precondition(fixture.registrations.count == 4)

        for x in [0.0, 100, 0, 100, 0] {
            time += 0.016
            point.x = x
            fixture.deliverMove(move)
        }
        precondition(overlayEnabled && shakes == 1, "Shake must still enable an inactive overlay")
        let readsBeforeThrottle = positionReads
        for _ in 0..<100 { fixture.deliverMove(move) }
        precondition(positionReads == readsBeforeThrottle)
        let retired = fixture.registrations
        settings.shakeEnabled = false
        precondition(fixture.active.isEmpty && fixture.removals == 4)
        for registration in retired where registration.events.contains(.mouseMoved) { registration.deliver(move) }
        precondition(positionReads == readsBeforeThrottle)

        // Stop also resets partial samples and cooldowns before the next run.
        settings.shakeEnabled = true
        for x in [0.0, 100, 0] {
            time += 0.016
            point.x = x
            fixture.deliverMove(move)
        }
        settings.shakeEnabled = false
        settings.shakeEnabled = true
        for x in [100.0, 0] {
            time += 0.016
            point.x = x
            fixture.deliverMove(move)
        }
        precondition(shakes == 1, "Restart must discard the previous partial shake")
        for registration in retired where registration.events.contains(.mouseMoved) { registration.deliver(move) }
        precondition(shakes == 1)

        settings.shakeEnabled = false
        settings.shakeModifier = .shift
        flags = .shift
        settings.shakeEnabled = true
        for x in [0.0, 100, 0, 100, 0] {
            time += 0.016
            point.x = x
            fixture.deliverMove(move)
        }
        precondition(peekStarts == 1 && peekEnds == 0)
        settings.shakeEnabled = false
        precondition(peekEnds == 1 && fixture.active.isEmpty)
        detector.stop()
        detector.stop()
        precondition(peekEnds == 1)
        settings.shakeEnabled = true
        precondition(fixture.active.isEmpty, "Stopped detectors must stop observing settings")
        detector.start()
        precondition(fixture.active.count == 4)
        detector.stop()
        precondition(fixture.removals == fixture.registrations.count)

        let disposedFixture = MonitorFixture()
        var disposedDetector: ShakeDetector? = ShakeDetector(settings: settings, eventMonitors: disposedFixture.dependencies)
        disposedDetector?.start()
        precondition(disposedFixture.active.count == 4)
        disposedDetector = nil
        precondition(disposedFixture.active.isEmpty && disposedFixture.removals == 4)

        let center = CountingNotificationCenter()
        var manager: HotkeyManager? = HotkeyManager(settings: settings, notificationCenter: center)
        var hotkeyCalls = 0
        manager?.onToggle = { hotkeyCalls += 1 }
        manager?.start()
        manager?.start()
        precondition(center.additions == 1)
        sendHotkey(1, to: manager)
        await nextMainQueueTurn()
        precondition(hotkeyCalls == 1)
        center.post(name: .quietLensShortcutChanged, object: nil)
        precondition(center.deliveries == 1)
        sendHotkey(1, to: manager)
        manager?.stop()
        manager?.stop()
        precondition(center.removals == 1)
        center.post(name: .quietLensShortcutChanged, object: nil)
        precondition(center.deliveries == 1)
        manager?.start()
        manager?.start()
        precondition(center.additions == 2)
        await nextMainQueueTurn()
        precondition(hotkeyCalls == 1, "Queued keys from the prior registration must be ignored")
        sendHotkey(1, to: manager)
        await nextMainQueueTurn()
        precondition(hotkeyCalls == 2)
        center.post(name: .quietLensShortcutChanged, object: nil)
        precondition(center.deliveries == 2)
        manager = nil
        precondition(center.removals == 2)
        center.post(name: .quietLensShortcutChanged, object: nil)
        precondition(center.deliveries == 2)
        print("Shake setting lifecycle, event throttling, peek cleanup, and hotkey observer ownership: passed")
    }

    private static func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor private static func sendHotkey(_ id: UInt32, to manager: HotkeyManager?) {
        guard let manager else { preconditionFailure("Expected a live hotkey manager") }
        var event: EventRef?
        guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                          0, UInt32(kEventAttributeNone), &event) == noErr, let event else {
            preconditionFailure("Could not create hotkey event")
        }
        defer { ReleaseEvent(event) }
        var key = EventHotKeyID(signature: 0x514C454E, id: id)
        precondition(SetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &key) == noErr)
        // A call-chain ref differs from the ref returned by InstallEventHandler.
        // Dispatch the actual callback with no call-chain to prove it is ignored.
        let result = HotkeyManager.carbonHandler(nil, event, Unmanaged.passUnretained(manager).toOpaque())
        precondition(result == noErr)
    }
}
