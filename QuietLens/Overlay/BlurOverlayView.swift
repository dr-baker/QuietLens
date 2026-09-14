import AppKit
import CoreImage
import QuartzCore

final class BlurOverlayView: NSView {
    private let effect: NSVisualEffectView
    private let effectsView: NSView
    private let tintLayer = CALayer()
    private let gradientLayer = CAGradientLayer()
    private let grainLayer = CALayer()
    private let backdropLayer = CALayer()
    private var lastBackdropKey: String = ""

    override init(frame frameRect: NSRect) {
        effect = NSVisualEffectView(frame: frameRect)
        effectsView = NSView(frame: frameRect)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        effect.blendingMode = .behindWindow
        effect.material = .windowBackground
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        addSubview(effect)

        // Keep every color treatment in a sibling view above the material.
        // NSVisualEffectView manages its own backing layers and can otherwise
        // reorder root-layer siblings when its material changes.
        effectsView.wantsLayer = true
        effectsView.autoresizingMask = [.width, .height]
        effectsView.layer?.masksToBounds = true
        addSubview(effectsView, positioned: .above, relativeTo: effect)

        backdropLayer.frame = bounds
        backdropLayer.contentsGravity = .resizeAspectFill
        backdropLayer.isHidden = true
        tintLayer.frame = bounds
        gradientLayer.frame = bounds
        grainLayer.frame = bounds
        grainLayer.contentsGravity = .resizeAspectFill
        effectsView.layer?.addSublayer(backdropLayer)
        effectsView.layer?.addSublayer(tintLayer)
        effectsView.layer?.addSublayer(gradientLayer)
        effectsView.layer?.addSublayer(grainLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effect.frame = bounds
        effectsView.frame = bounds
        backdropLayer.frame = bounds
        tintLayer.frame = bounds
        gradientLayer.frame = bounds
        grainLayer.frame = bounds
        CATransaction.commit()
    }

    func apply(settings: QuietLensSettings) {
        let radius = max(0, min(50, settings.blurRadius))
        let isAmbient = settings.overlayMode == .ambient
        let isTinted = settings.overlayMode == .tinted

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let useBackdropImage = settings.backdropMode != .blur
        if useBackdropImage {
            applyBackdropImage(settings: settings)
            backdropLayer.isHidden = false
            effect.isHidden = true
        } else if radius < 0.5 {
            backdropLayer.isHidden = true
            effect.isHidden = true
        } else {
            backdropLayer.isHidden = true
            effect.isHidden = false
            // AppKit does not expose a continuous radius for visual-effect
            // materials. Combine material steps with a continuous alpha ramp
            // so every part of the strength control produces visible feedback.
            switch radius {
            case ..<10: effect.material = .hudWindow
            case ..<25: effect.material = .underWindowBackground
            case ..<40: effect.material = .fullScreenUI
            default: effect.material = .menu
            }
            let normalizedStrength = radius / 50
            let modeScale: CGFloat = isAmbient ? 0.78 : 1.0
            effect.alphaValue = (0.22 + normalizedStrength * 0.78) * modeScale
        }

        let opacity = max(0.1, min(1.0, settings.overlayOpacity)) * (isTinted ? 1.2 : 1.0)
        let tintCompositingFilter: String? = isTinted ? "multiplyBlendMode" : nil

        let useGradient = settings.gradientEnabled || isAmbient
        if useGradient {
            tintLayer.isHidden = true
            gradientLayer.isHidden = false
            if isAmbient && !settings.gradientEnabled {
                let tint = settings.effectiveTintColor
                let topAlpha: CGFloat = 0.0
                let bottomAlpha: CGFloat = opacity * 0.55
                gradientLayer.colors = [
                    tint.withAlphaComponent(topAlpha).cgColor,
                    tint.withAlphaComponent(bottomAlpha).cgColor
                ]
                gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
                gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
            } else {
                let scale: CGFloat = isAmbient ? 0.55 : 1.0
                let c1 = settings.effectiveTintColor.withAlphaComponent(opacity * scale).cgColor
                let c2 = settings.effectiveTintColor2.withAlphaComponent(opacity * scale).cgColor
                gradientLayer.colors = [c1, c2]
                let rad = settings.gradientAngle * .pi / 180.0
                let dx = 0.5 * cos(rad), dy = 0.5 * sin(rad)
                gradientLayer.startPoint = CGPoint(x: 0.5 - dx, y: 0.5 - dy)
                gradientLayer.endPoint = CGPoint(x: 0.5 + dx, y: 0.5 + dy)
            }
            gradientLayer.compositingFilter = tintCompositingFilter
        } else {
            gradientLayer.isHidden = true
            tintLayer.isHidden = false
            tintLayer.backgroundColor = settings.effectiveTintColor.withAlphaComponent(opacity).cgColor
            tintLayer.compositingFilter = tintCompositingFilter
        }

        if settings.grainIntensity > 0.01 {
            if grainLayer.contents == nil {
                Self.grainImage { [weak self] img in
                    guard let self, let img else { return }
                    self.grainLayer.contents = img
                }
            }
            grainLayer.contentsGravity = .resize
            grainLayer.magnificationFilter = .nearest
            grainLayer.minificationFilter = .nearest
            grainLayer.compositingFilter = "softLightBlendMode"
            grainLayer.opacity = Float(0.05 + 0.35 * settings.grainIntensity)
            grainLayer.isHidden = false
        } else {
            grainLayer.isHidden = true
        }

        if settings.grayscale {
            let f = CIFilter(name: "CIColorControls")!
            f.setValue(0, forKey: kCIInputSaturationKey)
            layer?.filters = [f]
        } else {
            layer?.filters = nil
        }

        CATransaction.commit()

        applyShader(mode: settings.shaderMode, speed: settings.animationSpeed)
    }

    private func applyShader(mode: ShaderMode, speed: Double) {
        layer?.removeAnimation(forKey: "shader")
        layer?.opacity = 1
        layer?.transform = CATransform3DIdentity
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let s = max(0.1, speed)
        switch mode {
        case .staticMode:
            return
        case .breathing:
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0.75
            a.toValue = 1.0
            a.duration = 3.0 / s
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(a, forKey: "shader")
        case .pulse:
            let a = CABasicAnimation(keyPath: "transform.scale")
            a.fromValue = 1.0
            a.toValue = 1.015
            a.duration = 1.4 / s
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(a, forKey: "shader")
        case .drift:
            let g = CAAnimationGroup()
            let tx = CAKeyframeAnimation(keyPath: "transform.translation.x")
            tx.values = [0, 8, 0, -8, 0]
            let ty = CAKeyframeAnimation(keyPath: "transform.translation.y")
            ty.values = [0, -6, 0, 6, 0]
            g.animations = [tx, ty]
            g.duration = 7.0 / s
            g.repeatCount = .infinity
            layer?.add(g, forKey: "shader")
        }
    }

    private func applyBackdropImage(settings: QuietLensSettings) {
        let key: String
        let imageURL: URL?
        switch settings.backdropMode {
        case .blur:
            imageURL = nil
            key = ""
        case .image:
            if let p = settings.backdropImagePath, !p.isEmpty {
                imageURL = URL(fileURLWithPath: p)
                key = "image:\(p)"
            } else {
                imageURL = nil
                key = "image:nil"
            }
        case .wallpaper:
            if let screen = window?.screen ?? NSScreen.main {
                imageURL = NSWorkspace.shared.desktopImageURL(for: screen)
                key = "wallpaper:\(imageURL?.path ?? "nil")"
            } else {
                imageURL = nil
                key = "wallpaper:nil"
            }
        }
        guard key != lastBackdropKey else { return }
        lastBackdropKey = key
        if let url = imageURL, let image = NSImage(contentsOf: url) {
            var rect = NSRect(origin: .zero, size: image.size)
            backdropLayer.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        } else {
            backdropLayer.contents = nil
        }
    }

    // Grain generation used to run synchronously on the main thread with
    // 16M Swift RNG calls (~hundreds of ms hang the first time grain was
    // enabled). It now fills the noise planes with arc4random_buf on a
    // background queue and applies the result on the main thread.
    private static var cachedGrain: CGImage?
    private static var grainCallbacks: [(CGImage?) -> Void] = []

    /// Main-thread only. Calls back on the main thread with the cached or
    /// freshly generated grain texture.
    static func grainImage(_ completion: @escaping (CGImage?) -> Void) {
        if let g = cachedGrain { completion(g); return }
        grainCallbacks.append(completion)
        guard grainCallbacks.count == 1 else { return }
        DispatchQueue.global(qos: .utility).async {
            let img = makeGrain()
            DispatchQueue.main.async {
                cachedGrain = img
                let cbs = grainCallbacks
                grainCallbacks = []
                cbs.forEach { $0(img) }
            }
        }
    }

    private static func makeGrain() -> CGImage? {
        let w = 2048, h = 2048
        let cs = CGColorSpaceCreateDeviceRGB()
        let bpr = w * 4
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bpr, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var noiseA = [UInt8](repeating: 0, count: w * h)
        var noiseB = [UInt8](repeating: 0, count: w * h)
        arc4random_buf(&noiseA, noiseA.count)
        arc4random_buf(&noiseB, noiseB.count)
        let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(w * h) {
            let avg = (Int(noiseA[i]) + Int(noiseB[i])) / 2
            let v = UInt8(clamping: 96 + (avg - 128) * 80 / 128 + 64)
            buf[i * 4 + 0] = v
            buf[i * 4 + 1] = v
            buf[i * 4 + 2] = v
            buf[i * 4 + 3] = 255
        }
        return ctx.makeImage()
    }
}
