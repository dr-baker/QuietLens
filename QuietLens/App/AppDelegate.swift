import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, @unchecked Sendable {
    @MainActor func applicationWillTerminate(_ notification: Notification) {
        WindowRaiser.shared.clearAll()
    }

    // Settings/Onboarding stay at .normal level. Putting them above the
    // overlay (screenSaver+1) used to keep them visible while the overlay was
    // on, but it broke macOS Screenshot which then can't capture them.
    // OverlayManager now treats our own windows as cutout targets, so they
    // stay clear without needing a higher window level.

    @MainActor
    func windowDidBecomeKey(_ notification: Notification) {}

    @MainActor
    func windowDidResignKey(_ notification: Notification) {}

    static private(set) var shared: AppDelegate!

    var statusItem: NSStatusItem!
    var overlayManager: OverlayManager!
    var windowTracker: WindowTracker!
    var shakeDetector: ShakeDetector!
    var hotkeyManager: HotkeyManager!
    var automationHandler: AutomationHandler!

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)

        let settings = QuietLensSettings.shared
        overlayManager = OverlayManager(settings: settings)
        windowTracker = WindowTracker()
        shakeDetector = ShakeDetector(settings: settings)
        hotkeyManager = HotkeyManager(settings: settings)
        automationHandler = AutomationHandler()

        setupStatusItem()
        setupMainMenu()
        setupBindings()
        setupURLHandler()
        iCloudSync.shared.start()

        windowTracker.onFocusedWindowChanged = { [weak self] info in
            self?.handleFocusChange(info)
        }
        windowTracker.onWindowGeometryChanged = { [weak self] in
            self?.overlayManager.noteWindowGeometryChanging()
        }
        overlayManager.onEnabledChanged = { [weak self] enabled in
            guard let self else { return }
            self.windowTracker.setPollingEnabled(enabled)
            if enabled {
                self.pauseTimer?.invalidate()
                self.pauseTimer = nil
                self.windowTracker.refresh()
                self.applyCurrentExclusion()
            }
            self.scheduleAutoDisable(enabled: enabled)
            self.updateStatusIcon()
            self.applyAutoHide()
        }
        shakeDetector.onShake = { [weak self] in self?.toggleOverlay() }
        shakeDetector.onPeekStart = { [weak self] in self?.overlayManager.peek(true) }
        shakeDetector.onPeekEnd = { [weak self] in self?.overlayManager.peek(false) }
        hotkeyManager.onToggle = { [weak self] in self?.toggleOverlay() }
        hotkeyManager.onOpenSettings = { [weak self] in self?.openSettings() }
        hotkeyManager.onToggleExclude = { [weak self] in self?.toggleExcludeCurrent() }
        hotkeyManager.onTogglePin = { [weak self] in self?.togglePinCurrent() }

        evaluateAccessibility(promptIfMissing: false)
        startAccessibilityPoll()
    }

    private var trackingStarted = false
    private var axPollTimer: Timer?
    private var autoDisableTimer: Timer?
    private var pauseTimer: Timer?
    private var lastAutoDisable: AutoDisableAfter = .never
    /// True after the user explicitly turned the overlay off. Suppresses
    /// auto-enable-on-focus until the user turns it back on, so the setting
    /// can't fight a deliberate "off".
    private var userDisabledOverlay = false

    private var wasShowingOnboarding = false

    @MainActor
    private func evaluateAccessibility(promptIfMissing: Bool) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfMissing] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        if trusted {
            if !trackingStarted {
                trackingStarted = true
                startTracking()
            }
            onboardingWindow?.close()
        } else if !trackingStarted {
            wasShowingOnboarding = true
            showOnboarding()
        }
    }

    @MainActor
    private func startAccessibilityPoll() {
        axPollTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                if trusted && !self.trackingStarted {
                    self.trackingStarted = true
                    self.startTracking()
                    self.onboardingWindow?.close()
                    if self.wasShowingOnboarding {
                        self.wasShowingOnboarding = false
                        self.openSettings()
                    }
                } else if !trusted && self.trackingStarted {
                    self.trackingStarted = false
                    self.wasShowingOnboarding = true
                    self.showOnboarding()
                }
            }
        }
        t.tolerance = 0.5
        axPollTimer = t
    }

    @MainActor
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Quiet Lens")
            btn.image?.isTemplate = true
            btn.target = self
            btn.action = #selector(statusBarClicked(_:))
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusIcon()
    }

    @MainActor
    private func setupBindings() {
        let s = QuietLensSettings.shared
        lastAutoDisable = s.autoDisableAfter
        s.objectWillChange
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateStatusIcon()
                self.overlayManager.refreshAppearance()
                self.applyAutoHide()
                let auto = QuietLensSettings.shared.autoDisableAfter
                if auto != self.lastAutoDisable {
                    self.lastAutoDisable = auto
                    self.scheduleAutoDisable(enabled: self.overlayManager.isEnabled)
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(s.$autoHideDock.removeDuplicates(),
                                 s.$autoHideMenuBar.removeDuplicates())
            .dropFirst()
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.overlayManager.refreshGeometry() }
            .store(in: &cancellables)

        s.$excludedBundleIDs
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.applyCurrentExclusion() }
            .store(in: &cancellables)

        Publishers.CombineLatest(s.$pinnedBundleIDs.removeDuplicates(),
                                 s.$highlightSameAppWindows.removeDuplicates())
            .dropFirst()
            .sink { [weak self] _ in self?.overlayManager.refreshFocusLayout() }
            .store(in: &cancellables)
        // iCloud push is debounced separately and much more loosely — the
        // 60ms cadence above fires on every slider tick, and each push hits
        // NSUbiquitousKeyValueStore.synchronize().
        s.objectWillChange
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { _ in iCloudSync.shared.pushCurrent() }
            .store(in: &cancellables)
    }

    /// LSUIElement apps have no visible menu bar menu, but a main menu is
    /// still required for standard key equivalents (⌘C/⌘V in the search
    /// field, ⌘W to close Settings, ⌘Q to quit) to reach the responder chain.
    @MainActor
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Quiet Lens",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = win
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    @MainActor
    private func scheduleAutoDisable(enabled: Bool) {
        autoDisableTimer?.invalidate()
        autoDisableTimer = nil
        guard enabled, let secs = QuietLensSettings.shared.autoDisableAfter.seconds else { return }
        let t = Timer.scheduledTimer(withTimeInterval: secs, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.overlayManager.isEnabled else { return }
                // Route through setOverlayEnabled so auto-enable-on-focus
                // doesn't immediately undo the auto-disable on the next
                // focus change.
                self.setOverlayEnabled(false)
            }
        }
        t.tolerance = min(30, secs * 0.05)
        autoDisableTimer = t
    }

    @MainActor
    func pauseOverlay(for seconds: TimeInterval) {
        guard overlayManager.isEnabled else { return }
        userDisabledOverlay = true
        overlayManager.setEnabled(false, animated: true)
        let t = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.setOverlayEnabled(true) }
        }
        t.tolerance = 5
        pauseTimer = t
    }

    private func setupURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let str = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: str) else { return }
        Task { @MainActor in
            automationHandler.handle(url: url)
        }
    }

    @MainActor
    @objc private func statusBarClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            switch QuietLensSettings.shared.menuBarLeftClick {
            case .toggleOverlay: toggleOverlay()
            case .openSettings: openSettings()
            }
        }
    }

    @MainActor
    private func showContextMenu() {
        let menu = NSMenu()
        let isOn = overlayManager.isEnabled
        let toggleItem = NSMenuItem(title: isOn ? "Disable Overlay" : "Enable Overlay",
                                    action: #selector(toggleFromMenu), keyEquivalent: "")
        toggleItem.image = NSImage(systemSymbolName: isOn ? "pause.circle" : "play.circle",
                                   accessibilityDescription: nil)
        toggleItem.target = self
        menu.addItem(toggleItem)

        let focusName = windowTracker.currentApp?.localizedName ?? "—"
        let focusItem = NSMenuItem(title: "Focused: \(focusName)", action: nil, keyEquivalent: "")
        focusItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        focusItem.isEnabled = false
        menu.addItem(focusItem)

        if isOn {
            let pauseItem = NSMenuItem(title: "Pause for 5 Minutes",
                                       action: #selector(pauseFiveMinutes), keyEquivalent: "")
            pauseItem.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: nil)
            pauseItem.target = self
            menu.addItem(pauseItem)
        }

        menu.addItem(.separator())

        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        modeItem.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: nil)
        let modeMenu = NSMenu()
        for mode in OverlayMode.allCases {
            let mi = NSMenuItem(title: "\(mode.label) — \(mode.summary)",
                                action: #selector(selectMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = mode.rawValue
            mi.state = (QuietLensSettings.shared.overlayMode == mode) ? .on : .off
            modeMenu.addItem(mi)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let excluded = isCurrentExcluded()
        let exItem = NSMenuItem(title: excluded ? "Include Current App" : "Exclude Current App",
                                action: #selector(toggleExcludeCurrent), keyEquivalent: "")
        exItem.image = NSImage(systemSymbolName: excluded ? "plus.circle" : "minus.circle",
                               accessibilityDescription: nil)
        exItem.target = self
        menu.addItem(exItem)

        if let id = windowTracker.currentApp?.bundleIdentifier {
            let pinned = QuietLensSettings.shared.pinnedBundleIDs.contains(id)
            let pinItem = NSMenuItem(title: pinned ? "Unpin Current App" : "Pin Current App",
                                     action: #selector(togglePinFromMenu), keyEquivalent: "")
            pinItem.image = NSImage(systemSymbolName: pinned ? "pin.slash" : "pin",
                                    accessibilityDescription: nil)
            pinItem.target = self
            menu.addItem(pinItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Quiet Lens",
                                  action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        // Pop the menu up directly under the status item. Don't assign
        // `statusItem.menu` + `performClick`: that re-enters statusBarClicked
        // while currentEvent is still .rightMouseUp, which calls back into
        // showContextMenu, which calls performClick again — infinite recursion.
        if let btn = statusItem.button {
            let p = NSPoint(x: 0, y: btn.bounds.maxY + 4)
            menu.popUp(positioning: nil, at: p, in: btn)
        }
    }

    @MainActor @objc private func toggleFromMenu() { toggleOverlay() }
    @MainActor @objc private func openSettingsFromMenu() { openSettings() }
    @MainActor @objc private func pauseFiveMinutes() { pauseOverlay(for: 300) }
    @MainActor @objc private func togglePinFromMenu() { togglePinCurrent() }
    @MainActor @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = OverlayMode(rawValue: raw) else { return }
        QuietLensSettings.shared.overlayMode = mode
    }
    @MainActor func togglePinCurrent() {
        guard let id = windowTracker.currentApp?.bundleIdentifier else { return }
        var list = QuietLensSettings.shared.pinnedBundleIDs
        if let idx = list.firstIndex(of: id) { list.remove(at: idx) } else { list.append(id) }
        QuietLensSettings.shared.pinnedBundleIDs = list
    }

    @MainActor @objc func toggleExcludeCurrent() {
        guard let id = windowTracker.currentApp?.bundleIdentifier else { return }
        var list = QuietLensSettings.shared.excludedBundleIDs
        if let idx = list.firstIndex(of: id) { list.remove(at: idx) } else { list.append(id) }
        QuietLensSettings.shared.excludedBundleIDs = list
        applyCurrentExclusion()
    }

    @MainActor
    private func isCurrentExcluded() -> Bool {
        guard let id = windowTracker.currentApp?.bundleIdentifier else { return false }
        return QuietLensSettings.shared.excludedBundleIDs.contains(id)
    }

    @MainActor
    func toggleOverlay() {
        setOverlayEnabled(!overlayManager.isEnabled)
    }

    /// Single entry point for user-intent enable/disable (menu, hotkey,
    /// shake, URL automation). Tracks the manual-off flag that gates
    /// auto-enable-on-focus; onEnabledChanged handles icon, polling,
    /// auto-hide, and re-reading the frontmost window.
    @MainActor
    func setOverlayEnabled(_ on: Bool) {
        userDisabledOverlay = !on
        overlayManager.setEnabled(on, animated: true)
    }

    @MainActor
    func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView().environmentObject(QuietLensSettings.shared)
            let host = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: host)
            w.title = "Quiet Lens Settings"
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView, .resizable]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = false
            w.setContentSize(NSSize(width: 920, height: 640))
            // Do NOT override the close button's target/action. The default
            // already routes through the responder chain and closes the
            // window. Setting target = w + action = performClose: causes
            // infinite recursion: performClose simulates a click on the
            // close button, which re-invokes performClose, which simulates
            // another click… stack overflows in __CFStringAppendBytes when
            // AppKit tries to log the runaway.
            w.level = .normal
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.delegate = self
            w.center()
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    func showOnboarding() {
        if onboardingWindow == nil {
            let v = OnboardingView(onDone: { [weak self] in
                guard let self else { return }
                self.onboardingWindow?.close()
                if !self.trackingStarted {
                    self.trackingStarted = true
                    self.startTracking()
                }
                if self.wasShowingOnboarding {
                    self.wasShowingOnboarding = false
                    self.openSettings()
                }
            })
            let host = NSHostingController(rootView: v)
            let w = NSWindow(contentViewController: host)
            w.title = ""
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = false
            w.setContentSize(NSSize(width: 620, height: 760))
            w.center()
            w.isReleasedWhenClosed = false
            w.level = .normal
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.delegate = self
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private func startTracking() {
        windowTracker.start()
        shakeDetector.start()
        hotkeyManager.start()
    }

    @MainActor
    private func handleFocusChange(_ info: FocusedWindowInfo?) {
        if QuietLensSettings.shared.autoEnableOnFocus,
           !overlayManager.isEnabled, !userDisabledOverlay, info != nil {
            overlayManager.setEnabled(true, animated: true)
        }
        applyCurrentExclusion()
        overlayManager.updateFocus(info, animated: true)
        updateStatusIcon()
    }

    @MainActor
    private func applyCurrentExclusion() {
        let excluded = isCurrentExcluded()
        overlayManager.setExcluded(excluded, animated: true)
        applyAutoHide()
    }

    @MainActor
    private func applyAutoHide() {
        let s = QuietLensSettings.shared
        let active = overlayManager.isEnabled && overlayManager.isVisible
        var opts: NSApplication.PresentationOptions = []
        if active && s.autoHideMenuBar {
            // AppKit requires autoHideDock whenever autoHideMenuBar is set;
            // setting the menu-bar option alone throws
            // NSInvalidArgumentException and kills the app.
            opts.insert(.autoHideMenuBar)
            opts.insert(.autoHideDock)
        }
        NSApp.presentationOptions = opts
    }

    @MainActor
    private enum MenuIconState {
        case off, ambient, deep, excluded
    }

    @MainActor
    private func updateStatusIcon() {
        guard let btn = statusItem?.button else { return }
        let isOn = overlayManager?.isEnabled ?? false
        let excluded = isCurrentExcluded()
        let mode = QuietLensSettings.shared.overlayMode
        let dotEnabled = QuietLensSettings.shared.showIndicatorDot

        let state: MenuIconState
        if excluded { state = .excluded }
        else if isOn && !dotEnabled { state = .off }
        else if isOn && mode == .ambient { state = .ambient }
        else if isOn { state = .deep }
        else { state = .off }

        let image = Self.menuBarImage(state: state)
        btn.image = image
        btn.image?.isTemplate = (state != .ambient)

        let stateText: String
        switch state {
        case .excluded: stateText = "overlay off for this app"
        case .off: stateText = isOn ? "overlay on" : "overlay off"
        case .ambient, .deep: stateText = "overlay on"
        }
        btn.toolTip = "Quiet Lens — \(stateText)"
        btn.setAccessibilityLabel("Quiet Lens, \(stateText)")
    }

    private static func menuBarImage(state: MenuIconState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let circleRect = CGRect(x: 1.5, y: 1.5, width: 15, height: 15)
            let center = CGPoint(x: 9, y: 9)
            switch state {
            case .off:
                ctx.setStrokeColor(NSColor.black.cgColor)
                ctx.setLineWidth(1.4)
                ctx.strokeEllipse(in: circleRect)
            case .deep:
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fillEllipse(in: circleRect)
                ctx.setBlendMode(.destinationOut)
                ctx.setFillColor(NSColor.black.cgColor)
                let innerR: CGFloat = 2.4
                ctx.fillEllipse(in: CGRect(x: center.x - innerR, y: center.y - innerR,
                                           width: innerR*2, height: innerR*2))
            case .ambient:
                let cs = CGColorSpaceCreateDeviceRGB()
                ctx.saveGState()
                ctx.addEllipse(in: circleRect); ctx.clip()
                let grad = CGGradient(colorsSpace: cs, colors: [
                    CGColor(srgbRed: 0.55, green: 0.30, blue: 1.0, alpha: 1),
                    CGColor(srgbRed: 0.10, green: 0.50, blue: 1.0, alpha: 1),
                    CGColor(srgbRed: 0.20, green: 0.85, blue: 1.0, alpha: 1)
                ] as CFArray, locations: [0, 0.5, 1])!
                ctx.drawLinearGradient(grad,
                    start: CGPoint(x: circleRect.minX, y: circleRect.maxY),
                    end: CGPoint(x: circleRect.maxX, y: circleRect.minY),
                    options: [])
                ctx.restoreGState()
            case .excluded:
                ctx.setStrokeColor(NSColor.black.cgColor)
                ctx.setLineWidth(1.4)
                ctx.setLineDash(phase: 0, lengths: [2.2, 1.6])
                ctx.strokeEllipse(in: circleRect)
            }
            return true
        }
        return img
    }
}
