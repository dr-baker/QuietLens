# Development

## Build and check

Install Xcode, select its command-line tools, and install XcodeGen:

```bash
brew install xcodegen
bash scripts/check.sh
```

The check script runs the standalone Dock identity regression check, builds both
Apple silicon and Intel slices, and runs Xcode analysis. It builds without a
signing identity and does not install or launch the app.

For individual actions:

```bash
bash scripts/build.sh
bash scripts/build.sh analyze
```

The generated project comes from `project.yml`. Edit that file rather than
Xcode's generated build settings. Derived data stays under `.build/xcode`, and
the Release app is always at `.build/xcode/Build/Products/Release/Quiet Lens.app`
within the checkout.

CI runs the same checks on pushes to `main` and pull requests. Live interaction
checks are listed separately in [Verification](verification.md).

## Signing and installation

For a signed local build, use a team with a suitable certificate in your keychain:

```bash
QUIET_LENS_SIGNING_TEAM=YOUR_TEAM_ID bash scripts/build.sh
```

The default signing identity is `Developer ID Application`. Override it with
`QUIET_LENS_SIGNING_IDENTITY` when using another suitable identity. The project
does not store a personal team or certificate.

The stable build path avoids searching Xcode's changing DerivedData directories.
Accessibility authorization also depends on code identity: the build path alone
does not preserve a grant. Use a consistent signing identity, retain the bundle
identifier, and keep the installed app at a consistent location such as
`/Applications/Quiet Lens.app`. Unsigned or ad-hoc replacements can require
renewed authorization.

Replacing an installation is a separate, explicit step. Quit the running copy
before replacing it and run only one copy afterward. Upstream and fork builds
both use `app.quiet.QuietLens`, the same preferences, and the same URL scheme.
Do not reset settings or Accessibility permissions just to run build checks.

Accessibility is needed for focus tracking. Corner sampling uses a compositor
image; if macOS cannot supply it, the reader returns no measurement and the
overlay uses fallback corners. Do not treat a build as proof that sampling works
under every screen-capture permission state.

## Version and release packaging

`project.yml` is the version source for the bundle and About screen. To change
the version and increment the build number:

```bash
bash scripts/bump-version.sh 1.0.9
```

An optional second argument sets the build number explicitly. This helper
updates the project and regenerates it. It leaves `Casks/quietlens.rb` unchanged:
that inherited cask targets upstream, not this fork.

After updating the changelog and completing verification:

```bash
bash scripts/release.sh 1.0.9
```

The release helper requires the version to match the project. It creates a
universal archive and ZIP in a new `build/release-VERSION.*` directory, then prints
the checksum and an explicit publishing command for `dr-baker/QuietLens`.
It never overwrites a previous package, publishes, or notarizes.

Without signing configuration, archives are ad-hoc signed. The same
`QUIET_LENS_SIGNING_TEAM` and `QUIET_LENS_SIGNING_IDENTITY` variables enable
certificate signing. Signing alone does not establish notarization; arrange
and verify notarization before advertising a release as notarized. Prepare
release-specific notes in `RELEASE_NOTES.md` before executing the publishing
command; do not use the entire historical changelog as release notes.

## Git workflow

`origin` is the maintained fork; `upstream` is Quiet Apps' repository. Keep
published upstream PR branches intact.

Use plain changelog-style commit subjects. Separate independent fixes. Develop
multi-commit changes on feature branches and merge with `--no-ff` so first-parent
history shows the feature or fix. Keep generated files and experiments out of
commits.
