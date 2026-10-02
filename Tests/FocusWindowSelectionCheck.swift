import CoreGraphics

@main
struct FocusWindowSelectionCheck {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let first = FocusWindowCandidate(windowID: 1, pid: 101, rect: CGRect(x: 20, y: 30, width: 200, height: 150))
        let second = FocusWindowCandidate(windowID: 2, pid: 101, rect: CGRect(x: 220, y: 30, width: 200, height: 150))
        let pinned = FocusWindowCandidate(windowID: 3, pid: 202, rect: CGRect(x: 50, y: 300, width: 200, height: 150))
        func select(_ entries: [FocusWindowCandidate], focus: FocusWindowCandidate? = first,
                    pins: Set<Int32> = [], sameApp: Bool = false) -> [FocusWindowCandidate] {
            FocusWindowSelection.select(entries: entries, screen: screen, focused: focus, frontPID: 101,
                                        pinnedPIDs: pins, highlightSameAppWindows: sameApp, ourPID: 999)
        }
        precondition(select([first, second], pins: [101]).filter { $0.windowID == 1 }.count == 1)
        precondition(select([pinned], pins: [202]).map(\.windowID) == [3, 1])
        precondition(select([first, second], sameApp: true).map(\.windowID) == [1, 2])
        let coincident = FocusWindowCandidate(windowID: 4, pid: 101, rect: first.rect)
        precondition(select([first, coincident], sameApp: true).count == 2)
        precondition(select([first], focus: coincident).map(\.windowID) == [4])
        let unknownID = FocusWindowCandidate(windowID: 0, pid: 101, rect: first.rect)
        precondition(select([first], focus: unknownID).map(\.windowID) == [1])

        precondition(FocusWindowSelection.includesWindow(layer: 0, isRaised: false))
        precondition(!FocusWindowSelection.includesWindow(layer: 1000, isRaised: false))
        precondition(FocusWindowSelection.includesWindow(layer: 1000, isRaised: true))
        let nextScan = [first, second].filter {
            FocusWindowSelection.includesWindow(layer: $0.windowID == 2 ? 1000 : 0, isRaised: $0.windowID == 2)
        }
        precondition(select(nextScan, sameApp: true).map(\.windowID) == [1, 2])
        print("Focused, pinned, same-app, and raised-window selection: passed")
    }
}
