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
        exhaustionThenExplicitRecovery()
        freshSelectionAndPassiveBounds()
        passiveClearDoesNotRearmOtherWindows()
        recoveryWithQueuedRetryAndReusedOwner()
        print("Window levels, owner identity, bounded restoration retries, and fresh-event recovery: passed")
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
    private static func exhaustionThenExplicitRecovery() {
        let backend = FakeWindowBackend()
        let retries = ManualRetries()
        backend.states[1] = .present(ownerPID: 101, level: 3)
        let raiser = WindowRaiser(backend: backend.backend, scheduleRetry: retries.schedule)
        raiser.setRaised([1: 101], level: 1000)
        backend.states[1] = .unavailable
        raiser.clearAll()
        while !retries.pending.isEmpty { retries.runNext() }
        precondition(retries.delays == [0.25, 0.5, 1])
        precondition(raiser.isRaised(windowID: 1, ownerPID: 101))
        backend.states[1] = .present(ownerPID: 101, level: 1000)
        for _ in 0..<100 { raiser.clearAll(retryExhausted: false) }
        precondition(backend.writes.count == 1 && retries.pending.isEmpty)
        raiser.clearAll()
        precondition(backend.level(1) == 3, "A fresh clear must recover after an exhausted transient outage")
        precondition(!raiser.isRaised(windowID: 1, ownerPID: 101))
        precondition(backend.writes.map(\.level) == [1000, 3])
        precondition(retries.pending.isEmpty)
    }

    @MainActor
    private static func freshSelectionAndPassiveBounds() {
        let backend = FakeWindowBackend()
        let retries = ManualRetries()
        backend.states[1] = .present(ownerPID: 101, level: 3)
        backend.results = [true, false, false, false, false]
        let raiser = WindowRaiser(backend: backend.backend, scheduleRetry: retries.schedule)
        raiser.setRaised([1: 101], level: 1000)
        raiser.clearAll()
        while !retries.pending.isEmpty { retries.runNext() }
        precondition(backend.writes.map(\.level) == [1000, 3, 3, 3, 3])
        precondition(retries.delays == [0.25, 0.5, 1])

        // Invalid input and unchanged refreshes must not manufacture fresh intent.
        for _ in 0..<100 { raiser.setRaised([0: 101, 99: 0], level: 1000) }
        precondition(backend.writes.count == 5 && retries.pending.isEmpty)

        // A fresh clear starts a new batch, which still stops at four attempts.
        backend.results = [false, false, false, false]
        raiser.clearAll()
        while !retries.pending.isEmpty { retries.runNext() }
        precondition(backend.writes.count == 9)
        precondition(retries.delays == [0.25, 0.5, 1, 0.25, 0.5, 1])
        for _ in 0..<100 { raiser.clearAll(retryExhausted: false) }
        precondition(backend.writes.count == 9 && retries.pending.isEmpty)

        // A different focus selection also retries the retained, unfocused window.
        backend.states[2] = .present(ownerPID: 202, level: 8)
        raiser.setRaised([2: 202], level: 1000)
        precondition(backend.level(1) == 3 && backend.level(2) == 1000)
        precondition(!raiser.isRaised(windowID: 1, ownerPID: 101))
        raiser.clearAll()
        precondition(backend.level(2) == 8 && retries.pending.isEmpty)
    }

    @MainActor
    private static func passiveClearDoesNotRearmOtherWindows() {
        let backend = FakeWindowBackend()
        let retries = ManualRetries()
        backend.states[1] = .present(ownerPID: 101, level: 3)
        backend.states[2] = .present(ownerPID: 202, level: 8)
        let raiser = WindowRaiser(backend: backend.backend, maximumRestorationAttempts: 1,
                                  scheduleRetry: retries.schedule)
        raiser.setRaised([1: 101], level: 1000)
        raiser.setRaised([1: 101, 2: 202], level: 1000)
        backend.results = [false]
        raiser.setRaised([2: 202], level: 1000)
        precondition(raiser.isRaised(windowID: 1, ownerPID: 101))
        let failedWrites = backend.writes.filter { $0.windowID == 1 }
        raiser.clearAll(retryExhausted: false)
        precondition(backend.level(2) == 8)
        precondition(backend.level(1) == 1000, "Passive clear must not rearm an exhausted different window")
        precondition(backend.writes.filter { $0.windowID == 1 } == failedWrites)
        precondition(retries.pending.isEmpty)
        raiser.clearAll()
        precondition(backend.level(1) == 3)
    }

    @MainActor
    private static func recoveryWithQueuedRetryAndReusedOwner() {
        let backend = FakeWindowBackend()
        let retries = ManualRetries()
        backend.states[1] = .present(ownerPID: 101, level: 3)
        backend.states[2] = .present(ownerPID: 202, level: 8)
        backend.results = [true, false]
        let raiser = WindowRaiser(backend: backend.backend, maximumRestorationAttempts: 3,
                                  scheduleRetry: retries.schedule)
        raiser.setRaised([1: 101], level: 1000)
        raiser.clearAll()

        // Keep one pending chain alive while another record exhausts its budget.
        backend.states[1] = .unavailable
        raiser.setRaised([2: 202], level: 1000)
        retries.runNext()
        backend.states[2] = .unavailable
        raiser.clearAll(retryExhausted: false)
        retries.runNext()
        precondition(retries.pending.count == 1)
        backend.states[1] = .present(ownerPID: 101, level: 1000)
        backend.results = [false]
        raiser.clearAll()
        precondition(retries.pending.count == 1, "Fresh events must reuse the scheduled chain")

        // Reuse of the other window's ID must not restore its old owner's level.
        backend.states[2] = .present(ownerPID: 303, level: 7)
        retries.runNext()
        precondition(backend.level(1) == 3 && backend.level(2) == 7)
        precondition(!raiser.isRaised(windowID: 1, ownerPID: 101))
        precondition(!raiser.isRaised(windowID: 2, ownerPID: 202))
        precondition(backend.writes.filter { $0.windowID == 2 }.map(\.level) == [1000])
        precondition(retries.pending.isEmpty)

        let reusedBackend = FakeWindowBackend()
        reusedBackend.states[3] = .present(ownerPID: 303, level: 7)
        reusedBackend.results = [true, false]
        let reused = WindowRaiser(backend: reusedBackend.backend, maximumRestorationAttempts: 1)
        reused.setRaised([3: 303], level: 1000)
        reused.clearAll()
        precondition(reused.isRaised(windowID: 3, ownerPID: 303))
        reusedBackend.states[3] = .present(ownerPID: 404, level: 9)
        reused.clearAll()
        precondition(reusedBackend.level(3) == 9 && reusedBackend.writes.count == 2)
        precondition(!reused.isRaised(windowID: 3, ownerPID: 303))
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
        raiser.clearAll(retryExhausted: false)
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
