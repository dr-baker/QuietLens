/// A canceled Core Animation completion must not hide a newer visible state.
struct OverlayFadeState {
    private(set) var isVisible = false
    private var generation = 0

    mutating func begin(visible: Bool) -> Int {
        generation += 1
        isVisible = visible
        return generation
    }

    func canFinishHiding(generation: Int) -> Bool {
        !isVisible && self.generation == generation
    }
}
