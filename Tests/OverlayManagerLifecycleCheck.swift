import AppKit

// Compile the production manager against in-memory windows and services. These
// checks do not create native windows, capture pixels, or mutate window levels.
final class QuietLensSettings {
    var autoHideDock = false
    var autoHideMenuBar = false
    var pinnedBundleIDs: [String] = []
    var highlightSameAppWindows = false
    var fadeDuration = 0.2
}

struct FocusedWindowInfo {
    let pid: pid_t
    let frame: CGRect
    let windowNumber: CGWindowID?
}

struct WindowCornerFingerprint: Equatable {
    let ownerPID: pid_t
    let logicalSize: CGSize
    let displayScale: CGFloat
}

@MainActor final class WindowCornerReader {
    static let shared = WindowCornerReader()
    func cachedRadii(for windowID: CGWindowID, fingerprint: WindowCornerFingerprint) -> WindowCornerRadii? { nil }
    func resolve(windowID: CGWindowID, fingerprint: WindowCornerFingerprint,
                 completion: @escaping (WindowCornerRadii?) -> Void) { completion(nil) }
}

enum CutoutView {
    static let standardWindowCornerRadii = WindowCornerRadii(uniform: 16)
}

@MainActor final class WindowRaiser {
    static let shared = WindowRaiser()
    func clearAll() {}
    func setRaised(_ owners: [CGWindowID: pid_t], level: Int32) {}
    func isRaised(windowID: CGWindowID, ownerPID: pid_t) -> Bool { false }
}

@MainActor final class WindowPresentationReader {
    struct Presentation { let frame: CGRect; let scale: CGFloat }
    static let shared = WindowPresentationReader()
    var current: Presentation?
    func presentation(for windowID: CGWindowID) -> Presentation? { current }
    func windowID(at point: CGPoint, excludingPID: pid_t) -> CGWindowID? { 1 }
}

@MainActor final class OverviewDetector {
    enum Phase { case inactive, active, exiting }
    static let exitBlendDuration: TimeInterval = 0.12
    static var latest: OverviewDetector?
    var exitSelectionLocation: CGPoint?
    private let onPhase: (Phase) -> Void
    init(onPhase: @escaping (Phase) -> Void) { self.onPhase = onPhase; Self.latest = self }
    func start() {}
    func stop() {}
    func noteSelectionStarted() {}
    func emit(_ phase: Phase) { onPhase(phase) }
}

@MainActor final class OverlayWindow {
    static var created: [OverlayWindow] = []
    var frame: CGRect
    var visible = false
    var cutouts: [CGRect] = []
    var events: [String] = []
    init(frame: CGRect) { self.frame = frame; Self.created.append(self) }
    func setFrame(_ frame: CGRect, display: Bool) { self.frame = frame }
    func orderOut(_ sender: Any?) { visible = false; events.append("retire") }
    func applyAppearance(settings: QuietLensSettings) {}
    func setCutouts(_ rects: [CGRect], duration: TimeInterval,
                    cornerRadii: WindowCornerRadii = CutoutView.standardWindowCornerRadii) {
        cutouts = rects
        events.append("mask")
    }
    func fadeIn(duration: TimeInterval) { visible = true; events.append("show") }
    func fadeOut(duration: TimeInterval) { visible = false; events.append("hide") }
}

@main
struct OverlayManagerLifecycleCheck {
    @MainActor static func main() {
        let firstFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        var displays = [OverlayDisplay(id: 1, frame: firstFrame, visibleFrame: firstFrame, scale: 2)]
        let manager = OverlayManager(settings: QuietLensSettings(), displays: { displays }, windowInfo: { _, _ in [] })
        manager.updateFocus(FocusedWindowInfo(pid: 101, frame: CGRect(x: 100, y: 100, width: 200, height: 150),
                                             windowNumber: 1), excluded: false, animated: false)
        manager.setEnabled(true, animated: false)
        precondition(OverlayWindow.created.count == 1)
        let first = OverlayWindow.created[0]
        precondition(first.visible)

        // New displays receive a mask before being shown. Existing windows and
        // their ongoing fade state survive changes to the display inventory.
        let secondFrame = CGRect(x: 800, y: 0, width: 800, height: 600)
        displays.append(OverlayDisplay(id: 2, frame: secondFrame, visibleFrame: secondFrame, scale: 1))
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        precondition(OverlayWindow.created.count == 2 && first.visible)
        let second = OverlayWindow.created[1]
        precondition(second.visible && second.events.suffix(2) == ["mask", "show"])
        displays.removeLast()
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        precondition(!second.visible && first.visible && OverlayWindow.created.count == 2)

        guard let overview = OverviewDetector.latest else { preconditionFailure("Expected overview detector") }
        overview.emit(.active)
        precondition(!first.visible)
        overview.emit(.exiting)
        precondition(manager.isVisible && !first.visible && first.cutouts.isEmpty)
        manager.peek(true)
        manager.peek(false)
        precondition(!first.visible, "A logical show cannot bypass a missing presentation")

        WindowPresentationReader.shared.current = .init(frame: CGRect(x: 100, y: 100, width: 200, height: 150), scale: 1)
        manager.refreshFocusLayout()
        precondition(first.visible && !first.cutouts.isEmpty)
        precondition(first.events.suffix(2) == ["mask", "show"])
        manager.peek(true)
        manager.refreshFocusLayout()
        precondition(!first.visible, "A valid sample must respect the logical hide state")
        manager.peek(false)
        precondition(first.visible && !first.cutouts.isEmpty)
        WindowPresentationReader.shared.current = nil
        manager.refreshFocusLayout()
        precondition(!first.visible && first.cutouts.isEmpty)
        overview.emit(.inactive)
        precondition(first.visible, "Normal visibility must recover after an unavailable exit sample")

        // If the exit began while excluded, becoming eligible must start the
        // tracking path without flashing a full overlay first.
        manager.setExcluded(true, animated: false)
        overview.emit(.active)
        overview.emit(.exiting)
        manager.setExcluded(false, animated: false)
        precondition(!first.visible)
        WindowPresentationReader.shared.current = .init(frame: CGRect(x: 100, y: 100, width: 200, height: 150), scale: 1)
        manager.refreshFocusLayout()
        precondition(first.visible && !first.cutouts.isEmpty)
        manager.setEnabled(false, animated: false)
        manager.refreshFocusLayout()
        precondition(!first.visible)

        // A newly connected display remains hidden while the overview is active.
        manager.setEnabled(true, animated: false)
        overview.emit(.active)
        displays.append(OverlayDisplay(id: 2, frame: secondFrame, visibleFrame: secondFrame, scale: 1))
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        precondition(OverlayWindow.created.count == 3 && !OverlayWindow.created[2].visible)
        overview.emit(.inactive)
        precondition(OverlayWindow.created[2].visible)
        manager.setEnabled(false, animated: false)
        print("Display reconciliation, overview presentation loss/recovery, and logical visibility gates: passed")
    }
}
