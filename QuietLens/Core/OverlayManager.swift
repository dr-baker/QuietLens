import AppKit
import Combine

@MainActor
final class OverlayManager {
    private(set) var isEnabled: Bool = false
    private(set) var isVisible: Bool = false
    private var isExcluded: Bool = false
    private var isPeeking: Bool = false
    private var isDragging: Bool = false
    private var overviewPhase: OverviewDetector.Phase = .inactive
    private var overviewExitTimer: Timer?
    private var overviewExitWindowID: CGWindowID?
    private var overviewExitCornerFingerprint: WindowCornerFingerprint?
    private var overviewExitCornerRadii: WindowCornerRadii?
    private var focusedCornerFingerprint: WindowCornerFingerprint?
    private var focusedCornerRadii: WindowCornerRadii?
    private var mouseButtonDown = false
    private var dragEndFailsafe: DispatchWorkItem?
    private var dragMonitors: [Any] = []

    /// Fired whenever isEnabled flips, regardless of who flipped it (menu,
    /// hotkey, shake, URL automation, auto-disable). Lets AppDelegate keep
    /// the status icon, auto-hide state and tracker polling in sync from a
    /// single place.
    var onEnabledChanged: ((Bool) -> Void)?

    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private let settings: QuietLensSettings
    private let displays: () -> [OverlayDisplay]
    private let windowInfo: (CGWindowListOption, CGWindowID) -> [[String: Any]]?
    private var focused: FocusedWindowInfo?
    private lazy var overviewDetector = OverviewDetector { [weak self] phase in
        self?.setOverviewPhase(phase)
    }

    init(settings: QuietLensSettings,
         displays: @escaping () -> [OverlayDisplay] = { NSScreen.screens.map(OverlayDisplay.init(screen:)) },
         windowInfo: @escaping (CGWindowListOption, CGWindowID) -> [[String: Any]]? = {
             CGWindowListCopyWindowInfo($0, $1) as? [[String: Any]]
         }) {
        self.settings = settings
        self.displays = displays
        self.windowInfo = windowInfo
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        observeDrag()
    }

    deinit {
        for monitor in dragMonitors { NSEvent.removeMonitor(monitor) }
        dragEndFailsafe?.cancel()
        overviewExitTimer?.invalidate()
    }

    func setEnabled(_ on: Bool, animated: Bool) {
        let changed = isEnabled != on
        isEnabled = on
        if on {
            isDragging = false
            isPeeking = false
            overviewDetector.start()
        } else {
            overviewDetector.stop()
            overviewPhase = .inactive
            stopOverviewExitTracking()
        }
        updateVisibility(animated: animated)
        if changed { onEnabledChanged?(on) }
    }

    func setExcluded(_ ex: Bool, animated: Bool) {
        guard isExcluded != ex else { return }
        isExcluded = ex
        updateVisibility(animated: animated)
    }

    func peek(_ on: Bool) {
        isPeeking = on
        updateVisibility(animated: true)
    }

    func updateFocus(_ info: FocusedWindowInfo?, excluded: Bool, animated: Bool) {
        if info != nil {
            overviewDetector.noteSelectionStarted()
        }
        focused = info
        isExcluded = excluded
        if overviewPhase == .exiting, let windowID = info?.windowNumber {
            setOverviewExitWindow(windowID)
            refreshOverviewExitCutout()
        }

        let visible = shouldBeVisible()
        if visible != isVisible {
            updateVisibility(animated: animated)
        } else if visible {
            // A stale cutout exposes the previously focused window. Switch the
            // mask immediately and reserve fadeDuration for show/hide changes.
            refreshCutouts(animated: false)
        }
    }

    func refreshAppearance() {
        for (_, w) in windows { w.applyAppearance(settings: settings) }
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        refreshAppearance()
    }

    func refreshGeometry() {
        let screens = displays()
        for (id, w) in windows {
            guard let screen = screens.first(where: { $0.id == id }) else { continue }
            w.setFrame(overlayFrame(for: screen), display: true)
        }
        refreshCutouts(animated: false)
    }

    func refreshFocusLayout() {
        refreshCutouts(animated: false)
    }

    private func setOverviewPhase(_ phase: OverviewDetector.Phase) {
        guard overviewPhase != phase else { return }
        overviewPhase = phase

        switch phase {
        case .active:
            stopOverviewExitTracking()
            updateVisibility(animated: false)
        case .exiting:
            showOverviewExitEffect()
        case .inactive:
            stopOverviewExitTracking()
            updateVisibility(animated: false)
        }
    }

    @objc private func screensChanged() {
        // Preserve unaffected windows and their fade state. New windows start
        // transparent, and receive their masks before joining a visible effect.
        let addedIDs = reconcileWindows()
        if overviewPhase == .exiting { setOverviewExitWindow(overviewExitWindowID) }
        refreshCutouts(animated: false)
        if isVisible, overviewPhase != .exiting {
            for id in addedIDs { windows[id]?.fadeIn(duration: 0) }
        }
    }

    private func observeDrag() {
        // Only track the button state here. The overlay hides during real
        // window drags — AX move/resize while the button is down, reported
        // via noteWindowGeometryChanging() — not on every left-drag.
        // Hiding on any drag made the overlay flicker during plain text
        // selection in the focused window.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.mouseButtonDown = true }
        }) { dragMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] _ in
            Task { @MainActor in self?.endDrag() }
        }) { dragMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] ev in
            Task { @MainActor in self?.mouseButtonDown = true }
            return ev
        }) { dragMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] ev in
            Task { @MainActor in self?.endDrag() }
            return ev
        }) { dragMonitors.append(monitor) }
    }

    /// Called by WindowTracker on kAXWindowMoved / kAXWindowResized.
    func noteWindowGeometryChanging() {
        guard mouseButtonDown else { return }
        setDragging(true)
        // Failsafe: if the matching mouseUp never arrives (secure input,
        // missed event), un-hide once geometry events stop for a second.
        dragEndFailsafe?.cancel()
        let w = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.setDragging(false) }
        }
        dragEndFailsafe = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
    }

    private func endDrag() {
        mouseButtonDown = false
        dragEndFailsafe?.cancel()
        dragEndFailsafe = nil
        setDragging(false)
    }

    private func setDragging(_ d: Bool) {
        guard isDragging != d else { return }
        isDragging = d
        updateVisibility(animated: true)
    }

    private func shouldBeVisible() -> Bool {
        guard isEnabled else { return false }
        if isExcluded { return false }
        if isPeeking { return false }
        if isDragging { return false }
        if overviewPhase == .active { return false }
        return true
    }

    private func showOverviewExitEffect() {
        guard shouldBeVisible() else {
            updateVisibility(animated: false)
            return
        }

        isVisible = true
        ensureWindows()
        WindowRaiser.shared.clearAll()
        if let selectionLocation = overviewDetector.exitSelectionLocation {
            setOverviewExitWindow(WindowPresentationReader.shared.windowID(
                at: selectionLocation,
                excludingPID: ProcessInfo.processInfo.processIdentifier
            ))
        } else {
            setOverviewExitWindow(focused?.windowNumber)
        }
        refreshOverviewExitCutout()
        startOverviewExitTracking()
    }

    private func startOverviewExitTracking() {
        overviewExitTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshOverviewExitCutout() }
        }
        timer.tolerance = 0.001
        RunLoop.main.add(timer, forMode: .common)
        overviewExitTimer = timer
    }

    private func stopOverviewExitTracking() {
        overviewExitTimer?.invalidate()
        overviewExitTimer = nil
        overviewExitWindowID = nil
        overviewExitCornerFingerprint = nil
        overviewExitCornerRadii = nil
    }

    private func refreshOverviewExitCutout() {
        guard overviewPhase == .exiting else { return }
        guard shouldBeVisible(), let windowID = overviewExitWindowID,
              let presentation = WindowPresentationReader.shared.presentation(for: windowID) else {
            // A missing presentation must not leave a hole at the last sample.
            // Resume only after a valid frame, with its cutout installed first.
            for window in windows.values {
                window.setCutouts([], duration: 0)
                window.fadeOut(duration: 0)
            }
            return
        }

        let cocoaFrame = cgToCocoa(presentation.frame)
        let cornerRadii = (overviewExitCornerRadii ?? CutoutView.standardWindowCornerRadii)
            .scaled(by: presentation.scale)
        for (_, window) in windows {
            let cutouts = CutoutGeometry.localRect(for: cocoaFrame, overlay: window.frame).map { [$0] } ?? []
            window.setCutouts(cutouts, duration: 0, cornerRadii: cornerRadii)
            window.fadeIn(duration: OverviewDetector.exitBlendDuration)
        }
    }

    private func resolveFocusedCornerRadii(_ info: FocusedWindowInfo?) {
        guard let info, let windowID = info.windowNumber else {
            focusedCornerFingerprint = nil
            focusedCornerRadii = nil
            return
        }
        let fingerprint = cornerFingerprint(ownerPID: info.pid, frame: info.frame)
        focusedCornerFingerprint = fingerprint
        focusedCornerRadii = WindowCornerReader.shared.cachedRadii(for: windowID, fingerprint: fingerprint)
        guard focusedCornerRadii == nil else { return }

        WindowCornerReader.shared.resolve(windowID: windowID, fingerprint: fingerprint) { [weak self] radii in
            guard let self, let radii, self.focused?.windowNumber == windowID,
                  self.focusedCornerFingerprint == fingerprint else { return }
            self.focusedCornerRadii = radii
            if self.overviewPhase == .exiting, self.overviewExitWindowID == windowID {
                self.overviewExitCornerRadii = radii
                self.refreshOverviewExitCutout()
            } else {
                self.refreshCutouts(animated: false)
            }
        }
    }

    private func setOverviewExitWindow(_ windowID: CGWindowID?) {
        let fingerprint = windowID.flatMap { cornerFingerprint(for: $0) }
        guard overviewExitWindowID != windowID || overviewExitCornerFingerprint != fingerprint else { return }
        overviewExitWindowID = windowID
        overviewExitCornerFingerprint = fingerprint
        guard let windowID, let fingerprint else {
            overviewExitCornerRadii = nil
            return
        }
        overviewExitCornerRadii = WindowCornerReader.shared.cachedRadii(for: windowID, fingerprint: fingerprint)
        guard overviewExitCornerRadii == nil else { return }

        WindowCornerReader.shared.resolve(windowID: windowID, fingerprint: fingerprint) { [weak self] radii in
            guard let self, let radii,
                  self.overviewPhase == .exiting,
                  self.overviewExitWindowID == windowID,
                  self.overviewExitCornerFingerprint == fingerprint else { return }
            self.overviewExitCornerRadii = radii
            self.refreshOverviewExitCutout()
        }
    }

    private func cornerFingerprint(for windowID: CGWindowID) -> WindowCornerFingerprint? {
        if let focused, focused.windowNumber == windowID {
            return cornerFingerprint(ownerPID: focused.pid, frame: focused.frame)
        }
        guard let list = windowInfo(.optionIncludingWindow, windowID),
              let window = list.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }),
              let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return cornerFingerprint(ownerPID: ownerPID, frame: frame)
    }

    private func cornerFingerprint(ownerPID: pid_t, frame: CGRect) -> WindowCornerFingerprint {
        let cocoaFrame = cgToCocoa(frame)
        let screen = displays().max {
            let first = $0.frame.intersection(cocoaFrame)
            let second = $1.frame.intersection(cocoaFrame)
            return first.width * first.height < second.width * second.height
        }
        return WindowCornerFingerprint(
            ownerPID: ownerPID, logicalSize: frame.size, displayScale: screen?.scale ?? 1
        )
    }

    private func updateVisibility(animated: Bool) {
        let visible = shouldBeVisible()
        isVisible = visible
        if visible {
            if overviewPhase == .exiting {
                if overviewExitTimer == nil {
                    showOverviewExitEffect()
                } else {
                    ensureWindows()
                    refreshOverviewExitCutout()
                }
                return
            }
            ensureWindows()
            // Apply cutouts BEFORE fading in. Otherwise the user sees a
            // full-screen blur for one frame, then the focused-window
            // cutout appears — visible as a brief jitter.
            refreshCutouts(animated: false)
            for (_, w) in windows {
                w.fadeIn(duration: animated ? settings.fadeDuration : 0)
            }
        } else {
            for (_, w) in windows {
                w.fadeOut(duration: animated ? settings.fadeDuration : 0)
            }
            WindowRaiser.shared.clearAll()
        }
    }

    private func ensureWindows() {
        if windows.isEmpty { _ = reconcileWindows() }
    }

    private func reconcileWindows() -> Set<CGDirectDisplayID> {
        let screens = displays()
        let retiredIDs = Set(windows.keys).subtracting(screens.map(\.id))
        for id in retiredIDs {
            windows.removeValue(forKey: id)?.orderOut(nil)
        }
        var addedIDs = Set<CGDirectDisplayID>()
        for screen in screens {
            let id = screen.id
            let frame = overlayFrame(for: screen)
            if let window = windows[id] {
                if window.frame != frame { window.setFrame(frame, display: true) }
            } else {
                let window = OverlayWindow(frame: frame)
                window.applyAppearance(settings: settings)
                windows[id] = window
                addedIDs.insert(id)
            }
        }
        return addedIDs
    }

    private func overlayFrame(for screen: OverlayDisplay) -> NSRect {
        let full = screen.frame
        let vis = screen.visibleFrame
        var rect = full
        if !settings.autoHideMenuBar {
            let menuBarHeight = full.maxY - vis.maxY
            if menuBarHeight > 0 {
                rect.size.height -= menuBarHeight
            }
        }
        if !settings.autoHideDock {
            let dockBottom = vis.minY - full.minY
            let dockLeft = vis.minX - full.minX
            let dockRight = full.maxX - vis.maxX
            if dockBottom > 0 {
                rect.origin.y += dockBottom
                rect.size.height -= dockBottom
            }
            if dockLeft > 0 {
                rect.origin.x += dockLeft
                rect.size.width -= dockLeft
            }
            if dockRight > 0 {
                rect.size.width -= dockRight
            }
        }
        return rect
    }

    private func refreshCutouts(animated: Bool) {
        guard isVisible else {
            WindowRaiser.shared.clearAll()
            return
        }
        if overviewPhase == .exiting {
            WindowRaiser.shared.clearAll()
            refreshOverviewExitCutout()
            return
        }
        resolveFocusedCornerRadii(focused)
        let perScreen = computePerScreenWindows()
        let displayIDs = Set(displays().map(\.id))
        let ourPID = ProcessInfo.processInfo.processIdentifier
        var owners: [CGWindowID: pid_t] = [:]
        for (id, w) in windows {
            guard displayIDs.contains(id) else { continue }
            let overlayRect = w.frame
            let entries = perScreen[id] ?? []
            let cutouts = entries.compactMap { entry -> CGRect? in
                CutoutGeometry.localRect(for: entry.rect, overlay: overlayRect)
            }
            // Carry ownership from the selection scan. Our settings and
            // onboarding windows must never be raised above the overlay.
            for entry in entries where entry.windowID != 0 && entry.pid != ourPID {
                owners[entry.windowID] = entry.pid
            }
            w.setCutouts(
                cutouts,
                duration: animated ? settings.fadeDuration : 0,
                cornerRadii: focusedCornerRadii ?? CutoutView.standardWindowCornerRadii
            )
        }
        let raiseLevel = Int32(CGWindowLevelForKey(.screenSaverWindow))
        WindowRaiser.shared.setRaised(owners, level: raiseLevel)
    }

    private func computePerScreenWindows() -> [CGDirectDisplayID: [FocusWindowCandidate]] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let arr = windowInfo(opts, kCGNullWindowID) else { return [:] }

        var entries: [FocusWindowCandidate] = []
        for d in arr {
            guard let pid = d[kCGWindowOwnerPID as String] as? pid_t else { continue }
            let wid = (d[kCGWindowNumber as String] as? CGWindowID) ?? 0
            let layer = (d[kCGWindowLayer as String] as? Int) ?? 0
            guard FocusWindowSelection.includesWindow(
                layer: layer, isRaised: WindowRaiser.shared.isRaised(windowID: wid, ownerPID: pid)
            ) else { continue }
            let onScreen = (d[kCGWindowIsOnscreen as String] as? Bool) ?? true
            if !onScreen { continue }
            guard let b = d[kCGWindowBounds as String] as? [String: Any],
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { continue }
            let alpha = (d[kCGWindowAlpha as String] as? Double) ?? 1.0
            if alpha < 0.05 { continue }
            if r.width < 40 || r.height < 30 { continue }
            entries.append(FocusWindowCandidate(windowID: wid, pid: pid, rect: cgToCocoa(r)))
        }

        let ourPID = ProcessInfo.processInfo.processIdentifier
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        let pinnedIDs = Set(settings.pinnedBundleIDs)
        let pinnedPIDs: Set<pid_t> = {
            guard !pinnedIDs.isEmpty else { return [] }
            return Set(NSWorkspace.shared.runningApplications.compactMap { app in
                guard let bid = app.bundleIdentifier, pinnedIDs.contains(bid) else { return nil }
                return app.processIdentifier
            })
        }()
        let focus = focused.map {
            FocusWindowCandidate(windowID: $0.windowNumber ?? 0, pid: $0.pid, rect: cgToCocoa($0.frame))
        }
        return Dictionary(uniqueKeysWithValues: displays().map { screen in
            (screen.id, FocusWindowSelection.select(
                entries: entries, screen: screen.frame, focused: focus, frontPID: frontPID,
                pinnedPIDs: pinnedPIDs, highlightSameAppWindows: settings.highlightSameAppWindows,
                ourPID: ourPID
            ))
        })
    }

    private func cgToCocoa(_ r: CGRect) -> CGRect {
        guard let primary = displays().first else { return r }
        let topY = primary.frame.maxY
        return CGRect(x: r.origin.x, y: topY - r.origin.y - r.size.height, width: r.size.width, height: r.size.height)
    }
}
