import AppKit
import QuartzCore

final class OverlayWindow: NSWindow {
    private let blurView: BlurOverlayView
    private let cutoutView: CutoutView

    init(screen: NSScreen, frame: NSRect) {
        blurView = BlurOverlayView(frame: NSRect(origin: .zero, size: frame.size))
        cutoutView = CutoutView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        alphaValue = 0

        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        root.autoresizingMask = [.width, .height]
        blurView.autoresizingMask = [.width, .height]
        cutoutView.autoresizingMask = [.width, .height]
        root.addSubview(blurView)
        root.addSubview(cutoutView)
        contentView = root
        cutoutView.maskTarget = blurView
        orderFrontRegardless()
    }

    func applyAppearance(settings: QuietLensSettings) {
        blurView.apply(settings: settings)
        cutoutView.applyGlow(enabled: settings.edgeGlowEnabled,
                             color: settings.effectiveTintColor,
                             radius: CGFloat(settings.edgeGlowRadius))
    }

    func setCutouts(
        _ rects: [CGRect],
        duration: TimeInterval,
        cornerRadius: CGFloat = CutoutView.standardWindowCornerRadius
    ) {
        cutoutView.setCutouts(rects, duration: duration, cornerRadius: cornerRadius)
    }

    func fadeIn(duration: TimeInterval) {
        orderFrontRegardless()
        // Always nuke any lingering fadeOut animation. fadeOut uses
        // fillMode=.forwards + isRemovedOnCompletion=false so it can keep
        // the layer at opacity 0 across the orderOut. If we don't remove
        // it here, fadeIn's 0→1 animation runs, finishes, gets removed,
        // and the stuck fadeOut snaps the layer back to opacity 0 —
        // overlay flashes on then disappears.
        let layer = contentView?.layer
        layer?.removeAnimation(forKey: "fadeOut")
        layer?.opacity = 1
        // Idempotent: skip if already fully shown and no fadeIn animation
        // is mid-flight.
        if alphaValue >= 0.999 && layer?.animation(forKey: "fadeIn") == nil {
            return
        }
        if duration <= 0 {
            alphaValue = 1
            return
        }
        // Set the final alpha immediately so the window is fully visible as
        // soon as it joins the scene, then animate the fade via a
        // layer-level CABasicAnimation. NSAnimationContext + window.animator
        // only fires reliably for key/main windows; on an LSUIElement
        // (.accessory) app whose window isn't key, the alpha animation
        // doesn't tick until the window server gets some other event
        // (e.g. clicking another app), which is why the overlay appeared
        // invisible after a shake until the user clicked elsewhere.
        alphaValue = 1
        guard let layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "fadeIn")
    }

    func fadeOut(duration: TimeInterval) {
        if duration <= 0 {
            contentView?.layer?.removeAnimation(forKey: "fadeIn")
            contentView?.layer?.opacity = 0
            alphaValue = 0
            orderOut(nil)
            return
        }
        guard let layer = contentView?.layer else {
            alphaValue = 0
            orderOut(nil)
            return
        }
        layer.removeAnimation(forKey: "fadeIn")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        // Hold opacity at 0 between when the animation finishes and when our
        // completion block runs, so the layer doesn't snap back to its
        // model value (1) for one frame. fadeIn explicitly removes this
        // animation and restores opacity=1 before doing its own fade, so
        // the ghost-animation overriding fadeIn bug can't happen.
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            self.contentView?.layer?.opacity = 0
            self.contentView?.layer?.removeAnimation(forKey: "fadeOut")
            self.alphaValue = 0
            self.orderOut(nil)
        }
        layer.add(fade, forKey: "fadeOut")
        CATransaction.commit()
    }
}
