import CoreGraphics

struct WindowCornerRadii: Equatable {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomRight: CGFloat
    let bottomLeft: CGFloat

    init(uniform radius: CGFloat) {
        topLeft = radius
        topRight = radius
        bottomRight = radius
        bottomLeft = radius
    }

    func scaled(by scale: CGFloat) -> WindowCornerRadii {
        WindowCornerRadii(
            topLeft: topLeft * scale,
            topRight: topRight * scale,
            bottomRight: bottomRight * scale,
            bottomLeft: bottomLeft * scale
        )
    }

    init(
        topLeft: CGFloat,
        topRight: CGFloat,
        bottomRight: CGFloat,
        bottomLeft: CGFloat
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }
}
