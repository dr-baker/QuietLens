import Combine
import Foundation

/// @Published emits before its storage changes. Defer effects that reread
/// settings until the assignment finishes, combining changes in the same turn.
@MainActor
final class CommittedSettingsEffect {
    private var subscription: AnyCancellable?
    private var pending = false
    private let perform: () -> Void

    init<Changes: Publisher>(changes: Changes, perform: @escaping () -> Void)
    where Changes.Failure == Never {
        self.perform = perform
        subscription = changes.sink { [weak self] _ in self?.schedule() }
    }

    private func schedule() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pending = false
            self.perform()
        }
    }
}
