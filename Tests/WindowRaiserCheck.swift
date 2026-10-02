import Foundation
import CoreGraphics

@MainActor
private final class FakeWindowBackend {
    struct Write: Equatable {
        let windowID: CGWindowID
        let level: Int32
    }

    var states: [CGWindowID: WindowRaiser.WindowState] = [:]
    var results: [Bool] = []
    var writes: [Write] = []

    var backend: WindowRaiser.Backend {
        WindowRaiser.Backend(
            windowState: { [self] in states[$0] ?? .gone },
            setLevel: { [self] windowID, level in
                writes.append(Write(windowID: windowID, level: level))
                let success = results.isEmpty ? true : results.removeFirst()
                guard success, case let .present(ownerPID, _) = states[windowID] else { return false }
                states[windowID] = .present(ownerPID: ownerPID, level: level)
                return true
            }
        )
    }

    func level(_ windowID: CGWindowID) -> Int32? {
        guard case let .present(_, level) = states[windowID] else { return nil }
        return level
    }
}

@MainActor
private final class ManualRetries {
    var pending: [WindowRaiser.Retry] = []
    var delays: [TimeInterval] = []

    func schedule(_ delay: TimeInterval, retry: @escaping WindowRaiser.Retry) {
        delays.append(delay)
        pending.append(retry)
    }

    func runNext() {
        precondition(!pending.isEmpty)
        pending.removeFirst()()
    }
}

@main
struct WindowRaiserCheck {
    @MainActor
    static func main() {
        originalLevelAndOwnership()
        failedRaiseAndMissingBackend()
        restorationRetry()
        deadAndReusedWindows()
        retryBudgetAndReselection()
        print("Window levels, owner identity, backend failures, and bounded restoration retries: passed")
    }

    @MainActor
    private static func originalLevelAndOwnership() {
        let backend = FakeWindowBackend()
        backend.states[1] = .present(ownerPID: 101, level: 3)
        let raiser = WindowRaiser(backend: backend.backend)
        raiser.setRaised([1: 101], level: 1000)
        precondition(backend.level(1) == 1000)
        precondition(raiser.isRaised(windowID: 1, ownerPID: 101))
        precondition(!raiser.isRaised(windowID: 1, ownerPID: 202))

        raiser.setRaised([1: 101], level: 1001)
        raiser.clearAll()
        precondition(backend.level(1) == 3)
        precondition(!raiser.isRaised(windowID: 1, ownerPID: 101))
        precondition(backend.writes.map(\.level) == [1000, 1001, 3])
    }

    @MainActor
    private static func failedRaiseAndMissingBackend() {
        let backend = FakeWindowBackend()
        backend.states[1] = .present(ownerPID: 101, level: 0)
        backend.states[2] = .present(ownerPID: 202, level: 0)
        backend.results = [false]
        let raiser = WindowRaiser(backend: backend.backend)
        raiser.setRaised([1: 101, 0: 101, 2: 303], level: 1000)
        precondition(!raiser.isRaised(windowID: 1, ownerPID: 101))
        precondition(!raiser.isRaised(windowID: 2, ownerPID: 202))
        raiser.clearAll()
        precondition(backend.writes == [.init(windowID: 1, level: 1000)])

        let unavailable = WindowRaiser(backend: nil)
        unavailable.setRaised([1: 101], level: 1000)
        unavailable.clearAll()
        precondition(!unavailable.isRaised(windowID: 1, ownerPID: 101))
    }

    @MainActor
    private static func restorationRetry() {
        let backend = FakeWindowBackend()
        let retries = ManualRetries()
        backend.states[1] = .present(ownerPID: 101, level: 3)
        backend.results = [true, false, true]
        let raiser = WindowRaiser(backend: backend.backend, scheduleRetry: retries.schedule)
        raiser.setRaised([1: 101], level: 1000)
        raiser.clearAll()
        precondition(raiser.isRaised(windowID: 1, ownerPID: 101))
        precondition(backend.level(1) == 1000)
        raiser.clearAll()
        precondition(backend.writes.count == 2)
        precondition(retries.pending.count == 1)
        retries.runNext()
        precondition(backend.level(1) == 3)
        precondition(!raiser.isRaised(windowID: 1, ownerPID: 101))
        precondition(retries.pending.isEmpty)

        backend.states[2] = .present(ownerPID: 202, level: 8)
        raiser.setRaised([2: 202], level: 1000)
        backend.states[2] = .unavailable
        raiser.clearAll()
        precondition(raiser.isRaised(windowID: 2, ownerPID: 202))
        backend.states[2] = .present(ownerPID: 202, level: 1000)
        retries.runNext()
        precondition(backend.level(2) == 8)
        precondition(!raiser.isRaised(windowID: 2, ownerPID: 202))
    }

    @MainActor
    private static func deadAndReusedWindows() {
        let backend = FakeWindowBackend()
        backend.states[1] = .present(ownerPID: 101, level: 3)
        let raiser = WindowRaiser(backend: backend.backend)
        raiser.setRaised([1: 101], level: 1000)
        backend.states.removeValue(forKey: 1)
        raiser.clearAll()
        precondition(!raiser.isRaised(windowID: 1, ownerPID: 101))
        precondition(backend.writes.count == 1)

        backend.states[1] = .present(ownerPID: 101, level: 3)
        raiser.setRaised([1: 101], level: 1000)
        backend.states[1] = .present(ownerPID: 202, level: 7)
        raiser.clearAll()
        precondition(backend.level(1) == 7)
        precondition(!raiser.isRaised(windowID: 1, ownerPID: 101))
        precondition(backend.writes.count == 2)

        raiser.setRaised([1: 101], level: 1000)
        precondition(backend.writes.count == 2)
        raiser.setRaised([1: 202], level: 1000)
        precondition(raiser.isRaised(windowID: 1, ownerPID: 202))
        raiser.clearAll()
        precondition(backend.level(1) == 7)
    }

    @MainActor
    private static func retryBudgetAndReselection() {
        let backend = FakeWindowBackend()
        let retries = ManualRetries()
        backend.states[1] = .present(ownerPID: 101, level: 3)
        backend.results = [true, false, false, false]
        let raiser = WindowRaiser(
            backend: backend.backend,
            maximumRestorationAttempts: 3,
            scheduleRetry: retries.schedule
        )
        raiser.setRaised([1: 101], level: 1000)
        raiser.clearAll()
        while !retries.pending.isEmpty { retries.runNext() }
        precondition(retries.delays == [0.25, 0.5])
        precondition(backend.writes.count == 4)
        precondition(raiser.isRaised(windowID: 1, ownerPID: 101))
        raiser.clearAll()
        precondition(backend.writes.count == 4)
        precondition(retries.pending.isEmpty)

        // Reselecting the still-raised window starts a new restoration budget.
        raiser.setRaised([1: 101], level: 1000)
        raiser.clearAll()
        precondition(backend.level(1) == 3)
        precondition(!raiser.isRaised(windowID: 1, ownerPID: 101))

        backend.results = [true, false]
        raiser.setRaised([1: 101], level: 1000)
        raiser.clearAll()
        raiser.setRaised([1: 101], level: 1000)
        let writeCount = backend.writes.count
        retries.runNext()
        precondition(backend.writes.count == writeCount)
        precondition(raiser.isRaised(windowID: 1, ownerPID: 101))
        raiser.clearAll()
        precondition(backend.level(1) == 3)

        let exhaustedBackend = FakeWindowBackend()
        exhaustedBackend.states[2] = .present(ownerPID: 202, level: 7)
        exhaustedBackend.results = [true, false]
        let exhausted = WindowRaiser(backend: exhaustedBackend.backend, maximumRestorationAttempts: 1)
        exhausted.setRaised([2: 202], level: 1000)
        exhausted.clearAll()
        precondition(exhausted.isRaised(windowID: 2, ownerPID: 202))
        exhaustedBackend.states.removeValue(forKey: 2)
        exhausted.clearAll()
        precondition(!exhausted.isRaised(windowID: 2, ownerPID: 202))
        precondition(exhaustedBackend.writes.count == 2)
    }
}
