@main
struct OverlayFadeStateCheck {
    static func main() {
        var state = OverlayFadeState()
        let firstHide = state.begin(visible: false)
        precondition(state.canFinishHiding(generation: firstHide))
        _ = state.begin(visible: true)
        precondition(!state.canFinishHiding(generation: firstHide))
        precondition(state.isVisible)
        let secondHide = state.begin(visible: false)
        precondition(!state.canFinishHiding(generation: firstHide))
        precondition(state.canFinishHiding(generation: secondHide))
        _ = state.begin(visible: true)
        let thirdHide = state.begin(visible: false)
        precondition(!state.canFinishHiding(generation: secondHide))
        precondition(state.canFinishHiding(generation: thirdHide))
        print("Interrupted fade and stale hide completions: passed")
    }
}
