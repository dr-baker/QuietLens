import CoreGraphics

@main
struct CutoutGeometryCheck {
    static func main() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let first = CGRect(x: 100, y: 100, width: 100, height: 100)
        let second = CGRect(x: 150, y: 100, width: 100, height: 100)
        let zero = WindowCornerRadii(uniform: 0)
        let overlap = CutoutGeometry.paths(bounds: bounds, rects: [first, second], cornerRadii: zero)
        precondition(!overlap.mask.contains(CGPoint(x: 175, y: 150), using: .evenOdd))
        precondition(!overlap.mask.contains(CGPoint(x: 125, y: 150), using: .evenOdd))
        precondition(overlap.mask.contains(CGPoint(x: 25, y: 25), using: .evenOdd))

        let duplicate = CutoutGeometry.paths(bounds: bounds, rects: [first, first], cornerRadii: zero)
        precondition(!duplicate.mask.contains(CGPoint(x: 150, y: 150), using: .evenOdd))
        let separate = CutoutGeometry.paths(
            bounds: bounds, rects: [first, CGRect(x: 275, y: 100, width: 100, height: 100)],
            cornerRadii: zero
        )
        precondition(separate.mask.contains(CGPoint(x: 250, y: 150), using: .evenOdd))
        precondition(!separate.mask.contains(CGPoint(x: 325, y: 150), using: .evenOdd))

        let asymmetric = WindowCornerRadii(topLeft: 20, topRight: 0, bottomRight: 0, bottomLeft: 0)
        let rounded = CutoutGeometry.paths(bounds: bounds, rects: [first], cornerRadii: asymmetric)
        precondition(rounded.mask.contains(CGPoint(x: 101, y: 199), using: .evenOdd))
        precondition(!rounded.mask.contains(CGPoint(x: 199, y: 199), using: .evenOdd))
        precondition(!rounded.mask.contains(CGPoint(x: 101, y: 101), using: .evenOdd))

        let empty = CutoutGeometry.paths(bounds: bounds, rects: [.zero, .null], cornerRadii: zero)
        precondition(empty.mask.contains(CGPoint(x: 150, y: 150), using: .evenOdd))
        let crossing = CGRect(x: -40, y: 100, width: 100, height: 100)
        guard let local = CutoutGeometry.localRect(for: crossing, overlay: bounds) else {
            fatalError("Expected the window crossing the overlay")
        }
        precondition(local == crossing)
        let seam = CutoutGeometry.paths(bounds: bounds, rects: [local], cornerRadii: .init(uniform: 20))
        precondition(!seam.mask.contains(CGPoint(x: 1, y: 199), using: .evenOdd))
        precondition(CutoutGeometry.localRect(for: first, overlay: CGRect(x: 500, y: 0, width: 100, height: 100)) == nil)
        print("Cutout overlap, duplicates, separate windows, corners, and display seams: passed")
    }
}
