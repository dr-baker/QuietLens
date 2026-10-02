import Foundation
import CoreGraphics
import Darwin

struct WindowCornerFingerprint: Equatable, Sendable {
    let ownerPID: pid_t
    let logicalSize: CGSize
    let displayScale: CGFloat

    fileprivate var isValid: Bool {
        ownerPID > 0 && logicalSize.width.isFinite && logicalSize.height.isFinite
            && logicalSize.width > 0 && logicalSize.height > 0
            && displayScale.isFinite && displayScale > 0
    }
}

/// Reads the compositor-produced alpha silhouette for a window and reduces it
/// to four corner radii. Captures stay off the main thread and are cached by
/// owner, size, and display scale so a focus change never waits for capture.
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

    typealias Completion = @MainActor (WindowCornerRadii?) -> Void
    typealias Capture = (CGWindowID, WindowCornerFingerprint, @escaping Completion) -> Void

    private enum Value {
        case sample(WindowCornerRadii)
        case failure
        case pending(token: UInt64, callbacks: [Completion])
    }

    private struct Entry {
        let fingerprint: WindowCornerFingerprint
        let generation: UInt64
        var value: Value
        var resolvedAt: TimeInterval
        var lastAccess: UInt64
    }

    private static let captureQueue = DispatchQueue(
        label: "app.quiet.QuietLens.window-corners",
        qos: .userInitiated
    )

    private let capture: Capture
    private let now: () -> TimeInterval
    private let capacity: Int
    private let maximumPendingCaptures: Int
    private let maximumCallbacksPerCapture: Int
    private let failureCooldown: TimeInterval
    private let sampleLifetime: TimeInterval
    private var entries: [CGWindowID: Entry] = [:]
    private var outstandingRequests: Set<UInt64> = []
    private var sequence: UInt64 = 0

    private convenience init() {
        self.init(capture: { windowID, fingerprint, completion in
            Self.captureQueue.async {
                let radii = Self.readRadii(windowID: windowID, fingerprint: fingerprint)
                DispatchQueue.main.async { completion(radii) }
            }
        })
    }

    init(
        capture: @escaping Capture,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        capacity: Int = 128,
        maximumPendingCaptures: Int = 8,
        maximumCallbacksPerCapture: Int = 16,
        failureCooldown: TimeInterval = 1,
        sampleLifetime: TimeInterval = 30
    ) {
        self.capture = capture
        self.now = now
        self.capacity = max(1, capacity)
        self.maximumPendingCaptures = max(1, maximumPendingCaptures)
        self.maximumCallbacksPerCapture = max(1, maximumCallbacksPerCapture)
        self.failureCooldown = max(0, failureCooldown)
        self.sampleLifetime = max(0, sampleLifetime)
    }

    func cachedRadii(
        for windowID: CGWindowID,
        fingerprint: WindowCornerFingerprint
    ) -> WindowCornerRadii? {
        guard windowID != 0, fingerprint.isValid else {
            entries.removeValue(forKey: windowID)
            return nil
        }
        guard let entry = currentEntry(for: windowID, fingerprint: fingerprint),
              case let .sample(radii) = entry.value else { return nil }
        return radii
    }

    func resolve(
        windowID: CGWindowID,
        fingerprint: WindowCornerFingerprint,
        completion: @escaping Completion
    ) {
        guard windowID != 0, fingerprint.isValid else {
            entries.removeValue(forKey: windowID)
            completion(nil)
            return
        }

        if var entry = currentEntry(for: windowID, fingerprint: fingerprint) {
            switch entry.value {
            case let .sample(radii):
                completion(radii)
            case .failure:
                completion(nil)
            case let .pending(token, callbacks):
                guard callbacks.count < maximumCallbacksPerCapture else {
                    completion(nil)
                    return
                }
                entry.value = .pending(token: token, callbacks: callbacks + [completion])
                entries[windowID] = entry
            }
            return
        }

        sequence &+= 1
        let token = sequence
        let hasCaptureSlot = outstandingRequests.count < maximumPendingCaptures
        entries[windowID] = Entry(
            fingerprint: fingerprint,
            generation: token,
            value: hasCaptureSlot ? .pending(token: token, callbacks: [completion]) : .failure,
            resolvedAt: now(),
            lastAccess: nextAccess()
        )
        trimCache()
        guard hasCaptureSlot else {
            completion(nil)
            return
        }

        outstandingRequests.insert(token)
        capture(windowID, fingerprint) { [weak self] radii in
            self?.finish(windowID: windowID, fingerprint: fingerprint, token: token, radii: radii)
        }
    }

    /// Observing new geometry cancels old callbacks even when no replacement
    /// capture has started. Its queued capture still counts against the work cap.
    private func currentEntry(
        for windowID: CGWindowID,
        fingerprint: WindowCornerFingerprint
    ) -> Entry? {
        guard var entry = entries[windowID] else { return nil }
        let lifetime: TimeInterval
        switch entry.value {
        case .sample: lifetime = sampleLifetime
        case .failure: lifetime = failureCooldown
        case .pending: lifetime = .infinity
        }
        guard entry.fingerprint == fingerprint,
              now() - entry.resolvedAt < lifetime else {
            entries.removeValue(forKey: windowID)
            return nil
        }
        entry.lastAccess = nextAccess()
        entries[windowID] = entry
        return entry
    }

    private func finish(
        windowID: CGWindowID,
        fingerprint: WindowCornerFingerprint,
        token: UInt64,
        radii: WindowCornerRadii?
    ) {
        guard outstandingRequests.remove(token) != nil,
              var entry = entries[windowID],
              entry.fingerprint == fingerprint,
              case let .pending(currentToken, callbacks) = entry.value,
              currentToken == token else { return }

        entry.value = radii.map(Value.sample) ?? .failure
        entry.resolvedAt = now()
        entry.lastAccess = nextAccess()
        entries[windowID] = entry
        for callback in callbacks {
            guard entries[windowID]?.generation == token else { break }
            callback(radii)
        }
    }

    private func nextAccess() -> UInt64 {
        sequence &+= 1
        return sequence
    }

    private func trimCache() {
        while entries.count > capacity {
            // Failed requests at the work cap must not evict the captures
            // already serving current callers when there is another victim.
            let resolved = entries.filter {
                if case .pending = $0.value.value { return false }
                return true
            }
            let candidates = resolved.isEmpty ? entries : resolved
            guard let oldest = candidates.min(by: {
                $0.value.lastAccess < $1.value.lastAccess
            })?.key else { return }
            entries.removeValue(forKey: oldest)
        }
    }

    private nonisolated static func readRadii(
        windowID: CGWindowID,
        fingerprint: WindowCornerFingerprint
    ) -> WindowCornerRadii? {
        // Nominal resolution makes image pixels equal screen points, including
        // on Retina displays. The mask must never consume device-pixel radii.
        let imageOptions: CGWindowImageOption = [.boundsIgnoreFraming, .nominalResolution]
        guard let createWindowImage, matches(windowID: windowID, fingerprint: fingerprint),
              let imagePointer = createWindowImage(
                .null,
                CGWindowListOption.optionIncludingWindow.rawValue,
                windowID,
                imageOptions.rawValue
              ) else { return nil }
        let image = Unmanaged<CGImage>.fromOpaque(imagePointer).takeRetainedValue()
        guard matches(windowID: windowID, fingerprint: fingerprint) else { return nil }
        return radii(from: image)
    }

    private nonisolated static func matches(
        windowID: CGWindowID,
        fingerprint: WindowCornerFingerprint
    ) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
                as? [[String: Any]],
              let window = windows.first(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
              }),
              (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == fingerprint.ownerPID,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
        return abs(frame.width - fingerprint.logicalSize.width) <= 1
            && abs(frame.height - fingerprint.logicalSize.height) <= 1
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
