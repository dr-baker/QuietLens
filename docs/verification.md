# Verification

## Automated checks

Run `bash scripts/check.sh` from the checkout.

The script runs eleven standalone checks against production components:

- `OverviewDockIdentityCheck` covers Dock replacement, launch and termination
  ordering, startup without a Dock, stale snapshots, and stop/start generations.
- `SettingsDeliveryCheck` covers committed Combine delivery, removing the final
  pin, exclusions, same-app highlighting, and coalesced settings changes.
- `OverlayTimerCancellationCheck` covers manual intent, pause cancellation,
  auto-disable replacement, and callbacks queued before cancellation.
- `InputMonitorLifecycleCheck` covers disabled shake monitors, sampling limits,
  peek cleanup, hotkey observer ownership, Carbon dispatch, and stale key events.
- `WindowRaiserCheck` covers original levels, successful and failed mutations,
  owner reuse, missing APIs, bounded restoration retries, and reselection.
- `WindowCornerCacheCheck` covers failure cooldowns, sample expiry, owner, size,
  and scale invalidation, stale captures, callback limits, and work bounds.
- `FocusWindowSelectionCheck` covers focused, pinned, same-app, coincident, and
  successfully raised windows.
- `CutoutGeometryCheck` covers overlap, duplicates, asymmetric corners, and
  windows crossing display edges.
- `OverlayFadeStateCheck` covers interrupted transitions and stale hide completions.
- `OverlayShaderCheck` covers animation phase retention, speed changes, Reduce
  Motion, and backing-layer replacement using unhosted Core Animation layers.
- `OverlayManagerLifecycleCheck` covers display reconciliation, mask-before-show
  ordering, missing overview presentation data, recovery, and logical hide gates.

Injected services and in-memory settings keep the checks from changing your
preferences, capturing windows, or mutating window levels. The manager check
uses synthetic display inventory and in-memory overlay windows. Standalone
checks compile with warnings treated as errors.

The script also builds the universal Release app and runs Xcode analysis.
These checks do not launch the app, restart Dock, or grant permissions. They do
not prove animation smoothness, cutout accuracy, or private-API behavior on a
particular macOS version.

## Live acceptance

Use an explicitly installed build. Record the commit, macOS version, display
layout, scaling, and relevant overlay settings. Test these behaviors:

1. Switch between apps and between windows of the same app using clicks and
   keyboard shortcuts. Check for stale cutouts, late reactions, and corner seams.
2. Move and resize the focused window. Repeat with multiple displays and a
   window crossing display boundaries.
3. Enable same-app highlighting, then move, create, close, or minimize another
   window without changing focus. Repeat with a pinned app. Check that pinning
   the focused app does not erase its cutout.
4. In Deep and Tinted modes, drag blur, tint, and opacity controls from end to
   end. Compare dragging with clicking at the same values.
5. Enter and leave Mission Control and App Exposé using the available trackpad,
   keyboard, and mouse paths. Select both the previous window and a different
   window. Check that the effect disappears during overview and that the
   returning mask follows the visible window without a late flash.
6. Repeat overview exits with Reduce Motion enabled, exclusions, pinned apps,
   and multiple displays. Check restoration of any raised window levels.
7. With permission to disrupt the desktop, restart Dock and repeat overview
   entry/exit. Confirm the detector follows the replacement process.
8. Use **Check for Updates**. With no fork release, expect the no-release message,
   rather than an upstream update suggestion.
9. Toggle the effect off and on before its fade ends. Check that an old hide
   completion cannot hide the newly enabled effect. Connect and disconnect a
   display while the effect is visible and while overview is active.
10. Pause the overlay, then explicitly disable it while it is already paused.
    Confirm it stays off after the pause expires. Change auto-disable duration
    while enabled and confirm the replaced deadline does not fire.
11. Disable shake during a modifier peek and confirm the effect returns. Check
    hotkeys after Accessibility access is revoked and granted again. Change an
    unrelated appearance setting during a shader animation and check its phase.

Use screen recordings when judging transition timing and corner matching.
Record a behavior as accepted only after observing it. A synthetic lifecycle
check does not establish successful recovery from an actual Dock restart.
