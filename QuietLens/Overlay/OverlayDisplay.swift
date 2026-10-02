import AppKit

struct OverlayDisplay {
    let id: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect
    let scale: CGFloat

    init(id: CGDirectDisplayID, frame: CGRect, visibleFrame: CGRect, scale: CGFloat) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scale = scale
    }

    init(screen: NSScreen) {
        id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        frame = screen.frame
        visibleFrame = screen.visibleFrame
        scale = screen.backingScaleFactor
    }
}
