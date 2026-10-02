import CoreGraphics

struct FocusWindowCandidate: Equatable {
    let windowID: CGWindowID
    let pid: Int32
    let rect: CGRect
}

enum FocusWindowSelection {
    static func includesWindow(layer: Int, isRaised: Bool) -> Bool {
        layer <= 0 || isRaised
    }

    static func select(
        entries: [FocusWindowCandidate],
        screen: CGRect,
        focused: FocusWindowCandidate?,
        frontPID: Int32,
        pinnedPIDs: Set<Int32>,
        highlightSameAppWindows: Bool,
        ourPID: Int32
    ) -> [FocusWindowCandidate] {
        let onScreen = entries.filter { $0.rect.intersects(screen) }
        var picked = onScreen.filter { pinnedPIDs.contains($0.pid) }
        var active: [FocusWindowCandidate] = []
        if highlightSameAppWindows {
            active = onScreen.filter { $0.pid == frontPID }
        }
        if let focused, focused.pid == frontPID, focused.rect.intersects(screen) {
            let exact = onScreen.first {
                $0.pid == focused.pid && focused.windowID != 0 && $0.windowID == focused.windowID
            }
            let frameMatch = focused.windowID == 0 ? onScreen.first {
                $0.pid == focused.pid && approximatelyEqual($0.rect, focused.rect)
            } : nil
            let matched = exact ?? frameMatch ?? focused
            appendUnique(matched, to: &active)
        }
        if active.isEmpty, let top = onScreen.first(where: { $0.pid == frontPID }) {
            active.append(top)
        }
        if active.isEmpty, let top = onScreen.first(where: { $0.pid != ourPID }) {
            active.append(top)
        }
        // Pinned windows supplement the focused selection. They must never
        // suppress an AX fallback just because the pinned list is nonempty.
        for entry in active { appendUnique(entry, to: &picked) }
        return picked
    }

    private static func appendUnique(_ entry: FocusWindowCandidate, to entries: inout [FocusWindowCandidate]) {
        let exists = entries.contains {
            if entry.windowID != 0, $0.windowID != 0 {
                return $0.windowID == entry.windowID && $0.pid == entry.pid
            }
            return $0.pid == entry.pid && approximatelyEqual($0.rect, entry.rect)
        }
        if !exists { entries.append(entry) }
    }

    private static func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 4 && abs(a.minY - b.minY) < 4
            && abs(a.width - b.width) < 4 && abs(a.height - b.height) < 4
    }
}
