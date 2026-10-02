import CoreGraphics

enum CutoutGeometry {
    static func localRect(for window: CGRect, overlay: CGRect) -> CGRect? {
        guard valid(window), valid(overlay), window.intersects(overlay) else { return nil }
        // Keep the original corners outside the overlay when a window crosses
        // displays. Rounding a clipped intersection invents corners at the seam.
        return window.offsetBy(dx: -overlay.minX, dy: -overlay.minY)
    }

    static func paths(
        bounds: CGRect,
        rects: [CGRect],
        cornerRadii: WindowCornerRadii
    ) -> (mask: CGPath, rim: CGPath) {
        let holes = CGMutablePath()
        var count = 0
        for rect in rects where valid(rect) {
            holes.addPath(roundedRectPath(rect, radii: cornerRadii))
            count += 1
        }
        // Normalize same-direction subpaths using winding fill, so overlapping
        // and duplicate clear windows form a union rather than canceling.
        let rim: CGPath = count > 1 ? holes.normalized(using: .winding) : holes
        let mask = CGMutablePath()
        mask.addRect(bounds)
        mask.addPath(rim)
        return (mask, rim)
    }

    private static func valid(_ rect: CGRect) -> Bool {
        rect.minX.isFinite && rect.minY.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }

    static func roundedRectPath(_ rect: CGRect, radii: WindowCornerRadii) -> CGPath {
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
}
