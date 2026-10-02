# Verification

## Automated checks

Run `bash scripts/check.sh` from the checkout.

The standalone Dock identity check covers process replacement, duplicate launch
events, late termination of the previous Dock, startup without a Dock, stale
snapshot results, and detector stop/start generations. It compiles the identity
model from the production detector.

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

Use screen recordings when judging transition timing and corner matching.
Record a behavior as accepted only after observing it. A synthetic lifecycle
check does not establish successful recovery from an actual Dock restart.
