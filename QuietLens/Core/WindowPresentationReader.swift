import AppKit
import CoreGraphics
import Darwin

/// Reads the WindowServer presentation transform for a window. Mission Control
/// changes this transform without changing the window's logical AX frame.
@MainActor
final class WindowPresentationReader {
    static let shared = WindowPresentationReader()

    private typealias MainConnectionIDFunc = @convention(c) () -> Int32
    private typealias GetWindowRectFunc = @convention(c) (
        Int32, CGWindowID, UnsafeMutablePointer<CGRect>
    ) -> Int32
    private typealias GetWindowTransformFunc = @convention(c) (
        Int32, CGWindowID, UnsafeMutablePointer<CGAffineTransform>
    ) -> Int32

    private static let framework = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY
    )

    private static func symbol<T>(_ names: [String], as type: T.Type) -> T? {
        guard let framework else { return nil }
        for name in names {
            if let value = dlsym(framework, name) {
                return unsafeBitCast(value, to: type)
            }
        }
        return nil
    }

    private static let mainConnectionID = symbol(
        ["SLSMainConnectionID", "CGSMainConnectionID", "_CGSDefaultConnection"],
        as: MainConnectionIDFunc.self
    )
    private static let getWindowRect = symbol(
        ["SLSGetScreenRectForWindow", "CGSGetScreenRectForWindow"],
        as: GetWindowRectFunc.self
    )
    private static let getWindowTransform = symbol(
        ["SLSGetWindowTransform", "CGSGetWindowTransform"],
        as: GetWindowTransformFunc.self
    )

    private init() {}

    /// Returns the current WindowServer presentation bounds in Core Graphics
    /// coordinates. The inverse transform maps window-local points to screen.
    func presentationFrame(for windowID: CGWindowID) -> CGRect? {
        guard windowID != 0,
              let mainConnectionID = Self.mainConnectionID,
              let getWindowRect = Self.getWindowRect else { return nil }

        let connectionID = mainConnectionID()
        guard connectionID != 0 else { return nil }

        var logicalFrame = CGRect.zero
        guard getWindowRect(connectionID, windowID, &logicalFrame) == 0,
              Self.isValid(logicalFrame) else { return nil }

        guard let getWindowTransform = Self.getWindowTransform else {
            return logicalFrame
        }

        var transform = CGAffineTransform.identity
        guard getWindowTransform(connectionID, windowID, &transform) == 0,
              Self.isValid(transform) else {
            return logicalFrame
        }

        let determinant = transform.a * transform.d - transform.b * transform.c
        guard abs(determinant) > 0.000_001 else { return logicalFrame }

        let localBounds = CGRect(origin: .zero, size: logicalFrame.size)
        let presentationFrame = localBounds.applying(transform.inverted()).standardized
        return Self.isValid(presentationFrame) ? presentationFrame : logicalFrame
    }

    /// Finds the frontmost transformed application window below a click in
    /// Mission Control. CGWindowList remains front-to-back while SkyLight owns
    /// each window's live presentation transform.
    func windowID(at cocoaPoint: CGPoint, excludingPID: pid_t) -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else { return nil }

        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != excludingPID,
                  let windowID = window[kCGWindowNumber as String] as? CGWindowID,
                  let frame = presentationFrame(for: windowID),
                  Self.cgToCocoa(frame).contains(cocoaPoint) else { continue }
            return windowID
        }
        return nil
    }

    private static func cgToCocoa(_ frame: CGRect) -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else { return frame }
        return CGRect(
            x: frame.minX,
            y: primaryScreen.frame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private static func isValid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
            && frame.width > 1 && frame.height > 1
    }

    private static func isValid(_ transform: CGAffineTransform) -> Bool {
        [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]
            .allSatisfy(\.isFinite)
    }
}
