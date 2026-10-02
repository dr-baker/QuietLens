# Quiet Lens

Dim or blur the desktop around the window you're using.

This is [Daniel Baker's maintained fork](https://github.com/dr-baker/QuietLens) of
[Quiet Lens by Quiet Apps](https://github.com/quietapps/QuietLens), originally
created by Parth Thummar. It keeps the native macOS menu bar app and concentrates
on responsive window tracking, accurate cutouts, and Mission Control transitions.

The fork is in development. It has no published binary releases yet.
Upstream downloads and the upstream Homebrew tap do not include these changes.

## What it does

- Deep, Ambient, and Tinted overlay modes, with adjustable blur, opacity, and color.
- Accessibility-based focus tracking, with WindowServer fallbacks.
- Per-display overlays, pinned apps, and an option to keep same-app windows clear.
- Mission Control and App Exposé detection, with presentation-frame tracking
  while returning to a selected window.
- Menu bar controls, global shortcuts, shake-to-toggle, and URL automation.

This fork fixes tint/blur composition and slider dragging, reduces work on the
normal focus-change path, reads window corner shapes asynchronously, and handles
Dock restarts in overview detection. Build checks do not establish that every
animation or window shape looks correct; see the [verification checklist](docs/verification.md).

## Build from source

Use macOS 14 or later, a current Xcode installation with its command-line tools
selected, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/dr-baker/QuietLens.git
cd QuietLens
brew install xcodegen
bash scripts/check.sh
```

The checks compile the Dock lifecycle regression test, build a universal Release
app, and run Xcode analysis. The unsigned build lands at:

```text
.build/xcode/Build/Products/Release/Quiet Lens.app
```

For a build without analysis, run `bash scripts/build.sh`.
Neither command installs or launches the app. Read the
[development guide](docs/development.md) before replacing a working installation,
especially if you want to retain its Accessibility grant.

## Use

Launch Quiet Lens and grant Accessibility access when prompted. Click its menu
bar icon to toggle the effect; right-click it to open Settings or quit.
Finder is excluded by default. Change exclusions and pinned apps in Settings.

The fork retains the bundle identifier `app.quiet.QuietLens`, preferences, and
the `quietlens://toggle`, `enable`, `disable`, and `settings` URLs.
Run one copy at a time: upstream and fork builds share that identity.

## Development and contributions

Read the [fork goals](docs/fork-goals.md), [development guide](docs/development.md),
and [project charter](AGENTS.md). For a proposed feature, open an issue describing
the problem before starting a large change. Keep each pull request focused,
follow the existing Swift style, avoid new force unwraps, and run
`bash scripts/check.sh`.

Report visual issues with the macOS version, affected app, overlay mode, display
arrangement, and steps to reproduce. A screen recording is useful when timing
or corners are involved.

## Credits and license

Original app: [Quiet Apps / Parth Thummar](https://github.com/quietapps/QuietLens).
Original inspiration: [Monocle](https://iamdk.gumroad.com/l/monocle-elegant-macos-window-blur-focus).
Fork maintenance: Daniel Baker.

[MIT license](LICENSE). The original copyright notice is preserved.
