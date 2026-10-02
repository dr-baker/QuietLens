import Combine
import Foundation

@MainActor
private final class SettingsFixture: ObservableObject {
    @Published var excludedBundleIDs: [String] = []
    @Published var pinnedBundleIDs = ["app.pinned"]
    @Published var highlightSameAppWindows = false
}

@main
struct SettingsDeliveryCheck {
    @MainActor
    static func main() async {
        let settings = SettingsFixture()
        var excluded = false
        var extraCutouts = Set(settings.pinnedBundleIDs)
        var exclusionReads: [[String]] = []
        var layoutReads: [(pins: [String], highlight: Bool)] = []
        let effects = [
            CommittedSettingsEffect(
                changes: settings.$excludedBundleIDs.removeDuplicates().dropFirst(),
                perform: {
                    exclusionReads.append(settings.excludedBundleIDs)
                    excluded = settings.excludedBundleIDs.contains("app.focused")
                }
            ),
            CommittedSettingsEffect(
                changes: Publishers.CombineLatest(settings.$pinnedBundleIDs.removeDuplicates(),
                                                 settings.$highlightSameAppWindows.removeDuplicates()).dropFirst(),
                perform: {
                    layoutReads.append((settings.pinnedBundleIDs, settings.highlightSameAppWindows))
                    extraCutouts = Set(settings.pinnedBundleIDs)
                    if settings.highlightSameAppWindows { extraCutouts.insert("app.focused.other-window") }
                }
            )
        ]
        precondition(exclusionReads.isEmpty && layoutReads.isEmpty)

        settings.pinnedBundleIDs = []
        precondition(layoutReads.isEmpty)
        await nextMainQueueTurn()
        precondition(layoutReads.count == 1 && layoutReads[0].pins.isEmpty)
        precondition(extraCutouts.isEmpty, "Removing the final pin must clear its cutout")

        settings.highlightSameAppWindows = true
        await nextMainQueueTurn()
        precondition(extraCutouts == ["app.focused.other-window"])
        settings.highlightSameAppWindows = false
        await nextMainQueueTurn()
        precondition(layoutReads.last?.highlight == false && extraCutouts.isEmpty)

        settings.excludedBundleIDs = ["app.focused"]
        precondition(!excluded)
        await nextMainQueueTurn()
        precondition(excluded && exclusionReads.last == ["app.focused"])
        settings.excludedBundleIDs = []
        await nextMainQueueTurn()
        precondition(!excluded && exclusionReads.last == [])

        let layoutCount = layoutReads.count
        let exclusionCount = exclusionReads.count
        settings.pinnedBundleIDs = ["app.pinned"]
        settings.highlightSameAppWindows = true
        settings.pinnedBundleIDs = []
        settings.highlightSameAppWindows = false
        settings.excludedBundleIDs = ["app.focused"]
        settings.excludedBundleIDs = []
        await nextMainQueueTurn()
        precondition(layoutReads.count == layoutCount + 1)
        precondition(exclusionReads.count == exclusionCount + 1)
        precondition(extraCutouts.isEmpty && !excluded)

        settings.pinnedBundleIDs = []
        settings.highlightSameAppWindows = false
        settings.excludedBundleIDs = []
        await nextMainQueueTurn()
        precondition(layoutReads.count == layoutCount + 1 && exclusionReads.count == exclusionCount + 1)

        var abandonedCalls = 0
        var abandonedEffect: CommittedSettingsEffect? = CommittedSettingsEffect(
            changes: settings.$pinnedBundleIDs.dropFirst(), perform: { abandonedCalls += 1 }
        )
        settings.pinnedBundleIDs = ["app.pinned"]
        precondition(abandonedEffect != nil)
        abandonedEffect = nil
        await nextMainQueueTurn()
        precondition(abandonedCalls == 0)

        withExtendedLifetime(effects) {}
        print("Committed Combine settings, final pin removal, highlight disable, exclusion, and coalescing: passed")
    }

    private static func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
