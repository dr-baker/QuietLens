import AppKit
import ApplicationServices

struct FocusedWindowInfo: Equatable {
    let pid: pid_t
    let bundleID: String?
    let frame: CGRect
    let windowNumber: CGWindowID?
}

@MainActor
final class WindowTracker {
    private typealias AXUIElementGetWindowFunc = @convention(c) (
        AXUIElement, UnsafeMutablePointer<UInt32>
    ) -> AXError

    private nonisolated(unsafe) static let hiServicesHandle: UnsafeMutableRawPointer? = {
        dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
            RTLD_NOW
        )
    }()

    private nonisolated static let axUIElementGetWindow: AXUIElementGetWindowFunc? = {
        guard let handle = hiServicesHandle else { return nil }
        for name in ["_AXUIElementGetWindow", "AXUIElementGetWindow"] {
            if let symbol = dlsym(handle, name) {
                return unsafeBitCast(symbol, to: AXUIElementGetWindowFunc.self)
            }
        }
        return nil
    }()

    var onFocusedWindowChanged: ((FocusedWindowInfo?) -> Void)?
    /// Fires when the focused window is being moved or resized (AX
    /// kAXWindowMoved / kAXWindowResized). Used to hide the overlay only
    /// during real window drags instead of on every mouse drag.
    var onWindowGeometryChanged: (() -> Void)?
    private(set) var currentApp: NSRunningApplication?
    private var axObserver: AXObserver?
    private var axApp: AXUIElement?
    private var observedPID: pid_t = 0
    private var pollTimer: Timer?
    private var lastInfo: FocusedWindowInfo?
    private var startedTracking = false
    private var pollingDesired = false

    func start() {
        guard !startedTracking else { return }
        startedTracking = true
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(activeAppChanged(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(activeAppChanged(_:)),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        attachToFrontmost()
        if pollingDesired { startPollTimer() }
    }

    /// The 0.5s poll is only a fallback for AX events the observer misses.
    /// It costs an AX round-trip + CGWindowList scan per tick, so it runs
    /// only while the overlay is enabled.
    func setPollingEnabled(_ on: Bool) {
        pollingDesired = on
        guard startedTracking else { return }
        if on {
            startPollTimer()
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func startPollTimer() {
        guard pollTimer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = 0.1
        pollTimer = t
    }

    @objc private func activeAppChanged(_ note: Notification) {
        Task { @MainActor in self.attachToFrontmost() }
    }

    private func attachToFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        currentApp = app
        attachAXObserver(pid: app.processIdentifier)
        refresh()
    }

    private func attachAXObserver(pid: pid_t) {
        if let obs = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        axObserver = nil
        axApp = AXUIElementCreateApplication(pid)
        if let app = axApp { AXUIElementSetMessagingTimeout(app, 0.4) }
        observedPID = pid
        var obs: AXObserver?
        let cb: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            let retainedElement = Unmanaged.passRetained(element)
            Task { @MainActor in
                let element = retainedElement.takeRetainedValue()
                let isGeometry = name == kAXWindowMovedNotification || name == kAXWindowResizedNotification
                if isGeometry { me.onWindowGeometryChanged?() }
                if !isGeometry,
                   let app = me.currentApp,
                   app.processIdentifier == me.observedPID,
                   let info = me.readWindow(element, app: app) {
                    me.publish(info)
                } else {
                    me.refresh()
                }
            }
        }
        if AXObserverCreate(pid, cb, &obs) == .success, let obs {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(obs, axApp!, kAXFocusedWindowChangedNotification as CFString, refcon)
            AXObserverAddNotification(obs, axApp!, kAXMainWindowChangedNotification as CFString, refcon)
            AXObserverAddNotification(obs, axApp!, kAXWindowMovedNotification as CFString, refcon)
            AXObserverAddNotification(obs, axApp!, kAXWindowResizedNotification as CFString, refcon)
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
            axObserver = obs
        }
    }

    func refresh() {
        publish(readFocusedWindow())
    }

    private func publish(_ info: FocusedWindowInfo?) {
        if info != lastInfo {
            lastInfo = info
            onFocusedWindowChanged?(info)
        }
    }

    private func readFocusedWindow() -> FocusedWindowInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        currentApp = app
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        // Prevent main-thread hangs if the target app's AX server is unresponsive.
        AXUIElementSetMessagingTimeout(axApp, 0.4)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let win = winRef else { return nil }
        let axWin = win as! AXUIElement
        AXUIElementSetMessagingTimeout(axWin, 0.4)

        return readWindow(axWin, app: app)
    }

    private func readWindow(_ axWin: AXUIElement, app: NSRunningApplication) -> FocusedWindowInfo? {
        let windowNumber = Self.windowID(for: axWin)
        guard let frame = Self.frame(for: axWin) else { return nil }

        return FocusedWindowInfo(
            pid: app.processIdentifier,
            bundleID: app.bundleIdentifier,
            frame: frame,
            windowNumber: windowNumber
        )
    }

    private nonisolated static func windowID(for window: AXUIElement) -> CGWindowID? {
        if let axUIElementGetWindow {
            var windowID: UInt32 = 0
            if axUIElementGetWindow(window, &windowID) == .success, windowID > 0 {
                return CGWindowID(windowID)
            }
        }

        var idRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "_AXWindowID" as CFString, &idRef) == .success,
           let number = idRef as? NSNumber {
            return CGWindowID(number.uint32Value)
        }
        return nil
    }

    private nonisolated static func frame(for window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef,
              let sizeRef else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
              size.width > 0,
              size.height > 0 else { return nil }
        return CGRect(origin: pos, size: size)
    }
}
