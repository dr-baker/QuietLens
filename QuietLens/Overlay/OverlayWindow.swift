import AppKit
import QuartzCore

final class OverlayWindow: NSWindow {
    private let blurView: BlurOverlayView
    private let cutoutView: CutoutView
    private var fadeState = OverlayFadeState()

    init(frame: NSRect) {
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
        cornerRadii: WindowCornerRadii = CutoutView.standardWindowCornerRadii
    ) {
        cutoutView.setCutouts(rects, duration: duration, cornerRadii: cornerRadii)
    }

    func fadeIn(duration: TimeInterval) {
        let layer = contentView?.layer
        if duration > 0, fadeState.isVisible,
           layer?.animation(forKey: "fadeIn") != nil {
            return
        }
        let wasFullyVisible = alphaValue >= 0.999 && (layer?.opacity ?? 0) >= 0.999
            && layer?.animation(forKey: "fadeIn") == nil
            && layer?.animation(forKey: "fadeOut") == nil
        if wasFullyVisible, fadeState.isVisible { return }
        let opacity = alphaValue > 0 ? (layer?.presentation()?.opacity ?? layer?.opacity ?? 0) : 0
        _ = fadeState.begin(visible: true)
        layer?.removeAnimation(forKey: "fadeOut")
        layer?.removeAnimation(forKey: "fadeIn")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = 1
        CATransaction.commit()
        alphaValue = 1
        orderFrontRegardless()
        guard duration > 0, !wasFullyVisible, let layer else { return }
        // Layer animation ticks independently of key-window events in this
        // menu bar app. Continue from the visible opacity on interruption.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity
        fade.toValue = 1
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "fadeIn")
    }

    func fadeOut(duration: TimeInterval) {
        let generation = fadeState.begin(visible: false)
        let layer = contentView?.layer
        let opacity = alphaValue > 0 ? (layer?.presentation()?.opacity ?? layer?.opacity ?? 0) : 0
        layer?.removeAnimation(forKey: "fadeIn")
        layer?.removeAnimation(forKey: "fadeOut")
        if duration <= 0 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.opacity = 0
            CATransaction.commit()
            alphaValue = 0
            orderOut(nil)
            return
        }
        guard let layer else {
            alphaValue = 0
            orderOut(nil)
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity
        fade.toValue = 0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.fadeState.canFinishHiding(generation: generation) else { return }
            self.alphaValue = 0
            self.orderOut(nil)
        }
        layer.add(fade, forKey: "fadeOut")
        CATransaction.commit()
    }
}
