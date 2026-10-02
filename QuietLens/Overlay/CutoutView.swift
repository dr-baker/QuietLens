import AppKit
import QuartzCore

final class CutoutView: NSView {
    static var standardWindowCornerRadius: CGFloat {
        if #available(macOS 26.0, *) { return 16 }
        return 10
    }

    static var standardWindowCornerRadii: WindowCornerRadii {
        WindowCornerRadii(uniform: standardWindowCornerRadius)
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
        cornerRadii: WindowCornerRadii = CutoutView.standardWindowCornerRadii
    ) {
        let path = CGMutablePath()
        path.addRect(bounds)
        let rimPath = CGMutablePath()
        for r in rects {
            let rounded = Self.roundedRectPath(r, radii: cornerRadii)
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

    private static func roundedRectPath(_ rect: CGRect, radii: WindowCornerRadii) -> CGPath {
        let maximum = min(rect.width, rect.height) * 0.5
        let topLeft = min(maximum, max(0, radii.topLeft))
        let topRight = min(maximum, max(0, radii.topRight))
        let bottomRight = min(maximum, max(0, radii.bottomRight))
        let bottomLeft = min(maximum, max(0, radii.bottomLeft))
        let path = CGMutablePath()

        path.move(to: CGPoint(x: rect.minX + bottomLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - bottomRight, y: rect.minY))
        if bottomRight > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - bottomRight, y: rect.minY + bottomRight),
                radius: bottomRight,
                startAngle: -.pi / 2,
                endAngle: 0,
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - topRight))
        if topRight > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - topRight, y: rect.maxY - topRight),
                radius: topRight,
                startAngle: 0,
                endAngle: .pi / 2,
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + topLeft, y: rect.maxY))
        if topLeft > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + topLeft, y: rect.maxY - topLeft),
                radius: topLeft,
                startAngle: .pi / 2,
                endAngle: .pi,
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bottomLeft))
        if bottomLeft > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + bottomLeft, y: rect.minY + bottomLeft),
                radius: bottomLeft,
                startAngle: .pi,
                endAngle: .pi * 3 / 2,
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
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
