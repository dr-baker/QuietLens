# Quiet Lens

## What we're after

Maintain a small native macOS focus tool that follows the active window promptly,
keeps its shape clear, and gets out of the way during Mission Control and App
Exposé. This is Daniel Baker's development fork of Quiet Apps' Quiet Lens.
Keep the original attribution and MIT license.

## Where to go

- [Fork goals](docs/fork-goals.md): scope and upstream relationship.
- [Development guide](docs/development.md): builds, signing, and release packaging.
- [Verification](docs/verification.md): automated checks and live acceptance.
- `QuietLens/Core/`: focus tracking, overview detection, overlay coordination,
  WindowServer presentation, and corner sampling.
- `QuietLens/Overlay/`: overlay windows, rendering, and cutout masks.
- `QuietLens/App/AppDelegate.swift`: runtime ownership and settings application.
- `QuietLens/Models/Settings.swift` and `QuietLens/Views/`: persistence and settings UI.
- `project.yml`: XcodeGen source; the generated Xcode project is ignored.

## Ground rules

- Keep changes scoped to a real behavior or maintenance problem. Prefer clear
  ownership and meaningful simplification over compatibility shims.
- Use focused commits with plain changelog-style subjects. Build multi-commit
  features on branches and land them with `--no-ff` merges. Preserve upstream
  ancestry and published PR branch history; do not force-push it.
- Preserve the app's bundle identifier, settings, and existing window restoration
  behavior unless an explicit migration is part of the change.
- Do not commit personal signing identities, generated projects, builds, or
  local experiments. Signing is configured through the build environment.
- Keep blocking capture and broad window scans off the default focus path.
  Fence asynchronous results against stale window or process identity.
- Guard optional private APIs and retain usable fallback behavior. Avoid new
  force unwraps.
- Run `bash scripts/check.sh`. Report automated results separately from live
  visual acceptance. Installing a build, resetting settings or permissions,
  restarting Dock, or changing system gestures requires user direction.

## Vocabulary

- **Overview**: Mission Control or App Exposé, including its entry/exit animation.
- **Cutout**: the clear region in an overlay mask.
- **Presentation frame**: where WindowServer currently draws an animating window;
  its logical Accessibility frame can differ.
