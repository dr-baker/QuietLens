import Foundation
import CoreGraphics

@MainActor
private final class ManualCornerCaptures {
    struct Request {
        let windowID: CGWindowID
        let fingerprint: WindowCornerFingerprint
        let completion: WindowCornerReader.Completion
    }

    var requests: [Request] = []

    func capture(
        _ windowID: CGWindowID,
        fingerprint: WindowCornerFingerprint,
        completion: @escaping WindowCornerReader.Completion
    ) {
        requests.append(Request(windowID: windowID, fingerprint: fingerprint, completion: completion))
    }

    func finish(_ index: Int, with radii: WindowCornerRadii?) {
        requests[index].completion(radii)
    }
}

@main
struct WindowCornerCacheCheck {
    private static let radii = WindowCornerRadii(uniform: 12)
    private static let fingerprint = WindowCornerFingerprint(
        ownerPID: 101,
        logicalSize: CGSize(width: 800, height: 600),
        displayScale: 2
    )

    @MainActor
    static func main() {
        failedCaptureRetries()
        staleCompletions()
        fingerprintAndLifetime()
        deduplicationAndCallbackBound()
        callbackSupersedesGeometry()
        supersededCapturesHoldWorkSlots()
        cacheAndWorkBounds()
        print("Corner cooldown, sample invalidation, stale capture fencing, deduplication, and bounds: passed")
    }

    @MainActor
    private static func failedCaptureRetries() {
        var time: TimeInterval = 0
        let captures = ManualCornerCaptures()
        let reader = WindowCornerReader(capture: captures.capture, now: { time })
        var results: [WindowCornerRadii?] = []
        reader.resolve(windowID: 1, fingerprint: fingerprint) { results.append($0) }
        precondition(results.isEmpty)
        precondition(captures.requests[0].fingerprint == fingerprint)
        captures.finish(0, with: nil)
        precondition(results.count == 1 && results[0] == nil)

        time = 0.9
        reader.resolve(windowID: 1, fingerprint: fingerprint) { results.append($0) }
        precondition(results.count == 2 && results[1] == nil)
        precondition(captures.requests.count == 1)

        time = 1
        reader.resolve(windowID: 1, fingerprint: fingerprint) { results.append($0) }
        precondition(captures.requests.count == 2)
        captures.finish(1, with: radii)
        precondition(results.count == 3 && results[2] == radii)
        precondition(reader.cachedRadii(for: 1, fingerprint: fingerprint) == radii)
    }

    @MainActor
    private static func staleCompletions() {
        let captures = ManualCornerCaptures()
        let reader = WindowCornerReader(capture: captures.capture)
        let resized = WindowCornerFingerprint(
            ownerPID: fingerprint.ownerPID,
            logicalSize: CGSize(width: 900, height: 600),
            displayScale: fingerprint.displayScale
        )
        var oldResults = 0
        var newResults: [WindowCornerRadii?] = []
        reader.resolve(windowID: 1, fingerprint: fingerprint) { _ in oldResults += 1 }
        precondition(reader.cachedRadii(for: 1, fingerprint: resized) == nil)
        reader.resolve(windowID: 1, fingerprint: resized) { newResults.append($0) }
        captures.finish(0, with: WindowCornerRadii(uniform: 20))
        precondition(oldResults == 0 && newResults.isEmpty)
        precondition(reader.cachedRadii(for: 1, fingerprint: resized) == nil)
        captures.finish(1, with: radii)
        precondition(newResults.count == 1 && newResults[0] == radii)

        // Returning to the same fingerprint still requires the current token.
        reader.resolve(windowID: 2, fingerprint: fingerprint) { _ in oldResults += 1 }
        reader.resolve(windowID: 2, fingerprint: resized) { _ in oldResults += 1 }
        reader.resolve(windowID: 2, fingerprint: fingerprint) { newResults.append($0) }
        captures.finish(2, with: WindowCornerRadii(uniform: 20))
        captures.finish(3, with: WindowCornerRadii(uniform: 18))
        precondition(oldResults == 0 && newResults.count == 1)
        captures.finish(4, with: radii)
        precondition(newResults.count == 2 && newResults[1] == radii)
        captures.finish(2, with: WindowCornerRadii(uniform: 30))
        precondition(reader.cachedRadii(for: 2, fingerprint: fingerprint) == radii)

        let invalid = WindowCornerFingerprint(ownerPID: 0, logicalSize: .zero, displayScale: 0)
        reader.resolve(windowID: 3, fingerprint: fingerprint) { _ in oldResults += 1 }
        precondition(reader.cachedRadii(for: 3, fingerprint: invalid) == nil)
        captures.finish(5, with: radii)
        precondition(oldResults == 0)
    }

    @MainActor
    private static func fingerprintAndLifetime() {
        var time: TimeInterval = 0
        var captureCount = 0
        let reader = WindowCornerReader(
            capture: { _, _, completion in captureCount += 1; completion(radii) },
            now: { time }
        )
        reader.resolve(windowID: 1, fingerprint: fingerprint) { precondition($0 == radii) }
        time = 29.9
        precondition(reader.cachedRadii(for: 1, fingerprint: fingerprint) == radii)
        time = 30
        precondition(reader.cachedRadii(for: 1, fingerprint: fingerprint) == nil)
        reader.resolve(windowID: 1, fingerprint: fingerprint) { precondition($0 == radii) }
        precondition(captureCount == 2)

        let replacementOwner = WindowCornerFingerprint(
            ownerPID: 202, logicalSize: fingerprint.logicalSize, displayScale: 2
        )
        precondition(reader.cachedRadii(for: 1, fingerprint: replacementOwner) == nil)
        reader.resolve(windowID: 1, fingerprint: replacementOwner) { precondition($0 == radii) }
        let newScale = WindowCornerFingerprint(
            ownerPID: 202, logicalSize: fingerprint.logicalSize, displayScale: 1
        )
        precondition(reader.cachedRadii(for: 1, fingerprint: newScale) == nil)
        reader.resolve(windowID: 1, fingerprint: newScale) { precondition($0 == radii) }
        precondition(captureCount == 4)
    }

    @MainActor
    private static func deduplicationAndCallbackBound() {
        let captures = ManualCornerCaptures()
        let reader = WindowCornerReader(capture: captures.capture, maximumCallbacksPerCapture: 2)
        var results: [WindowCornerRadii?] = []
        for _ in 0..<3 {
            reader.resolve(windowID: 1, fingerprint: fingerprint) { results.append($0) }
        }
        precondition(captures.requests.count == 1)
        precondition(results.count == 1 && results[0] == nil)
        captures.finish(0, with: radii)
        precondition(results.count == 3 && results[1] == radii && results[2] == radii)
        reader.resolve(windowID: 1, fingerprint: fingerprint) { results.append($0) }
        precondition(captures.requests.count == 1 && results.count == 4)
    }

    @MainActor
    private static func callbackSupersedesGeometry() {
        let captures = ManualCornerCaptures()
        let reader = WindowCornerReader(capture: captures.capture)
        let resized = WindowCornerFingerprint(
            ownerPID: fingerprint.ownerPID,
            logicalSize: CGSize(width: 900, height: 600),
            displayScale: fingerprint.displayScale
        )
        var supersededResults = 0
        var currentResults = 0
        reader.resolve(windowID: 1, fingerprint: fingerprint) { _ in
            reader.resolve(windowID: 1, fingerprint: resized) {
                precondition($0 == radii)
                currentResults += 1
            }
        }
        reader.resolve(windowID: 1, fingerprint: fingerprint) { _ in supersededResults += 1 }
        captures.finish(0, with: radii)
        precondition(supersededResults == 0 && currentResults == 0)
        captures.finish(1, with: radii)
        precondition(currentResults == 1)
    }

    @MainActor
    private static func supersededCapturesHoldWorkSlots() {
        var time: TimeInterval = 0
        let captures = ManualCornerCaptures()
        let reader = WindowCornerReader(capture: captures.capture, now: { time }, maximumPendingCaptures: 2)
        let resized = WindowCornerFingerprint(ownerPID: 101, logicalSize: CGSize(width: 900, height: 600), displayScale: 2)
        let resizedAgain = WindowCornerFingerprint(ownerPID: 101, logicalSize: CGSize(width: 1000, height: 600), displayScale: 2)
        var staleCallbacks = 0
        var rejections = 0
        var currentCallbacks = 0
        reader.resolve(windowID: 1, fingerprint: fingerprint) { _ in staleCallbacks += 1 }
        reader.resolve(windowID: 1, fingerprint: resized) { _ in staleCallbacks += 1 }
        reader.resolve(windowID: 1, fingerprint: resizedAgain) {
            precondition($0 == nil)
            rejections += 1
        }
        precondition(captures.requests.count == 2 && rejections == 1)
        captures.finish(0, with: radii)
        precondition(staleCallbacks == 0)
        time = 1
        reader.resolve(windowID: 1, fingerprint: resizedAgain) {
            precondition($0 == radii)
            currentCallbacks += 1
        }
        precondition(captures.requests.count == 3)
        captures.finish(1, with: radii)
        precondition(staleCallbacks == 0 && currentCallbacks == 0)
        captures.finish(2, with: radii)
        precondition(currentCallbacks == 1)
    }

    @MainActor
    private static func cacheAndWorkBounds() {
        var captureCount = 0
        let cache = WindowCornerReader(
            capture: { _, _, completion in captureCount += 1; completion(radii) },
            capacity: 3
        )
        for windowID in CGWindowID(1)...4 {
            cache.resolve(windowID: windowID, fingerprint: fingerprint) { precondition($0 == radii) }
        }
        precondition(cache.cachedRadii(for: 1, fingerprint: fingerprint) == nil)
        precondition(cache.cachedRadii(for: 2, fingerprint: fingerprint) == radii)
        cache.resolve(windowID: 5, fingerprint: fingerprint) { precondition($0 == radii) }
        precondition(cache.cachedRadii(for: 3, fingerprint: fingerprint) == nil)
        precondition(cache.cachedRadii(for: 2, fingerprint: fingerprint) == radii)
        precondition(cache.cachedRadii(for: 4, fingerprint: fingerprint) == radii)
        precondition(cache.cachedRadii(for: 5, fingerprint: fingerprint) == radii)
        precondition(captureCount == 5)

        var time: TimeInterval = 0
        let captures = ManualCornerCaptures()
        let work = WindowCornerReader(
            capture: captures.capture, now: { time }, maximumPendingCaptures: 2
        )
        var rejected = 0
        var completed = 0
        for windowID in CGWindowID(1)...2 {
            work.resolve(windowID: windowID, fingerprint: fingerprint) {
                precondition($0 == radii)
                completed += 1
            }
        }
        for windowID in CGWindowID(3)...200 {
            work.resolve(windowID: windowID, fingerprint: fingerprint) {
                precondition($0 == nil)
                rejected += 1
            }
        }
        precondition(captures.requests.count == 2 && rejected == 198)
        captures.finish(0, with: radii)
        captures.finish(1, with: radii)
        precondition(completed == 2)
        time = 1
        work.resolve(windowID: 200, fingerprint: fingerprint) { precondition($0 == radii) }
        precondition(captures.requests.count == 3)
        captures.finish(2, with: radii)
        precondition(work.cachedRadii(for: 200, fingerprint: fingerprint) == radii)
    }
}
