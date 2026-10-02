import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyManager {
    var onToggle: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onToggleExclude: (() -> Void)?
    var onTogglePin: (() -> Void)?

    private let settings: QuietLensSettings
    private let notificationCenter: NotificationCenter
    private var shortcutObserver: NSObjectProtocol?
    private var started = false
    private var generation: UInt64 = 0
    private var toggleRef: EventHotKeyRef?
    private var settingsRef: EventHotKeyRef?
    private var excludeRef: EventHotKeyRef?
    private var pinRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private static let toggleID: UInt32 = 1
    private static let settingsID: UInt32 = 2
    private static let excludeID: UInt32 = 3
    private static let pinID: UInt32 = 4

    init(settings: QuietLensSettings, notificationCenter: NotificationCenter = .default) {
        self.settings = settings
        self.notificationCenter = notificationCenter
    }

    deinit {
        if let shortcutObserver { notificationCenter.removeObserver(shortcutObserver) }
        if let toggleRef { UnregisterEventHotKey(toggleRef) }
        if let settingsRef { UnregisterEventHotKey(settingsRef) }
        if let excludeRef { UnregisterEventHotKey(excludeRef) }
        if let pinRef { UnregisterEventHotKey(pinRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    func start() {
        guard !started else { return }
        started = true
        generation &+= 1
        let generation = generation
        installHandler()
        register()
        shortcutObserver = notificationCenter.addObserver(forName: .quietLensShortcutChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.started, self.generation == generation else { return }
                self.register()
            }
        }
    }

    func stop() {
        started = false
        generation &+= 1
        if let shortcutObserver {
            notificationCenter.removeObserver(shortcutObserver)
            self.shortcutObserver = nil
        }
        unregister()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    static let carbonHandler: EventHandlerUPP = { _, evt, context in
        guard let context else { return noErr }
        let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
        var hk = EventHotKeyID()
        guard GetEventParameter(evt, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                nil, MemoryLayout<EventHotKeyID>.size, nil, &hk) == noErr else { return noErr }
        MainActor.assumeIsolated {
            manager.receiveHotkey(hk.id)
        }
        return noErr
    }

    private func installHandler() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), Self.carbonHandler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
    }

    private func receiveHotkey(_ id: UInt32) {
        guard started else { return }
        let generation = generation
        Task { @MainActor [weak self] in
            guard let self, self.started, self.generation == generation else { return }
            switch id {
            case Self.toggleID: self.onToggle?()
            case Self.settingsID: self.onOpenSettings?()
            case Self.excludeID: self.onToggleExclude?()
            case Self.pinID: self.onTogglePin?()
            default: break
            }
        }
    }

    private func unregister() {
        if let r = toggleRef { UnregisterEventHotKey(r); toggleRef = nil }
        if let r = settingsRef { UnregisterEventHotKey(r); settingsRef = nil }
        if let r = excludeRef { UnregisterEventHotKey(r); excludeRef = nil }
        if let r = pinRef { UnregisterEventHotKey(r); pinRef = nil }
    }

    private func register() {
        unregister()
        if let key = settings.toggleShortcutKey {
            toggleRef = registerKey(keyCode: key, mods: settings.toggleShortcutMods, id: Self.toggleID)
        }
        if let key = settings.settingsShortcutKey {
            settingsRef = registerKey(keyCode: key, mods: settings.settingsShortcutMods, id: Self.settingsID)
        }
        if let key = settings.excludeAppShortcutKey {
            excludeRef = registerKey(keyCode: key, mods: settings.excludeAppShortcutMods, id: Self.excludeID)
        }
        if let key = settings.pinShortcutKey {
            pinRef = registerKey(keyCode: key, mods: settings.pinShortcutMods, id: Self.pinID)
        }
    }

    private func registerKey(keyCode: UInt16, mods: UInt, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotID = EventHotKeyID(signature: OSType(0x464C4E53), id: id)
        RegisterEventHotKey(UInt32(keyCode), UInt32(mods), hotID, GetApplicationEventTarget(), 0, &ref)
        return ref
    }
}

extension Notification.Name {
    static let quietLensShortcutChanged = Notification.Name("quietLensShortcutChanged")
}
