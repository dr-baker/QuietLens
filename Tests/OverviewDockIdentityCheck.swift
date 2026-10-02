import Foundation

@main
struct OverviewDockIdentityCheck {
    static func main() {
        var identity = OverviewDockIdentity()
        identity.start(pid: 101)
        let firstGeneration = identity.generation
        precondition(identity.accepts(pid: 101, generation: firstGeneration))

        precondition(identity.didTerminate(pid: 101))
        precondition(identity.pid == nil)
        precondition(!identity.accepts(pid: 101, generation: firstGeneration))

        precondition(identity.didLaunch(pid: 202))
        let secondGeneration = identity.generation
        precondition(identity.accepts(pid: 202, generation: secondGeneration))
        precondition(!identity.accepts(pid: 101, generation: firstGeneration))

        precondition(!identity.didTerminate(pid: 101))
        precondition(!identity.didLaunch(pid: 202))
        precondition(identity.generation == secondGeneration)

        var overlapping = OverviewDockIdentity()
        overlapping.start(pid: 404)
        let overlappingGeneration = overlapping.generation
        precondition(overlapping.didLaunch(pid: 505))
        precondition(!overlapping.didTerminate(pid: 404))
        precondition(overlapping.pid == 505)
        precondition(!overlapping.accepts(pid: 404, generation: overlappingGeneration))

        var initiallyMissing = OverviewDockIdentity()
        initiallyMissing.start(pid: nil)
        precondition(initiallyMissing.didLaunch(pid: 606))
        precondition(initiallyMissing.accepts(pid: 606, generation: initiallyMissing.generation))

        identity.stop()
        precondition(!identity.accepts(pid: 202, generation: secondGeneration))
        identity.start(pid: 303)
        precondition(identity.accepts(pid: 303, generation: identity.generation))
        precondition(!identity.accepts(pid: 202, generation: secondGeneration))
        print("Dock PID replacement, stale results, event ordering, and stop/start: passed")
    }
}
