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
    private var mouseButtonDown = false
    private var dragEndFailsafe: DispatchWorkItem?

    /// Fired whenever isEnabled flips, regardless of who flipped it (menu,
    /// hotkey, shake, URL automation, auto-disable). Lets AppDelegate keep
    /// the status icon, auto-hide state and tracker polling in sync from a
    /// single place.
    var onEnabledChanged: ((Bool) -> Void)?

    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private let settings: QuietLensSettings
    private var focused: FocusedWindowInfo?
    private lazy var overviewDetector = OverviewDetector { [weak self] phase in
        self?.setOverviewPhase(phase)
    }

    init(settings: QuietLensSettings) {
        self.settings = settings
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        observeDrag()
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
        }
        updateVisibility(animated: animated)
        if changed { onEnabledChanged?(on) }
    }

    func setExcluded(_ ex: Bool, animated: Bool) {
        isExcluded = ex
        updateVisibility(animated: animated)
    }

    func peek(_ on: Bool) {
        isPeeking = on
        updateVisibility(animated: true)
    }

    func updateFocus(_ info: FocusedWindowInfo?, animated: Bool) {
        overviewDetector.noteSelectionStarted()
        focused = info
        refreshCutouts(animated: animated)
    }

    func refreshAppearance() {
        for (_, w) in windows { w.applyAppearance(settings: settings) }
    }

    func refreshGeometry() {
        for (id, w) in windows {
            guard let screen = NSScreen.screens.first(where: { screenID($0) == id }) else { continue }
            w.setFrame(overlayFrame(for: screen), display: true)
        }
        refreshCutouts(animated: false)
    }

    private func setOverviewPhase(_ phase: OverviewDetector.Phase) {
        guard overviewPhase != phase else { return }
        overviewPhase = phase

        switch phase {
        case .active:
            updateVisibility(animated: false)
        case .exiting:
            showOverviewExitEffect()
        case .inactive:
            if shouldBeVisible(), isVisible {
                refreshCutouts(animated: false)
            } else {
                updateVisibility(animated: false)
            }
        }
    }

    @objc private func screensChanged() {
        // Avoid rebuilding the overlay windows here. didChangeScreenParameters
        // fires for tiny visibleFrame changes too (e.g. when applyAutoHide
        // toggles the menu-bar autoHide presentation option), and tearing
        // the windows down + back up mid-fade caused a visible flash on
        // every shake. Resize-in-place handles both monitor add/remove and
        // visibleFrame changes; rebuildWindows happens lazily via
        // ensureWindows() when the screen set actually differs.
        let currentIDs = Set(windows.keys)
        let newIDs = Set(NSScreen.screens.map { screenID($0) })
        if currentIDs != newIDs {
            rebuildWindows()
        } else {
            for screen in NSScreen.screens {
                if let w = windows[screenID(screen)] {
                    w.setFrame(overlayFrame(for: screen), display: true)
                }
            }
        }
        refreshCutouts(animated: false)
    }

    private func observeDrag() {
        // Only track the button state here. The overlay hides during real
        // window drags — AX move/resize while the button is down, reported
        // via noteWindowGeometryChanging() — not on every left-drag.
        // Hiding on any drag made the overlay flicker during plain text
        // selection in the focused window.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.mouseButtonDown = true }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in self?.endDrag() }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] ev in
            Task { @MainActor in self?.mouseButtonDown = true }
            return ev
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] ev in
            Task { @MainActor in self?.endDrag() }
            return ev
        }
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
        for (_, window) in windows {
            window.setCutouts([], duration: 0)
            window.fadeIn(duration: OverviewDetector.exitBlendDuration)
        }
    }

    private func updateVisibility(animated: Bool) {
        let visible = shouldBeVisible()
        isVisible = visible
        if visible {
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
        if windows.isEmpty { rebuildWindows() }
    }

    private func rebuildWindows() {
        for (_, w) in windows { w.orderOut(nil) }
        windows.removeAll()
        for screen in NSScreen.screens {
            let frame = overlayFrame(for: screen)
            let w = OverlayWindow(screen: screen, frame: frame)
            w.applyAppearance(settings: settings)
            windows[screenID(screen)] = w
        }
    }

    private func screenID(_ s: NSScreen) -> CGDirectDisplayID {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func overlayFrame(for screen: NSScreen) -> NSRect {
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
            for (_, window) in windows {
                window.setCutouts([], duration: 0)
            }
            return
        }
        let perScreen = computePerScreenWindows()
        var allIDs = Set<CGWindowID>()
        for (id, w) in windows {
            guard NSScreen.screens.first(where: { screenID($0) == id }) != nil else { continue }
            let overlayRect = w.frame
            let entries = perScreen[id] ?? []
            let cutouts = entries.compactMap { entry -> CGRect? in
                let inter = entry.rect.intersection(overlayRect)
                if inter.isNull || inter.isEmpty { return nil }
                return CGRect(x: inter.minX - overlayRect.minX,
                              y: inter.minY - overlayRect.minY,
                              width: inter.width, height: inter.height)
            }
            for e in entries where e.windowID != 0 { allIDs.insert(e.windowID) }
            w.setCutouts(cutouts, duration: animated ? settings.fadeDuration : 0)
        }
        // Never raise our own windows (Settings / Onboarding). Otherwise every
        // refresh re-raises them to screenSaver level, which on macOS flashes
        // them forward in the z-order — visible as Settings popping in and
        // out on every shake.
        let ourPID = ProcessInfo.processInfo.processIdentifier
        if !allIDs.isEmpty,
           let arr = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
            for d in arr {
                guard let pid = d[kCGWindowOwnerPID as String] as? pid_t, pid == ourPID,
                      let wid = d[kCGWindowNumber as String] as? CGWindowID else { continue }
                allIDs.remove(wid)
            }
        }
        let raiseLevel = Int32(CGWindowLevelForKey(.screenSaverWindow))
        WindowRaiser.shared.setRaised(allIDs, level: raiseLevel)
    }

    struct WindowEntry {
        let windowID: CGWindowID
        let rect: CGRect
        var pid: pid_t = 0
    }

    private func computePerScreenWindows() -> [CGDirectDisplayID: [WindowEntry]] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let arr = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [:] }

        struct CGEntry {
            let windowID: CGWindowID
            let pid: pid_t
            let rect: CGRect
        }
        var entries: [CGEntry] = []
        for d in arr {
            let layer = (d[kCGWindowLayer as String] as? Int) ?? 0
            if layer > 0 { continue }
            let onScreen = (d[kCGWindowIsOnscreen as String] as? Bool) ?? true
            if !onScreen { continue }
            guard let pid = d[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard let b = d[kCGWindowBounds as String] as? [String: Any],
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { continue }
            let alpha = (d[kCGWindowAlpha as String] as? Double) ?? 1.0
            if alpha < 0.05 { continue }
            if r.width < 40 || r.height < 30 { continue }
            let wid = (d[kCGWindowNumber as String] as? CGWindowID) ?? 0
            entries.append(CGEntry(windowID: wid, pid: pid, rect: cgToCocoa(r)))
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
        var out: [CGDirectDisplayID: [WindowEntry]] = [:]

        for screen in NSScreen.screens {
            let id = screenID(screen)
            let sf = screen.frame
            var picked: [WindowEntry] = []

            for e in entries where pinnedPIDs.contains(e.pid) && e.rect.intersects(sf) {
                picked.append(WindowEntry(windowID: e.windowID, rect: e.rect))
            }

            if settings.highlightSameAppWindows {
                for e in entries where e.pid == frontPID {
                    if e.rect.intersects(sf) && !picked.contains(where: { rectsApproxEqual($0.rect, e.rect) }) {
                        picked.append(WindowEntry(windowID: e.windowID, rect: e.rect))
                    }
                }
                if let ax = focused?.frame, focused?.pid == frontPID {
                    let cocoa = axToCocoa(ax)
                    if cocoa.intersects(sf) && !picked.contains(where: { rectsApproxEqual($0.rect, cocoa) }) {
                        let wid = focused?.windowNumber ?? 0
                        picked.append(WindowEntry(windowID: wid, rect: cocoa))
                    }
                }
                if picked.isEmpty, let top = entries.first(where: { $0.pid != ourPID && $0.rect.intersects(sf) }) {
                    picked.append(WindowEntry(windowID: top.windowID, rect: top.rect))
                }
            } else {
                if let ax = focused?.frame, focused?.pid == frontPID {
                    let cocoa = axToCocoa(ax)
                    if cocoa.intersects(sf) {
                        let wid = focused?.windowNumber ?? entries.first(where: { $0.pid == frontPID && rectsApproxEqual($0.rect, cocoa) })?.windowID ?? 0
                        picked.append(WindowEntry(windowID: wid, rect: cocoa))
                    }
                }
                if picked.isEmpty,
                   let top = entries.first(where: { $0.pid == frontPID && $0.rect.intersects(sf) }) {
                    picked.append(WindowEntry(windowID: top.windowID, rect: top.rect))
                }
                if picked.isEmpty,
                   let any = entries.first(where: { $0.pid != ourPID && $0.rect.intersects(sf) }) {
                    picked.append(WindowEntry(windowID: any.windowID, rect: any.rect))
                }
            }
            out[id] = picked
        }
        return out
    }

    private func axToCocoa(_ r: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return r }
        let topY = primary.frame.maxY
        return CGRect(x: r.origin.x, y: topY - r.origin.y - r.size.height, width: r.size.width, height: r.size.height)
    }

    private func rectsApproxEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 4 && abs(a.minY - b.minY) < 4 &&
        abs(a.width - b.width) < 4 && abs(a.height - b.height) < 4
    }

    private func cgToCocoa(_ r: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return r }
        let topY = primary.frame.maxY
        return CGRect(x: r.origin.x, y: topY - r.origin.y - r.size.height, width: r.size.width, height: r.size.height)
    }
}
