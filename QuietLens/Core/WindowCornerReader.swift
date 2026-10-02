import CoreGraphics
import Darwin

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

    fileprivate init(
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

/// Reads the compositor-produced alpha silhouette for a window and reduces it
/// to four corner radii. Captures stay off the main thread and are cached by
/// WindowServer ID so a focus change never waits for screen capture.
@MainActor
final class WindowCornerReader {
    static let shared = WindowCornerReader()

    private typealias WindowListCreateImageFunc = @convention(c) (
        CGRect, UInt32, UInt32, UInt32
    ) -> UnsafeRawPointer?

    private nonisolated(unsafe) static let coreGraphicsHandle = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        RTLD_LAZY
    )
    private nonisolated static let createWindowImage: WindowListCreateImageFunc? = {
        guard let coreGraphicsHandle,
              let symbol = dlsym(coreGraphicsHandle, "CGWindowListCreateImage") else {
            return nil
        }
        return unsafeBitCast(symbol, to: WindowListCreateImageFunc.self)
    }()

    private let captureQueue = DispatchQueue(
        label: "app.quiet.QuietLens.window-corners",
        qos: .userInitiated
    )
    private var cached: [CGWindowID: WindowCornerRadii] = [:]
    private var resolved: Set<CGWindowID> = []
    private var pendingCallbacks: [CGWindowID: [(WindowCornerRadii?) -> Void]] = [:]

    private init() {}

    func cachedRadii(for windowID: CGWindowID) -> WindowCornerRadii? {
        cached[windowID]
    }

    func resolve(
        windowID: CGWindowID,
        completion: @escaping (WindowCornerRadii?) -> Void
    ) {
        guard windowID != 0 else {
            completion(nil)
            return
        }
        if resolved.contains(windowID) {
            completion(cached[windowID])
            return
        }

        pendingCallbacks[windowID, default: []].append(completion)
        guard pendingCallbacks[windowID]?.count == 1 else { return }

        captureQueue.async {
            let radii = Self.readRadii(windowID: windowID)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.resolved.insert(windowID)
                if let radii { self.cached[windowID] = radii }
                let callbacks = self.pendingCallbacks.removeValue(forKey: windowID) ?? []
                callbacks.forEach { $0(radii) }

                if self.resolved.count > 128 {
                    self.resolved.removeAll(keepingCapacity: true)
                    self.cached.removeAll(keepingCapacity: true)
                }
            }
        }
    }

    private nonisolated static func readRadii(windowID: CGWindowID) -> WindowCornerRadii? {
        guard let createWindowImage,
              let imagePointer = createWindowImage(
                .null,
                CGWindowListOption.optionIncludingWindow.rawValue,
                windowID,
                CGWindowImageOption.boundsIgnoreFraming.rawValue
              ) else { return nil }
        let image = Unmanaged<CGImage>.fromOpaque(imagePointer).takeRetainedValue()
        return radii(from: image)
    }

    private nonisolated static func radii(from image: CGImage) -> WindowCornerRadii? {
        guard image.bitsPerComponent == 8,
              image.bitsPerPixel >= 32,
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data),
              let alphaOffset = alphaOffset(for: image) else { return nil }

        let width = image.width
        let height = image.height
        let bytesPerPixel = image.bitsPerPixel / 8
        let limit = min(96, min(width, height) / 3)
        guard limit > 0 else { return nil }

        func alpha(x: Int, y: Int) -> UInt8 {
            bytes[y * image.bytesPerRow + x * bytesPerPixel + alphaOffset]
        }
        func firstOpaque(_ points: [(Int, Int)]) -> Int? {
            points.firstIndex { alpha(x: $0.0, y: $0.1) >= 128 }
        }

        let topLeft = radius(
            firstOpaque((0..<limit).map { ($0, 0) }),
            firstOpaque((0..<limit).map { (0, $0) })
        )
        let topRight = radius(
            firstOpaque((0..<limit).map { (width - 1 - $0, 0) }),
            firstOpaque((0..<limit).map { (width - 1, $0) })
        )
        let bottomRight = radius(
            firstOpaque((0..<limit).map { (width - 1 - $0, height - 1) }),
            firstOpaque((0..<limit).map { (width - 1, height - 1 - $0) })
        )
        let bottomLeft = radius(
            firstOpaque((0..<limit).map { ($0, height - 1) }),
            firstOpaque((0..<limit).map { (0, height - 1 - $0) })
        )

        let measured = [topLeft, topRight, bottomRight, bottomLeft].compactMap { $0 }
        guard !measured.isEmpty else { return nil }
        let fallback = measured.sorted()[measured.count / 2]
        return WindowCornerRadii(
            topLeft: topLeft ?? fallback,
            topRight: topRight ?? fallback,
            bottomRight: bottomRight ?? fallback,
            bottomLeft: bottomLeft ?? fallback
        )
    }

    private nonisolated static func radius(_ first: Int?, _ second: Int?) -> CGFloat? {
        let values = [first, second].compactMap { $0 }
        guard let inset = values.max() else { return nil }
        return inset == 0 ? 0 : CGFloat(inset + 1)
    }

    private nonisolated static func alphaOffset(for image: CGImage) -> Int? {
        let lastByte = image.bitsPerPixel / 8 - 1
        let littleEndian = image.bitmapInfo.contains(.byteOrder32Little)
        switch (image.alphaInfo, littleEndian) {
        case (.premultipliedFirst, false), (.first, false),
             (.premultipliedLast, true), (.last, true):
            return 0
        case (.premultipliedFirst, true), (.first, true),
             (.premultipliedLast, false), (.last, false):
            return lastByte
        default:
            return nil
        }
    }
}
