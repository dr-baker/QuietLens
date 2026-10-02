import Foundation
import CoreGraphics
import Darwin

@MainActor
final class WindowRaiser {
    static let shared = WindowRaiser(backend: Backend.live())

    enum WindowState {
        case present(ownerPID: pid_t, level: Int32)
        case gone
        case unavailable
    }

    struct Backend {
        let windowState: (CGWindowID) -> WindowState
        let setLevel: (CGWindowID, Int32) -> Bool
    }

    typealias Retry = @MainActor @Sendable () -> Void
    typealias RetryScheduler = (TimeInterval, @escaping Retry) -> Void

    private struct RaisedWindow {
        let ownerPID: pid_t
        let originalLevel: Int32
        var restorationAttempts = 0
    }

    private let backend: Backend?
    private let maximumRestorationAttempts: Int
    private let scheduleRetry: RetryScheduler
    private var raised: [CGWindowID: RaisedWindow] = [:]
    private var requestedOwners: [CGWindowID: pid_t] = [:]
    private var retryScheduled = false

    init(
        backend: Backend?,
        maximumRestorationAttempts: Int = 4,
        scheduleRetry: @escaping RetryScheduler = { delay, retry in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: retry)
        }
    ) {
        self.backend = backend
        self.maximumRestorationAttempts = max(1, maximumRestorationAttempts)
        self.scheduleRetry = scheduleRetry
    }

    /// The owner comes from the caller's current selection, so an old window
    /// number cannot raise a different process's replacement window.
    func setRaised(_ windows: [CGWindowID: pid_t], level: Int32) {
        requestedOwners = windows.filter { $0.key != 0 && $0.value > 0 }

        for (windowID, record) in raised
            where requestedOwners[windowID] != record.ownerPID
                && (record.restorationAttempts == 0
                    || record.restorationAttempts >= maximumRestorationAttempts) {
            restore(windowID)
        }

        if let backend {
            for (windowID, ownerPID) in requestedOwners {
                let state = backend.windowState(windowID)
                if case .gone = state { raised.removeValue(forKey: windowID) }
                if case let .present(currentOwner, _) = state,
                   let record = raised[windowID], record.ownerPID != currentOwner {
                    raised.removeValue(forKey: windowID)
                }
                guard case let .present(currentOwner, currentLevel) = state,
                      currentOwner == ownerPID else { continue }

                if var record = raised[windowID] {
                    guard record.ownerPID == ownerPID else { continue }
                    record.restorationAttempts = 0
                    if currentLevel != level {
                        guard backend.setLevel(windowID, level) else {
                            raised[windowID] = record
                            continue
                        }
                    }
                    raised[windowID] = record
                } else if currentLevel != level, backend.setLevel(windowID, level) {
                    raised[windowID] = RaisedWindow(
                        ownerPID: ownerPID,
                        originalLevel: currentLevel
                    )
                }
            }
        }

        scheduleRestorationRetryIfNeeded()
    }

    /// Also includes windows awaiting restoration after a failed backend call.
    /// Matching the scan's owner prevents stale IDs from preserving a new window.
    func isRaised(windowID: CGWindowID, ownerPID: pid_t) -> Bool {
        raised[windowID]?.ownerPID == ownerPID
    }

    func clearAll() {
        setRaised([:], level: 0)
    }

    private func restore(_ windowID: CGWindowID) {
        guard let backend, var record = raised[windowID] else { return }

        switch backend.windowState(windowID) {
        case .gone:
            raised.removeValue(forKey: windowID)
            return
        case let .present(ownerPID, level):
            guard ownerPID == record.ownerPID else {
                // A different owner confirms that the original window is gone.
                raised.removeValue(forKey: windowID)
                return
            }
            if level == record.originalLevel {
                raised.removeValue(forKey: windowID)
                return
            }
            guard record.restorationAttempts < maximumRestorationAttempts else { return }
            record.restorationAttempts += 1
            if backend.setLevel(windowID, record.originalLevel) {
                raised.removeValue(forKey: windowID)
                return
            }
        case .unavailable:
            guard record.restorationAttempts < maximumRestorationAttempts else { return }
            record.restorationAttempts += 1
        }
        raised[windowID] = record
    }

    private func scheduleRestorationRetryIfNeeded() {
        guard !retryScheduled else { return }
        let pending = raised.filter {
            requestedOwners[$0.key] != $0.value.ownerPID
                && $0.value.restorationAttempts < maximumRestorationAttempts
        }
        guard let attempt = pending.values.map(\.restorationAttempts).min() else { return }

        retryScheduled = true
        let delay = 0.25 * pow(2, Double(max(0, attempt - 1)))
        scheduleRetry(delay) { [weak self] in
            guard let self else { return }
            self.retryScheduled = false
            let windowIDs = self.raised.compactMap { windowID, record in
                self.requestedOwners[windowID] != record.ownerPID ? windowID : nil
            }
            for windowID in windowIDs { self.restore(windowID) }
            self.scheduleRestorationRetryIfNeeded()
        }
    }
}

private extension WindowRaiser.Backend {
    typealias MainConnectionID = @convention(c) () -> Int32
    typealias SetWindowLevel = @convention(c) (Int32, CGWindowID, Int32) -> Int32

    static let framework = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY
    )

    static func symbol<T>(_ names: [String], as type: T.Type) -> T? {
        guard let framework else { return nil }
        for name in names {
            if let symbol = dlsym(framework, name) {
                return unsafeBitCast(symbol, to: type)
            }
        }
        return nil
    }

    static func live() -> Self? {
        guard let mainConnectionID = symbol(
            ["SLSMainConnectionID", "CGSMainConnectionID", "_CGSDefaultConnection"],
            as: MainConnectionID.self
        ), let setWindowLevel = symbol(
            ["SLSSetWindowLevel", "CGSSetWindowLevel"],
            as: SetWindowLevel.self
        ) else { return nil }

        let connection = mainConnectionID()
        guard connection != 0 else { return nil }
        return Self(
            windowState: { windowID in
                guard let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
                        as? [[String: Any]] else { return .unavailable }
                guard let window = windows.first(where: {
                    ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
                }) else { return .gone }
                guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                      owner.int32Value > 0,
                      let level = window[kCGWindowLayer as String] as? NSNumber else {
                    return .unavailable
                }
                return .present(ownerPID: owner.int32Value, level: level.int32Value)
            },
            setLevel: { windowID, level in
                setWindowLevel(connection, windowID, level) == 0
            }
        )
    }
}
