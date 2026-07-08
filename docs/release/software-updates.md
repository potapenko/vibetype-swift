# Software Update And Installation Release Checklist

HoldType uses Sparkle 2 for native macOS updates. GitHub Releases should host
the signed app archive or disk image, and the appcast URL configured in the app
bundle should point at the generated Sparkle appcast.

The canonical public install artifact is a notarized disk image:

```text
HoldType-<version>.dmg
```

The same GitHub Release DMG is used by direct-download users and the Homebrew
Cask. Sparkle appcasts must point at final GitHub Release assets, not temporary
CI upload URLs.

## Required Secrets

The GitHub Actions workflow expects these repository secrets:

- `APPLE_TEAM_ID`
- `DEVELOPER_ID_CERTIFICATE_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- `SPARKLE_EDDSA_PRIVATE_KEY`
- `HOLDTYPE_UPDATE_FEED_URL`
- `HOLDTYPE_UPDATE_PUBLIC_ED_KEY`

Required Homebrew tap automation secrets for public release:

- `HOMEBREW_TAP_TOKEN`

Optional official Homebrew Cask bump automation secrets:

- `HOMEBREW_GITHUB_API_TOKEN`

Required Homebrew tap automation variables for public release:

- `HOMEBREW_TAP_REPOSITORY`, for example `holdtype/homebrew-tap`
- `HOMEBREW_EXPECTED_TAP`, for example `holdtype/tap`
- `HOMEBREW_MINIMUM_MACOS`, for example `>= :tahoe`

Optional official Homebrew Cask bump automation variables:

- `HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED`, set to `true` only after the first
  `holdtype` cask is accepted into `Homebrew/homebrew-cask`
- `HOMEBREW_OFFICIAL_CASK_FORK_ORG`, optional GitHub owner or organization for
  `brew bump-cask-pr --fork-org`

`HOMEBREW_MINIMUM_MACOS` must be a Homebrew macOS comparison expression such as
`>= :tahoe`, because the value is rendered into `depends_on macos:`.

The app bundle reads these build settings from
`Config/HoldTypeSigning.xcconfig` or an untracked
`Config/HoldTypeSigning.local.xcconfig`:

```xcconfig
HOLDTYPE_UPDATE_FEED_URL = https://example.com/holdtype/appcast.xml
HOLDTYPE_UPDATE_PUBLIC_ED_KEY = YOUR_SPARKLE_EDDSA_PUBLIC_KEY
```

Debug builds may leave both values blank. In that state the updater UI remains
visible, but update checks are disabled and Settings marks updates as
unconfigured.

## Release Contract

- Tags use `v<version>`, for example `v1.0.0`.
- `MARKETING_VERSION` matches `<version>` without the leading `v`.
- `CURRENT_PROJECT_VERSION` is the build number used for Sparkle version
  comparison.
- The release artifact name is `HoldType-<version>.dmg`.
- The disk image contains `HoldType.app` and an Applications shortcut, and the
  app can be copied out of the mounted DMG with its bundle/signature intact.
- `release-manifest.json` must describe `kind: public-release`, the version,
  build, tag, notarization/public-release booleans, and matching DMG/ZIP
  SHA-256 values.
- Sparkle appcast generation must read the release DMG filename from
  `release-manifest.json`, not from a wildcard match in the release directory.
- A `scripts/release/build_release.sh --skip-notarization` artifact must be
  treated as verification-only. Its manifest is marked
  `kind: notarization-skipped-release`, `notarized: false`, and
  `public_release: false`.
- Public `release-manifest.json` and `SHA256SUMS.txt` entries must use release
  artifact filenames, not absolute CI runner paths.
- Production release builds must use Developer ID Application signing, hardened
  runtime, notarization, and stapled notarization tickets.
- The project-owned Homebrew tap is the first supported Homebrew channel.
  Acceptance into the central Homebrew Cask repository is a later distribution
  milestone, not a blocker for the first public release.

## Manual Release Flow

1. Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for the release.
2. Build and archive the macOS app with Developer ID signing and hardened
   runtime enabled.
3. Export the archive as a Developer ID app.
4. Validate the app bundle with `codesign` and `spctl`.
5. Notarize the app archive and staple the app.
6. Create the DMG with `HoldType.app` and an Applications shortcut.
7. Notarize and staple the DMG.
8. Create or update a GitHub Release with the notarized DMG.
9. Run Sparkle `generate_appcast` against the release artifact directory using
   the EdDSA private key.
10. Publish the generated appcast at the URL used by
   `HOLDTYPE_UPDATE_FEED_URL`.
11. Update the Homebrew cask SHA-256 in the project-owned tap.
12. Test from an older signed build with `Check for Updates...` and verify that
   Sparkle offers the new version, installs it, and relaunches without the
   normal quit confirmation.

## CI Direction

The CI release job should make the manual flow reproducible:

- resolve SwiftPM dependencies before archive;
- fail if the update feed URL or public key is missing for release builds;
- verify that the exported app bundle embeds the expected Sparkle feed URL and
  public EdDSA key;
- validate code signing before upload;
- verify that the DMG contains `HoldType.app` plus an Applications shortcut;
- verify that the DMG copy/install path preserves a usable signed app bundle;
- run notarization with bounded waits;
- fetch the existing appcast before generation; a 404 is allowed for the first
  release, but HTTP/server/network failures must stop the workflow so older
  Sparkle items are not lost accidentally;
- generate the appcast after notarization so the published item points at the
  final distributable;
- verify that Sparkle appcast metadata resolves to the same release DMG, DMG
  length, build number, and marketing version before publishing;
- verify that the Homebrew cask resolves to the same release DMG and SHA-256
  before publishing;
- prune unexpected assets from an existing GitHub Release before upload so
  stale preview/notary/debug artifacts cannot remain attached to the public
  release;
- upload release assets and appcast through GitHub APIs.
- when updating an existing GitHub Release, force it out of draft/prerelease
  state before the published-release verification gate;
- deploy the appcast and verify the published GitHub Release is not a draft or
  prerelease, has the expected uploaded non-empty assets, and matches the Pages
  appcast before treating the release workflow as successful.
- prepare an official Homebrew Cask submission bundle after the public release
  is verified, using the configured `HOMEBREW_MINIMUM_MACOS` value.
- update the Homebrew tap through a pull request after the release asset is
  live and its SHA-256 is known.
- open an official `Homebrew/homebrew-cask` bump PR through `brew bump-cask-pr`
  after the first upstream cask has been accepted and
  `HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED` is set to `true`.
- wrap GitHub Release publication, tap clone/push, and pull-request operations
  in explicit timeouts so external services cannot hang the release job
  indefinitely.

The tracked workflow is `.github/workflows/release.yml`. It runs on `v*` tags
and uses `macos-26` runners so the project can build with the current Xcode 26
toolchain.

The tracked scripts are:

- `scripts/release/preflight.py`
- `scripts/release/bump_official_homebrew_cask_pr.sh`
- `scripts/release/build_release.sh`
- `scripts/release/build_preview_dmg.sh`
- `scripts/release/create_official_homebrew_cask_pr.sh`
- `scripts/release/fetch_existing_appcast.py`
- `scripts/release/generate_appcast.sh`
- `scripts/release/open_official_homebrew_cask_pr_from_bundle.sh`
- `scripts/release/prepare_official_homebrew_cask.sh`
- `scripts/release/prune_github_release_assets.py`
- `scripts/release/verify_dmg_layout.sh`
- `scripts/release/verify_release.sh`
- `scripts/release/render_homebrew_cask.sh`
- `scripts/release/update_homebrew_tap.sh`
- `scripts/release/validate_release_inputs.py`
- `scripts/release/verify_app_update_settings.py`
- `scripts/release/verify_dmg_install.sh`
- `scripts/release/verify_install_channels.py`
- `scripts/release/verify_github_release_setup.py`
- `scripts/release/verify_homebrew_cask.py`
- `scripts/release/verify_homebrew_tap_release.py`
- `scripts/release/verify_published_release.py`
- `scripts/release/verify_release_manifest.py`
- `scripts/release/verify_release_notes.py`
- `scripts/release/verify_release_workflow.py`
- `scripts/release/with_timeout.py`
- `scripts/release/write_homebrew_cask_submission.py`
- `scripts/release/write_release_notes.sh`

Run the preflight locally before creating a release tag:

```sh
scripts/release/preflight.py
```

Preflight also runs `scripts/release/verify_release_workflow.py` to confirm the
GitHub Actions release workflow still wires the required build, notarization,
appcast, published-release, and Homebrew tap steps in order.

Validate the exact first release inputs before creating or manually dispatching
the workflow:

```sh
scripts/release/validate_release_inputs.py \
  --version 1.0.0 \
  --build 1 \
  --tag v1.0.0 \
  --release-dir dist/release/v1.0.0 \
  --download-url-prefix https://github.com/<app-owner>/holdtype-swift/releases/download/v1.0.0/
```

The CI release job runs the stricter secret-aware form:

```sh
scripts/release/preflight.py --require-secrets --require-homebrew-tap --json
```

For public release automation, `HOMEBREW_TAP_REPOSITORY`,
`HOMEBREW_EXPECTED_TAP`, `HOMEBREW_TAP_TOKEN`, and `HOMEBREW_MINIMUM_MACOS`
are required. Preflight fails if any of them is missing or malformed,
including a tap repository name that does not use Homebrew's `homebrew-`
prefix convention or a repository that maps to the wrong public tap prefix.
The release workflow cannot silently publish only GitHub/Sparkle artifacts
while skipping or misrouting the Homebrew tap PR.

Use `docs/release/first-release-runbook.md` for the one-time setup sequence:
Apple signing material, Sparkle keys, GitHub Pages, and the project-owned
Homebrew tap.

After configuring GitHub secrets and Pages, verify the repository setup before
creating the first release tag:

```sh
GITHUB_TOKEN=<token-with-actions-secrets-variables-and-pages-read-access> \
scripts/release/verify_github_release_setup.py \
  --repository holdtype/holdtype-swift \
  --appcast-url https://holdtype.github.io/holdtype-swift/appcast.xml \
  --expected-homebrew-tap holdtype/tap \
  --require-homebrew-tap \
  --require-homebrew-minimum-macos
```

After the initial cask is merged into `Homebrew/homebrew-cask`, verify the
short install channel before advertising it or enabling automated official
bump PRs:

```sh
GITHUB_TOKEN=<token-with-actions-secrets-variables-and-pages-read-access> \
scripts/release/verify_github_release_setup.py \
  --repository holdtype/holdtype-swift \
  --appcast-url https://holdtype.github.io/holdtype-swift/appcast.xml \
  --expected-homebrew-tap holdtype/tap \
  --require-homebrew-tap \
  --require-homebrew-minimum-macos \
  --require-official-homebrew-cask
```

After appcast generation, verify channel metadata before publishing:

```sh
scripts/release/verify_install_channels.py \
  --release-dir dist/release/v1.0.0 \
  --repository holdtype/holdtype-swift
```

This gate requires a `public-release` manifest with `public_release: true` and
`notarized: true`, validates both DMG and ZIP checksums, then verifies that the
Sparkle appcast points at the same released DMG with matching
`sparkle:version`, `sparkle:shortVersionString`, and DMG length. It also checks
that the rendered Homebrew cask points at the same released DMG and SHA-256.

The release and preview builders verify their manifests automatically. To
check a generated release manifest directly:

```sh
scripts/release/verify_release_manifest.py \
  --manifest dist/release/v1.0.0/release-manifest.json \
  --artifact-root dist/release/v1.0.0 \
  --expect-kind public-release \
  --expect-public-release true \
  --expect-notarized true \
  --require-relative-artifact-paths
```

After the GitHub Release and Pages deployment are live, verify the published
state. This requires the GitHub Release to be non-draft, non-prerelease, and
backed by the expected public assets with `uploaded` state and non-zero size.
When `--release-notes-file` is passed, this also verifies that the shared
GitHub/Sparkle release notes have the expected `# HoldType <version>` heading,
a non-empty body, and no placeholder text:

```sh
scripts/release/verify_published_release.py \
  --repository holdtype/holdtype-swift \
  --version 1.0.0 \
  --appcast-url https://holdtype.github.io/holdtype-swift/appcast.xml \
  --release-notes-file /path/to/release-notes.md \
  --download-dmg \
  --verify-downloaded-dmg-install
```

Add `--download-dmg` when you want the verifier to download the public DMG and
compare its SHA-256 against the published manifest and checksum file. Add
`--verify-downloaded-dmg-install` to also mount that downloaded DMG and verify
the standard drag-to-Applications copy path. The verifier also rejects
published manifests that are marked as local previews or non-notarized
artifacts.

## Local Preview DMG

Use the preview builder to validate the Release build, Sparkle plist keys, DMG
layout, DMG copy/install path, ZIP, checksums, and preview manifest before
Developer ID signing and notarization are available:

```sh
scripts/release/build_preview_dmg.sh --version 1.0.0 --build 1
```

Preview artifacts are written under `dist/preview/`. Their manifest is marked
`kind: local-preview`, `notarized: false`, and `public_release: false`. They
must not be uploaded to GitHub Releases or used for Homebrew.

The full release builder also supports `--skip-notarization` for validating
archive/export packaging when App Store Connect notarization credentials are not
available. That output is not a public release: `release-manifest.json` is
marked `kind: notarization-skipped-release`, `notarized: false`, and
`public_release: false`, so install-channel verification rejects it.

## Homebrew Cask Direction

The first cask should live in a separate branded tap repository such as
`holdtype/homebrew-tap`:

```sh
brew install --cask holdtype/tap/holdtype
```

After the tap pull request is merged, verify the published tap cask before
advertising that command:

```sh
scripts/release/verify_homebrew_tap_release.py \
  --repository holdtype/holdtype-swift \
  --tap-repository holdtype/homebrew-tap \
  --expected-homebrew-tap holdtype/tap \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --minimum-macos ">= :tahoe"
```

Use the GitHub repository name for automation variables:
`HOMEBREW_TAP_REPOSITORY=holdtype/homebrew-tap`. Set
`HOMEBREW_EXPECTED_TAP=holdtype/tap` as the public tap guardrail. Homebrew
derives the public tap name `holdtype/tap` from that `homebrew-tap` repository
suffix.

For a fresh Homebrew install to work as:

```sh
brew install --cask holdtype
```

the cask must be accepted into the official `Homebrew/homebrew-cask` repository
with the token `holdtype`. A project-owned tap can support the short token only
after a user has already tapped it; it cannot make the unqualified command work
for new users by itself.

The cask should download `HoldType-<version>.dmg` from the matching GitHub
Release, install `HoldType.app`, include `auto_updates true`, and pin a concrete
SHA-256. Do not use `version :latest` or `sha256 :no_check` for production
releases unless a future distribution decision intentionally trades away
artifact reproducibility.

The rendered cask should also quit the running menu bar app during uninstall
and include a `zap` stanza for optional `brew uninstall --zap` cleanup of
HoldType-managed local state:

```text
~/Library/Caches/HoldType
~/Library/Preferences/app.holdtype.HoldType.plist
~/Library/Saved Application State/app.holdtype.HoldType.savedState
```

That cleanup is intentionally not part of ordinary Homebrew uninstall.

Use `scripts/release/update_homebrew_tap.sh` to update a cloned tap checkout.
The script renders and verifies `Casks/holdtype.rb` and can run
`brew audit --new --cask` when called with `--audit`; cloning, committing,
pushing, and pull-request creation stay in the caller. The release workflow
resolves the tap repository's default branch with the GitHub API and uses that
branch as the Homebrew tap pull-request base.

Use `scripts/release/prepare_official_homebrew_cask.sh` when preparing a pull
request for `Homebrew/homebrew-cask`. It writes the official cask candidate to
`Casks/h/holdtype.rb` in a local Homebrew Cask checkout or fork and verifies the
official cask layout before audit:

```sh
scripts/release/prepare_official_homebrew_cask.sh \
  --homebrew-cask-dir "$(brew --repository homebrew/cask)" \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --repository holdtype/holdtype-swift \
  --minimum-macos ">= :tahoe" \
  --audit
```

The official cask helpers require `--minimum-macos` or
`HOMEBREW_MINIMUM_MACOS`; use the same value that is configured for the release
workflow.

The release workflow also writes an Actions artifact named
`holdtype-official-homebrew-cask-<version>` using the configured
`HOMEBREW_MINIMUM_MACOS` value. That artifact contains:

- `Casks/h/holdtype.rb`, rendered for the official Homebrew Cask layout;
- `metadata.json`, with the release DMG URL, SHA-256, version, tag, and minimum
  macOS value;
- `SUBMISSION.md`, with the exact upstream PR command and Homebrew review
  checks.

To verify an already rendered cask without changing it:

```sh
scripts/release/verify_homebrew_cask.py \
  --cask-path "$(brew --repository homebrew/cask)/Casks/h/holdtype.rb" \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --repository holdtype/holdtype-swift \
  --minimum-macos ">= :tahoe" \
  --official-layout
```

Use `scripts/release/open_official_homebrew_cask_pr_from_bundle.sh` with the
downloaded official submission bundle when the public DMG is already live and
you deliberately want to create the upstream new-cask PR branch. It reads
`metadata.json`, runs `brew tap --force homebrew/cask` when no checkout path is
provided, resolves `brew --repository homebrew/cask`, and delegates to the
lower-level PR helper:

```sh
scripts/release/open_official_homebrew_cask_pr_from_bundle.sh \
  --bundle-dir /path/to/holdtype-official-homebrew-cask-1.0.0 \
  --audit \
  --style \
  --fork-repository <github-user>/homebrew-cask \
  --push \
  --open-pr
```

Use `scripts/release/create_official_homebrew_cask_pr.sh` directly only when
you intentionally want to pass the version, SHA-256, repository, and minimum
macOS values yourself. It prepares the same candidate, commits it with the
Homebrew-style `holdtype <version> (new cask)` subject, and only pushes or
opens a pull request when those flags are present:

```sh
scripts/release/create_official_homebrew_cask_pr.sh \
  --homebrew-cask-dir "$(brew --repository homebrew/cask)" \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --repository holdtype/holdtype-swift \
  --minimum-macos ">= :tahoe" \
  --audit \
  --style \
  --fork-repository <github-user>/homebrew-cask \
  --push \
  --open-pr
```

Keep this as an explicit release-operator step rather than an automatic part
of every GitHub Release run: Homebrew acceptance is an external review gate,
and opening repeated upstream PRs before the DMG is stable creates noise.

After the first cask is accepted, use
`scripts/release/bump_official_homebrew_cask_pr.sh` for later official cask
updates. It delegates to Homebrew's `brew bump-cask-pr` command with the
versioned GitHub Release DMG URL and pinned SHA-256. The script first runs
`brew tap --force homebrew/cask` with a bounded timeout so fresh CI runners have
the official cask tap as a local git checkout:

```sh
scripts/release/bump_official_homebrew_cask_pr.sh \
  --version 1.0.1 \
  --sha256 <sha256-of-HoldType-1.0.1.dmg> \
  --repository holdtype/holdtype-swift
```

The release workflow can run that bump automatically after acceptance. Configure
`HOMEBREW_GITHUB_API_TOKEN`, then set `HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED` to
`true`. Keep it unset or `false` until the initial upstream cask is merged,
because `brew bump-cask-pr` expects an existing official cask token. The GitHub
setup verifier checks for `Casks/h/holdtype.rb` in `Homebrew/homebrew-cask`
when official bump automation is enabled. Use the same verifier with
`--require-official-homebrew-cask` immediately after upstream acceptance to
prove `brew install --cask holdtype` is backed by the official cask before
turning that automation on.
That gate decodes `Homebrew/homebrew-cask`'s `Casks/h/holdtype.rb` and verifies
the cask token, GitHub Release DMG URL, app artifact, Sparkle-compatible
livecheck, uninstall/zap metadata, pinned numeric version, pinned SHA-256, and
absence of `version :latest`, `verified:`, or `sha256 :no_check`.

Before publishing the first cask, confirm the minimum macOS version. The
current Xcode project uses `MACOSX_DEPLOYMENT_TARGET = 26.5`; if that is not
the intended public minimum, update the project setting before release.

Submit to the official Homebrew Cask repository only after the public release
artifacts are live and stable. The submission should:

- use a public, versioned, notarized DMG URL;
- pass `brew audit --new --cask holdtype`;
- follow the Homebrew Cask token, stanza, and required-field conventions;
- satisfy Homebrew's Acceptable Casks policy, including the notability check.

## Verification Commands

The release scripts are intended to make the manual flow reproducible, but the
minimum release evidence remains:

```sh
scripts/release/verify_dmg_layout.sh --dmg HoldType-<version>.dmg
scripts/release/verify_dmg_install.sh --dmg HoldType-<version>.dmg
codesign --verify --deep --strict --verbose=2 HoldType.app
spctl --assess --type execute --verbose=4 HoldType.app
xcrun stapler validate HoldType.app
xcrun stapler validate HoldType-<version>.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 HoldType-<version>.dmg
shasum -a 256 HoldType-<version>.dmg
brew audit --cask holdtype
```

Reference docs:

- Sparkle programmatic setup:
  <https://sparkle-project.org/documentation/programmatic-setup/>
- Sparkle update settings UI:
  <https://sparkle-project.org/documentation/preferences-ui/>
- Sparkle customization and relaunch delegates:
  <https://sparkle-project.org/documentation/customization/>
- Sparkle publishing:
  <https://sparkle-project.org/documentation/publishing/>
- Homebrew Cask cookbook:
  <https://docs.brew.sh/Cask-Cookbook>
- Homebrew tap maintenance:
  <https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap>
- Homebrew Acceptable Casks:
  <https://docs.brew.sh/Acceptable-Casks>
- Homebrew pull request guide:
  <https://docs.brew.sh/How-To-Open-a-Homebrew-Pull-Request>
