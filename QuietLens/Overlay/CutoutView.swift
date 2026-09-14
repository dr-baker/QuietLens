import AppKit
import QuartzCore

final class CutoutView: NSView {
    static var standardWindowCornerRadius: CGFloat {
        if #available(macOS 26.0, *) { return 16 }
        return 10
    }

    weak var maskTarget: NSView?
    private let maskLayer = CAShapeLayer()
    private let glowLayer = CAShapeLayer()
    private var currentPath: CGPath?
    private var currentRimPath: CGPath?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = NSColor.white.cgColor

        glowLayer.fillColor = NSColor.clear.cgColor
        glowLayer.strokeColor = NSColor.white.withAlphaComponent(0.55).cgColor
        glowLayer.lineWidth = 2.0
        glowLayer.shadowColor = NSColor.white.cgColor
        glowLayer.shadowOpacity = 0.8
        glowLayer.shadowOffset = .zero
        glowLayer.shadowRadius = 12
        glowLayer.isHidden = true
        layer?.addSublayer(glowLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setCutouts(
        _ rects: [CGRect],
        duration: TimeInterval,
        cornerRadius: CGFloat = CutoutView.standardWindowCornerRadius
    ) {
        let path = CGMutablePath()
        path.addRect(bounds)
        let rimPath = CGMutablePath()
        for r in rects {
            let radius = min(cornerRadius, min(r.width, r.height) * 0.5)
            let rounded = CGPath(
                roundedRect: r,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
            path.addPath(rounded)
            rimPath.addPath(rounded)
        }
        guard let target = maskTarget else { return }
        target.wantsLayer = true
        if target.layer?.mask !== maskLayer {
            maskLayer.frame = target.bounds
            target.layer?.mask = maskLayer
        }
        maskLayer.frame = target.bounds
        glowLayer.frame = bounds

        if duration > 0.01 {
            if let old = currentPath {
                let anim = CABasicAnimation(keyPath: "path")
                anim.fromValue = old
                anim.toValue = path
                anim.duration = duration
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                maskLayer.add(anim, forKey: "path")
            }
            if let oldRim = currentRimPath {
                let anim = CABasicAnimation(keyPath: "path")
                anim.fromValue = oldRim
                anim.toValue = rimPath
                anim.duration = duration
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                glowLayer.add(anim, forKey: "path")
            }
        }
        maskLayer.path = path
        glowLayer.path = rimPath
        currentPath = path
        currentRimPath = rimPath
    }

    func applyGlow(enabled: Bool, color: NSColor, radius: CGFloat) {
        glowLayer.isHidden = !enabled
        glowLayer.strokeColor = color.withAlphaComponent(0.7).cgColor
        glowLayer.shadowColor = color.cgColor
        glowLayer.shadowRadius = radius
        glowLayer.shadowOpacity = enabled ? 0.85 : 0
        glowLayer.lineWidth = max(1, radius * 0.18)
    }
}
