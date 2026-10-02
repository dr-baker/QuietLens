# Fork goals

This fork is maintained for daily use by Daniel Baker. Its priority is the
window-to-window experience: the effect should follow focus promptly, preserve
the visible window shape, and return from Mission Control without a late mask
or overlay flash.

## Product goals

- React to focus changes without waiting for a full scan of every window or a
  corner capture. Extra work for pinned and same-app windows should remain
  conditional.
- Match the window's actual corner shape where sampling succeeds, including
  windows whose corners differ on macOS 26. Fall back when sampling is unavailable.
- Hide the effect during Mission Control and App Exposé. On exit, follow the
  selected window's presentation frame while bringing the effect back.
- Make blur, tint, and opacity controls useful across overlay modes, with
  continuous response while dragging.
- Preserve native menu bar operation, multiple displays, exclusions, pinned
  apps, and local settings.

## Engineering goals

Keep the app small and native. Prefer event-driven work, bounded caches, and
background sampling to additional work on every focus change. Keep conservative
fallbacks around private WindowServer APIs, whose availability and behavior can
change with macOS.

Treat a Dock process change as a lifecycle boundary. Discard queued snapshots
from the previous Dock or a stopped detector. Keep the overview polling cadence
unchanged until an alternative is measured and tested through real gestures.

Keep builds reproducible from a clean checkout. Personal signing settings belong
in the environment. Preserve the bundle identifier and avoid resetting
Accessibility grants or preferences as routine development steps.

Update checks remain user-initiated and target this fork. Do not add background
network activity or telemetry as part of these fixes. Any release needs its own
verification; an unsigned development build is not a notarized distribution.

## Current work

The fork includes the tint/blur and slider fixes, the reduced-query focus path,
overview exit tracking, asynchronous corner sampling, and Dock lifecycle
recovery. It also fences stale Accessibility events and keeps additional clear
windows refreshed when that feature is enabled.

The [verification checklist](verification.md) separates automated checks from
live behavior. Corner accuracy, transition timing, and responsiveness still need
acceptance on the affected apps and display setups. No numerical performance
claim follows from a successful build.

A Settings redesign, new focus gestures, and a replacement rendering engine
are outside the current cleanup.

## Upstream relationship

Keep the upstream history, attribution, and remote. Existing focused upstream
pull requests remain open; this fork can carry fixes independently while they
await review. Send useful changes upstream as focused contributions when
appropriate.

The decision to maintain this fork does not depend on declaring upstream
abandoned. Upstream releases remain upstream products; this fork's source,
issues, update checks, and eventual releases live at
[dr-baker/QuietLens](https://github.com/dr-baker/QuietLens).
