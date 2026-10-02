# Changelog

All notable changes to Quiet Lens are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased — maintained fork

### Fixed

- Tint remains visible with blur, and blur strength has a useful range in Deep
  and Tinted modes.
- Appearance sliders respond continuously while dragging.
- Focus tracking avoids redundant window scans and ignores queued events from
  the previous app.
- Pinned and same-app cutouts refresh when additional windows change; the focused
  pinned window is included only once.
- Overview detection handles Mission Control, App Exposé, and Dock replacement.
- Overview exits track WindowServer presentation frames while restoring the
  effect. Window corner sampling runs asynchronously with cached measurements.
- Interrupted hide completions cannot hide a newly enabled overlay. Display
  changes preserve existing overlay windows and show new ones after masking.
- Missing overview presentation data clears stale cutouts and hides the effect
  until a valid frame returns. Logical show requests respect this gate.
- Overlapping cutouts remain clear. Windows crossing displays retain their
  original corner geometry at the display boundary.
- Window levels restore to their recorded values. Failed restores retain their
  records through bounded retries, and stale owner IDs cannot mutate new windows.
- Exhausted window restorations can recover on a new selection or explicit clear
  after a transient backend outage. Periodic cutout refreshes cannot restart
  exhausted retry batches.
- Raised same-app and pinned windows remain eligible for cutouts on later scans.
- Exclusions, pins, and same-app highlighting apply after settings assignment.
- Explicit enable or disable requests cancel pauses, including an already-off
  disable. Replaced timer callbacks cannot override newer state.
- Disabled shake detection removes its event monitors and ends active peeks.
  Hotkey stop/start keeps one observer and ignores queued events from an older run.
- Unrelated appearance changes preserve shader animation phase. Reduce Motion
  changes apply without another settings edit.

### Added

- Stable build output, optional environment-based signing, universal build and
  analysis checks, and Dock identity regression checks in CI.
- Fork goals, development guidance, and a live verification checklist.
- Regression checks for settings delivery, timer cancellation, input monitor
  ownership, window restoration, corner caching, selection, masks, and transitions.

### Changed

- About links and manual update checks point to Daniel Baker's fork.
- Update checks report when the fork has no published release.
- Release packages use separate output directories. Version bumps leave the
  inherited upstream Homebrew cask unchanged.
- Window-level APIs load optionally. Corner samples expire, use nominal point
  resolution, and invalidate when owner, size, or display scale changes.

Earlier entries below describe upstream releases.

## [1.0.8] — 2026-06-17

**Build 8** · App icon refresh.

### Changed
- **App icon** updated to match the Quiet Apps icon standard for macOS 26 Tahoe — correct squircle shape, transparent outer padding, and proper canvas sizing so the icon appears correctly in the Dock and Launchpad.

---

## [1.0.7] — 2026-06-11

**Build 7** · Stability, performance, and accessibility overhaul — one crash fix, event-driven input tracking, working auto-disable/auto-enable/update-check, global settings search.

### Added
- **Auto-disable after** (Rules → Behavior) is now functional — the overlay turns itself off 5 min / 10 min / 30 min / 1 hour after being enabled.
- **Auto-enable on focus** (General → Startup) is now functional — the overlay re-enables when you switch windows; turning it off manually pauses the behavior until you turn the overlay back on.
- **Check for Updates** (General → Updates) is now functional — queries the latest GitHub release on demand and links to the release page when a newer version exists. No background phoning home.
- **iCloud Settings Sync toggle** is now wired to the existing sync engine (active on builds signed with the iCloud entitlement). Flipping it on mid-session now works.
- **Menu bar context menu**: new *Pause for 5 Minutes* item, *Mode* submenu (Deep / Ambient / Tinted), and *Pin / Unpin Current App* item.
- **Global settings search** — the ⌘K search field now searches across **all** tabs, matches every word you type independently, and clears with ⎋.
- **Standard key equivalents in Settings** — ⌘C/⌘V/⌘X/⌘A now work in the search field, ⌘W closes the window, ⌘M minimizes (LSUIElement apps need an explicit main menu for these).

### Fixed
- **Crash**: enabling *Blur menu bar while focused* set `NSApplication.PresentationOptions.autoHideMenuBar` without the required `.autoHideDock`, which AppKit rejects with `NSInvalidArgumentException`.
- **Overlay flicker during text selection** — the overlay used to hide on *any* left-drag. It now hides only while a window is actually being moved or resized (detected via AX window-moved/resized events while the mouse button is down), so selecting text no longer blinks the overlay.
- **Stale menu bar icon after `quietlens://enable|disable`** — URL automation now goes through the same state path as the menu and hotkeys, so icon, menu-bar auto-hide, and polling state stay in sync.
- **Hardcoded "version 1.0.3"** in General → Updates replaced with the real bundle version.
- **iCloud sync engine** could permanently latch "off" if the toggle was enabled after launch.
- **Settings → reload()** missed `onboardingDismissed`, so that key never applied from a cloud pull.

### Performance
- **Shake detection is now event-driven** (mouse-move monitors) instead of a 60 Hz always-on timer — zero CPU while the pointer is idle, sampling capped at ~125 Hz while moving.
- **Focused-window polling now runs only while the overlay is enabled.** The 0.5 s fallback poll (one AX round-trip + full CGWindowList scan per tick) previously ran forever, even with the overlay off.
- **iCloud pushes debounced to 2 s** — previously every 60 ms settings tick (i.e. every slider pixel) triggered a `NSUbiquitousKeyValueStore.synchronize()`.
- **Film-grain texture generation moved off the main thread** and switched from 16M Swift RNG calls to `arc4random_buf` plane fills — enabling grain no longer hangs the UI.
- Timer tolerances added across the app so macOS can coalesce wakeups.

### Accessibility
- System **Reduce Motion** now disables the breathing/drift/pulse overlay animations and the Settings live-preview animations.
- VoiceOver: settings rows read as single labeled elements; switches expose On/Off values; sliders are adjustable with VO gestures and have proper labels; segmented controls and color swatches expose names and selection state.
- Menu bar icon exposes a live accessibility label and tooltip ("Quiet Lens — overlay on / off / off for this app").

---

## [1.0.4] — 2026-05-15

**Build 5** · Brand visuals aligned to the **Quiet Apps** design system.

### Added
- **New app icon** — violet `#8B5CF6` → `#5B36B8` gradient background with a focused-window-stack glyph (one bright window on top of two dimmed windows, traffic-light dots on the focused one). Color now matches the in-app accent.
- **About → "An app by Quiet Apps"** subtitle under the app name.
- **About → Credits** now reads "Part of the Quiet Apps family… Follows the Quiet Apps brand system."
- **Version is now read from `Bundle.main`** at runtime — About screen always shows the real `CFBundleShortVersionString (CFBundleVersion)` instead of a hardcoded string.
- **`scripts/bump-version.sh VERSION [BUILD]`** — single command bumps `project.yml` + `Casks/quietlens.rb` and regenerates the Xcode project.

### Changed
- `Info.plist` now uses `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` substitution, so the only source of truth for version is `project.yml`. Bumping it propagates automatically to the built `.app`, the About screen, and the release zip name.
- Settings UI: unchanged (intentional — Liquid Glass v1 stays as-is).

### Migration
- No user action required. App preferences and pinned-apps survive the version bump.

---

## [1.0.3] — 2026-05-15

**Build 4** · Rebrand — FocusLens is now **Quiet Lens**, the first app under the new **Quiet** company umbrella.

### Changed
- **App name**: FocusLens → **Quiet Lens** (display name everywhere, status item title, settings sidebar, About card, Welcome screen, menu bar context menu).
- **Bundle identifier**: `com.parththummar.FocusLens` → `app.quiet.QuietLens`.
- **URL scheme**: `focuslens://` → `quietlens://` (`quietlens://toggle`, `enable`, `disable`, `settings`).
- **Repository**: `parththummar/FocusLens` → `quietapps/QuietLens`.
- **Homebrew tap**: `parththummar/homebrew-focuslens` → `quietapps/homebrew-quietlens`.
- **Cask name**: `focuslens` → `quietlens`.
- **Swift symbols**: `FocusLensSettings` → `QuietLensSettings`, `FocusLensApp` → `QuietLensApp`, `Notification.Name.focusLensShortcutChanged` → `.quietLensShortcutChanged`.
- **Xcode project + target**: `FocusLens.xcodeproj` / `FocusLens` target → `QuietLens.xcodeproj` / `QuietLens` target.
- **LICENSE** copyright holder updated to **Quiet**.
- **Tinted mode** now visually distinct from Deep — uses light `.hudWindow` blur + `multiplyBlendMode` compositing on the tint layer, so the user's chosen color casts onto the background (camera-filter feel) instead of looking like a dimmer Deep.

### Migration
- **Existing FocusLens users must re-grant Accessibility** because macOS treats the renamed bundle as a different app. After upgrading: open System Settings → Privacy & Security → Accessibility, remove FocusLens (now stale), add Quiet Lens from `/Applications`, toggle it on.
- **UserDefaults keys carry over automatically** — keys live in `UserDefaults.standard` with generic names (`blurRadius`, `tintColorHex`, etc.) and survive the bundle-ID rename. Your sliders, tints, exclude list and pinned apps stay configured.
- **Old Homebrew users**: uninstall the old cask first, then install the new tap:
  ```
  brew uninstall --cask focuslens
  brew untap parththummar/focuslens
  brew tap quietapps/quietlens
  brew install --cask quietlens
  ```

---

## [1.0.2] — 2026-05-15

**Build 3** · Liquid Glass redesign, live preview, settings search, third overlay mode, stronger real-world blur.

### Added
- **Liquid Glass design system** — settings UI rebuilt around the macOS 26-inspired Liquid Glass spec from the bundled design handoff. Five-layer material hierarchy (wallpaper → chrome → panel → control → overlay), `.ultraThinMaterial` backdrops with low-opacity tints that let the wallpaper bleed through, specular top-edge highlight strokes instead of drop shadows. New token sheet `DesignSystem.swift` + primitive kit `GlassComponents.swift` (`GlassPanel`, `SettingsRow`, `GlassSwitch`, `GlassSlider`, `GlassSegmented`, `GlassPicker`, `IconTile`, `Callout`, `PageHeader`, `SectionLabel`, `Kbd`, `GhostButton`, `PrimaryButton`, `DangerCircleButton`, `ColorSwatch`).
- **Decorative wallpaper background** with two soft accent orbs (purple top-left, pink bottom-right) that refract through the glass panels.
- **Live preview canvas** on the Appearance tab — 200 px scene with a pastel diagonal wallpaper + four faux apps (Mail, Terminal mono, Notes, Messages) + a focused white "Safari" window on top. Reacts in real time to **blur**, **opacity**, **tint**, **gradient + angle**, **grain**, **grayscale**, **edge glow + halo intensity**, **shader mode + speed**. The background apps blur with the radius slider so you can see exactly what the real overlay will do.
- **Shader animations** in the preview — Breathing (opacity 1.0 ↔ 0.75 over 3s), Pulse (scale 1.0 ↔ 1.02 over 1.4s), Drift (xy translation over 7s), Static (no motion). All scale to the speed slider.
- **Settings search** in the sidebar (⌘K to focus) — filters visible cards by keyword across every screen.
- **Keyboard navigation** — ⌘1–⌘5 switch tabs (General / Appearance / Gestures / Rules / About).
- **Third overlay mode: Tinted** — solid color wash with light blur, sitting between Deep and Ambient. Mode picker is a three-tile selector with status-dot accents (blue / purple / pink) and a description per tile.
- **"Pin current window" global shortcut** — fourth hotkey ID alongside Toggle / Settings / Exclude. Toggles the frontmost app's bundle ID in the pinned list.
- **Color Scheme override** in General (System / Light / Dark) — forces the Quiet Lens UI to a specific scheme regardless of macOS preference.
- **Show indicator dot** toggle — when off, the menu bar icon reads as a generic hollow ring even when the overlay is active (low-key mode).
- Welcome / Onboarding screen rebuilt — 96 px glass icon tile, accent radial glow, status pill, primary + ghost button pair, numbered-chip troubleshooting panel.
- **Coming-soon badges** on every UI element that's wired in the UI but not yet driving real behavior — Auto-enable on focus, iCloud Settings Sync, Check for Updates, Cursor halo, Focus on hover, Auto-disable after. Each is visually dimmed and non-interactive with a small "COMING SOON" accent pill next to the title.

### Changed
- **Settings window**: 920×640 default size, `.fullSizeContentView` with transparent titlebar (titlebar text hidden), full-bleed wallpaper underneath. ⌘W closes Settings.
- **Window level**: settings + onboarding windows sit at `.normal` level by default. When key, they auto-raise to `screenSaverWindow + 1` so dropdown menus and pickers appear above the overlay; when you switch to another app the window auto-drops back to `.normal` so it doesn't pin itself above everything.
- **Sliders** are now built from scratch on a custom `DragGesture` over the visible 4 px track + 18 px white thumb + accent fill + accent glow. Click-to-position works, drag works, hit area covers the full row. `isMovableByWindowBackground` is now off so window-drag doesn't intercept slider gestures.
- **Sensitivity** is now a 5-segment level bar (Very Low → Very High) with capsules that fill left-to-right with accent + glow as the level rises.
- **Sidebar**: 30 px brand icon + "Quiet Lens" label + version-uppercase caption, accent-tinted active item with glass background + edge-top highlight, ⌘1–⌘5 hints per row, persistent search field with `⌘K` chip at the bottom.
- **Color picker**: now a 15-swatch grid (rainbow custom picker + brights: Purple/Cyan/Magenta/Orange/Yellow/Green/Blue + darks: Indigo/Navy/Forest/Crimson/Slate/Charcoal + neutrals White/Black). Adaptive grid wraps on narrow widths. Selected swatch shows a 1.5 px solid ring offset 4 px outside the swatch.
- **"Menu Icon click action"** (renamed from "Left-click action") and **"Color Scheme"** are now segmented (radio-style) controls so they don't need to open a popover.
- **Real overlay blur strength** boosted — `NSVisualEffectView.alphaValue` no longer modulated against radius (which was making the blur invisible at low/mid radii). Material tiers now scale across the full 0–50 range: `.hudWindow` → `.underWindowBackground` → `.fullScreenUI` → `.menu` (heaviest). Tint layer continues to handle the opacity slider.
- **About card** redesigned with a 120 px glass icon tile, version pill (green dot · `Version 1.0.2`), tagline, links card (Website / License MIT / Report issue), credits card.

### Technical
- New files: `DesignSystem.swift`, `GlassComponents.swift`, `LivePreview.swift`, `GeneralScreen.swift`, `AppearanceScreen.swift`, `GestureScreen.swift`, `RulesScreen.swift`, `AboutScreen.swift`.
- Removed: `AppearanceSettings.swift`, `RulesSettings.swift` (replaced by Screen-prefixed equivalents). `GestureSettings.swift` slimmed to host the `ShortcutRecorder` static helpers + `KeyCaptureView` used by the new `ShortcutRow`.
- `QuietLensSettings` adds `autoEnableOnFocus`, `showIndicatorDot`, `colorSchemePref`, `cursorHalo`, `focusOnHover`, `autoDisableAfter`, `pinShortcutKey`/`pinShortcutMods`. All seven mirror through `iCloudSync` along with the existing keys.
- `HotkeyManager` adds a fourth hotkey ID (pin current window) and routes it via `AppDelegate.togglePinCurrent()`.
- `OverlayMode` extended with `.tinted` — `BlurOverlayView` now respects three modes (deep / ambient / tinted) with mode-specific tint blend modes (`.multiply` for tinted).
- Menu bar icon respects `showIndicatorDot` — falls back to the off-state ring when the dot is disabled even while overlay is enabled.
- `AppDelegate` adopts `NSWindowDelegate`; `windowDidBecomeKey` / `windowDidResignKey` toggle settings + onboarding window level between `.normal` and `screenSaverWindow + 1`.
- Keyboard event monitor (`NSEvent.addLocalMonitorForEvents`) bound for ⌘1–⌘5 and ⌘K so navigation works regardless of focus inside the SwiftUI hierarchy.
- Welcome window resized to 620×760 to host the new layout.

---

## [1.0.1] — 2026-05-14

**Build 2** · Pinned windows, iCloud sync, edge glow, custom backdrop.

### Added
- **Pinned Apps** — designate apps that always stay clear, even when not focused. Pin a terminal, music player, or reference window via Settings → Rules → Pinned Apps (file picker or running-app menu). Pinned windows are raised above the overlay alongside the active window.
- **iCloud Settings Sync** — opt-in toggle in Settings → General. Mirrors overlay configuration across all your Macs via `NSUbiquitousKeyValueStore`. Includes blur, tint, gradients, grain, shake config, shortcuts, excluded + pinned apps, edge glow, backdrop. Pulls on launch + external change, pushes on every local change. Requires iCloud Drive enabled and (eventually) an Apple Developer entitlement for true cross-device sync.
- **Edge Glow** — soft colored halo around the focused window, like macOS Stage Manager. Toggle + radius slider (2–30) in Settings → Appearance → Active Window Glow. Color follows your tint setting.
- **Custom Backdrop** — replace the blur with a user-chosen image or your current macOS desktop wallpaper. Three modes in Settings → Appearance → Backdrop:
  - **Blur** (default) — original `NSVisualEffectView` material
  - **Image** — pick any image file; rendered behind the tint and grain layers
  - **Wallpaper** — auto-syncs with the current macOS desktop wallpaper of the screen the overlay is on

### Changed
- Settings model: added `pinnedBundleIDs`, `iCloudSyncEnabled`, `edgeGlowEnabled`, `edgeGlowRadius`, `backdropMode`, `backdropImagePath` properties with `UserDefaults` persistence
- `QuietLensSettings.reload()` added — re-reads every key from `UserDefaults` and republishes to subscribers. Used by iCloud sync to refresh when remote changes land.

### Technical
- New file `Core/iCloudSync.swift` — KVS bridge with bidirectional sync, equality-checked to avoid infinite ping-pong
- Backdrop renders in a dedicated `CALayer` below tint, with caching keyed off `backdropMode + path` so the layer only reloads when needed
- Edge glow drawn as a second `CAShapeLayer` (sibling to cutout mask) with stroke + shadow, animated alongside cutout transitions

---

## [1.0.0] — 2026-05-14

**Build 1** · First public release.

### Added

#### Core
- Native macOS menu bar agent (no Dock icon)
- Per-screen active-window detection — every connected display tracks its own focused window
- AX-based focus tracking with `CGWindowList` z-order fallback
- Smooth animated cutout transitions between focused windows
- Multi-display support with hot-swap monitor handling
- Drag-and-drop awareness — overlay fades during a drag operation

#### Visual modes
- **Deep** mode — full-screen frosted-glass dim, heavy tint coverage
- **Ambient** mode — subtle vertical-fade gradient backdrop
- Real Gaussian blur via `NSVisualEffectView` with continuous 0–50 radius mapping
- Opacity slider 10–100%
- Soft-light film grain with high-frequency 2048×2048 noise source
- Grayscale background filter (Core Image `CIColorControls`)
- Animated shader modes: Static, Breathing (opacity), Drift (xy translation), Pulse (scale)
- Configurable fade duration (50–1000 ms)

#### Tint system
- 9 Apple system color swatches + rainbow custom-color picker
- **As System** mode — overlay tint follows macOS accent color live
- Optional gradient tint with custom second color + 0–360° angle
- Hex color input/output round-trip

#### Gestures
- 2D cursor shake detection (any direction — horizontal, vertical, diagonal, circular)
- 5-tick sensitivity slider (Very Low → Very High)
- Shake-to-peek with configurable modifier key (⇧ / ⌥ / ⌘ / none)
- 60 Hz polling implementation (no Input Monitoring permission required)

#### Shortcuts (global)
- Toggle overlay
- Open settings
- Exclude current app
- Carbon `RegisterEventHotKey` based — works system-wide

#### Rules
- Excluded apps list — overlay disables automatically when an excluded app is focused
- Add apps via file picker or from running-apps menu
- "Highlight all windows of same app" — keeps every window of the active app clear
- "Hide Dock" toggle — overlay excludes Dock area when off; hides Dock entirely when on
- "Hide Menu Bar" toggle — same behavior for the menu bar strip

#### UI
- Control Center–inspired settings window with sidebar navigation
- Material-backed tile cards (CCCard, CCRow, SliderRow components)
- Onboarding tile on first run with dismissible tips
- 4-state menu bar icon (off / deep / ambient / excluded-current)
- Right-click menu bar context menu with current-app indicator

#### Automation
- URL scheme `quietlens://`
  - `quietlens://toggle`
  - `quietlens://enable`
  - `quietlens://disable`
  - `quietlens://settings`
- AppleScript-driveable via `open` command

#### System integration
- `SMAppService` Launch at Login
- Accessibility permission onboarding with live polling (auto-resume after grant)
- Stable across rebuilds with signed Developer ID builds

### Technical
- macOS 14.0 deployment target
- Swift 5.9, SwiftUI for settings, AppKit for overlay windows
- No external dependencies — Apple frameworks only
- XcodeGen-based project generation (`project.yml`)
- MIT licensed

### Known limitations
- Module-cache–based Accessibility permission resets require remove + re-add after unsigned rebuilds
- True variable Gaussian blur radius would need a private `CABackdropLayer` — `NSVisualEffectView` material steps used instead
- Sparkle auto-updater not yet wired up

---

[Unreleased]: https://github.com/quietapps/QuietLens/compare/1.0.4...HEAD
[1.0.4]: https://github.com/quietapps/QuietLens/releases/tag/1.0.4
[1.0.3]: https://github.com/quietapps/QuietLens/releases/tag/1.0.3
[1.0.2]: https://github.com/parththummar/FocusLens/releases/tag/1.0.2
[1.0.1]: https://github.com/parththummar/FocusLens/releases/tag/1.0.1
[1.0.0]: https://github.com/parththummar/FocusLens/releases/tag/1.0.0
