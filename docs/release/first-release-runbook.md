# First Release Runbook

This runbook turns the tracked release automation into a real public release.
It assumes the release contract in `docs/release/software-updates.md`.

Do not commit certificates, API keys, Sparkle keys, or generated private key
files. Store them only in GitHub repository secrets or local untracked files.

## 1. Confirm Public Release Choices

Before creating the first public tag, decide:

- the final GitHub owner/repository URL;
- the appcast URL used by `HOLDTYPE_UPDATE_FEED_URL`;
- whether GitHub Pages is the appcast host;
- the first public minimum macOS version;
- whether the first artifact is Apple Silicon only or a universal build;
- the project-owned Homebrew tap repository, for example
  `holdtype/homebrew-tap`.

The current Xcode project reports `MACOSX_DEPLOYMENT_TARGET = 26.5`. If that
is not the intended public minimum, change the project setting before the first
release and update the Homebrew cask `depends_on macos:` value.

## 2. Prepare Apple Signing And Notarization

Required Apple-side material:

- Developer ID Application certificate exported as a password-protected `.p12`;
- Apple Team ID;
- App Store Connect API key with notarization access;
- API key ID;
- API issuer ID.

Convert the `.p12` certificate to a GitHub secret value:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Add these repository secrets:

```text
APPLE_TEAM_ID
DEVELOPER_ID_CERTIFICATE_BASE64
DEVELOPER_ID_CERTIFICATE_PASSWORD
APP_STORE_CONNECT_KEY_ID
APP_STORE_CONNECT_ISSUER_ID
APP_STORE_CONNECT_PRIVATE_KEY
```

`APP_STORE_CONNECT_PRIVATE_KEY` should contain the full `.p8` file contents.

## 3. Prepare Sparkle Signing

Generate or locate the Sparkle EdDSA key pair. The public key must be compiled
into production builds as `HOLDTYPE_UPDATE_PUBLIC_ED_KEY`; the private key is
used only by release automation to sign the appcast.

Add these repository secrets:

```text
SPARKLE_EDDSA_PRIVATE_KEY
HOLDTYPE_UPDATE_PUBLIC_ED_KEY
HOLDTYPE_UPDATE_FEED_URL
```

If GitHub Pages hosts the appcast, use a stable URL such as:

```text
https://<owner>.github.io/holdtype-swift/appcast.xml
```

## 4. Enable GitHub Pages

In the GitHub repository settings:

1. Open Pages settings.
2. Set the source to GitHub Actions.
3. Confirm Actions can create deployments.

The release workflow uploads only `appcast.xml` to Pages.

After secrets and Pages are configured, run the read-only setup verifier before
creating the first tag:

```sh
GITHUB_TOKEN=<token-with-actions-secrets-variables-and-pages-read-access> \
scripts/release/verify_github_release_setup.py \
  --repository holdtype/holdtype-swift \
  --appcast-url https://holdtype.github.io/holdtype-swift/appcast.xml \
  --expected-homebrew-tap holdtype/tap \
  --require-homebrew-tap \
  --require-homebrew-minimum-macos
```

## 5. Prepare The Homebrew Tap

Create the tap repository, for example:

```text
holdtype/homebrew-tap
```

Homebrew maps the public tap name `holdtype/tap` to the GitHub repository
`holdtype/homebrew-tap`. Configure `HOMEBREW_TAP_REPOSITORY` with the GitHub
repository name, not the shortened tap name.

The tap repository must be public and not archived before the release workflow
opens tap pull requests. The setup verifier checks this repository through the
GitHub API when `HOMEBREW_TAP_REPOSITORY` is configured.

Add an empty `Casks/` directory or let the release workflow create it in the
tap update branch. The release workflow resolves the tap repository's default
branch through the GitHub API and uses that branch as the pull-request base.

Add this repository variable to the app repository before the first public
release:

```text
name: HOMEBREW_TAP_REPOSITORY
value: holdtype/homebrew-tap
```

Add the expected public tap prefix as a separate guardrail. The release
preflight compares this value with the prefix derived from
`HOMEBREW_TAP_REPOSITORY`, so a personal `homebrew-tap` repository cannot
accidentally ship as the wrong public tap:

```text
name: HOMEBREW_EXPECTED_TAP
value: holdtype/tap
```

Create a GitHub token that can clone the tap, push a branch, and open a pull
request. Add this secret to the app repository before the first public release:

```text
HOMEBREW_TAP_TOKEN
```

Add this repository variable after the public minimum macOS version is
confirmed and before the first public release. The value must be a Homebrew
macOS comparison expression, for example `>= :tahoe`:

```text
name: HOMEBREW_MINIMUM_MACOS
value: >= :tahoe
```

Leave official Homebrew Cask bump automation disabled for the first release.
After the initial `holdtype` cask is accepted into `Homebrew/homebrew-cask`,
run the setup verifier with the official cask gate:

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

This verifier decodes the upstream `Casks/h/holdtype.rb` file and checks that
the short command is backed by the HoldType cask token, GitHub Release DMG URL,
`HoldType.app` artifact, pinned numeric version, pinned SHA-256, and no
`version :latest` or `sha256 :no_check` fallback.

Then add a `HOMEBREW_GITHUB_API_TOKEN` repository or environment secret and set
this repository variable:

```text
name: HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED
value: true
```

Optionally set `HOMEBREW_OFFICIAL_CASK_FORK_ORG` to the GitHub owner or
organization that should own the `brew bump-cask-pr` fork.

The first public Homebrew install command will be:

```sh
brew install --cask holdtype/tap/holdtype
```

The shorter command:

```sh
brew install --cask holdtype
```

becomes available to new users only after the cask is accepted into
`Homebrew/homebrew-cask` with the `holdtype` token. Treat that as a follow-up
distribution milestone after the GitHub Release DMG is public, versioned,
notarized, and stable.

After a release DMG exists, the tap cask can be updated manually with:

```sh
scripts/release/update_homebrew_tap.sh \
  --tap-dir /path/to/homebrew-tap \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --repository <app-owner>/holdtype-swift \
  --tap-repository holdtype/homebrew-tap \
  --audit
```

The script only updates and optionally audits `Casks/holdtype.rb`; it does not
commit, push, or create the tap pull request.

The rendered cask should quit `app.holdtype.HoldType` during Homebrew uninstall
and include optional zap cleanup for:

```text
~/Library/Caches/HoldType
~/Library/Preferences/app.holdtype.HoldType.plist
~/Library/Saved Application State/app.holdtype.HoldType.savedState
```

Zap cleanup is user-triggered with `brew uninstall --zap`; ordinary Homebrew
uninstall should leave these local support files alone.

When preparing the later official Homebrew Cask PR, render the candidate into a
local `Homebrew/homebrew-cask` checkout or fork. The helper verifies that the
candidate is written to the official `Casks/h/holdtype.rb` layout and that the
cask metadata points at the public GitHub Release DMG:

```sh
scripts/release/prepare_official_homebrew_cask.sh \
  --homebrew-cask-dir "$(brew --repository homebrew/cask)" \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --repository <app-owner>/holdtype-swift \
  --minimum-macos ">= :tahoe" \
  --audit
```

The official cask helpers require this minimum macOS value. Use the same
Homebrew comparison expression that you configured as `HOMEBREW_MINIMUM_MACOS`.

To inspect a rendered candidate directly without changing it:

```sh
scripts/release/verify_homebrew_cask.py \
  --cask-path "$(brew --repository homebrew/cask)/Casks/h/holdtype.rb" \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --repository <app-owner>/holdtype-swift \
  --minimum-macos ">= :tahoe" \
  --official-layout
```

To create the actual upstream PR branch after the public DMG is live and the
official cask submission is intentionally starting, prefer the uploaded
submission bundle wrapper. It reads `metadata.json`, prepares the local
`homebrew/cask` checkout with `brew tap --force homebrew/cask` when needed, and
then creates the PR branch from the verified release metadata:

```sh
scripts/release/open_official_homebrew_cask_pr_from_bundle.sh \
  --bundle-dir /path/to/holdtype-official-homebrew-cask-1.0.0 \
  --audit \
  --style \
  --fork-repository <github-user>/homebrew-cask \
  --push \
  --open-pr
```

Use the lower-level helper directly only when you intentionally want to pass
the version, SHA-256, repository, and minimum macOS values yourself:

```sh
scripts/release/create_official_homebrew_cask_pr.sh \
  --homebrew-cask-dir "$(brew --repository homebrew/cask)" \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --repository <app-owner>/holdtype-swift \
  --minimum-macos ">= :tahoe" \
  --audit \
  --style \
  --fork-repository <github-user>/homebrew-cask \
  --push \
  --open-pr
```

The script creates the local commit first. It only pushes or opens the
`Homebrew/homebrew-cask` pull request when `--push` and `--open-pr` are passed.

After the cask is accepted, later releases should use Homebrew's cask bump PR
flow instead of the new-cask helper:

```sh
scripts/release/bump_official_homebrew_cask_pr.sh \
  --version 1.0.1 \
  --sha256 <sha256-of-HoldType-1.0.1.dmg> \
  --repository <app-owner>/holdtype-swift
```

The bump helper prepares the official `homebrew/cask` tap locally with
`brew tap --force homebrew/cask` before calling `brew bump-cask-pr`, so it works
on fresh CI runners as well as developer machines.

The release workflow can run the same bump automatically when
`HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED=true` and `HOMEBREW_GITHUB_API_TOKEN` is
configured. Do not enable it before the first upstream cask is merged and
`verify_github_release_setup.py --require-official-homebrew-cask` proves that
`Homebrew/homebrew-cask` already contains `Casks/h/holdtype.rb`.

## 6. Local Preflight

Run the non-publishing preflight from the app repository:

```sh
scripts/release/preflight.py
```

This includes a release-workflow wiring check, so changes to
`.github/workflows/release.yml` should fail locally if a required build,
appcast, published-release, or Homebrew tap step is removed or moved out of
order.

Expected local warnings:

- release secrets are absent from the shell unless you intentionally exported
  them;
- Homebrew tap configuration and token are absent unless you intentionally exported
  `HOMEBREW_TAP_REPOSITORY`, `HOMEBREW_EXPECTED_TAP`, and
  `HOMEBREW_TAP_TOKEN`;
- `MACOSX_DEPLOYMENT_TARGET = 26.5` needs confirmation before public release.

No `fail` checks should remain.

The GitHub Actions release workflow runs the stricter form:

```sh
scripts/release/preflight.py --require-secrets --require-homebrew-tap --json
```

That means `HOMEBREW_TAP_REPOSITORY`, `HOMEBREW_EXPECTED_TAP`,
`HOMEBREW_TAP_TOKEN`, and `HOMEBREW_MINIMUM_MACOS` must be configured before a
public release run can publish, so Homebrew tap publication is not accidentally
skipped or pointed at the wrong public tap.

Validate the exact release inputs before creating the tag or using manual
workflow dispatch:

```sh
scripts/release/validate_release_inputs.py \
  --version 1.0.0 \
  --build 1 \
  --tag v1.0.0 \
  --release-dir dist/release/v1.0.0 \
  --download-url-prefix https://github.com/<app-owner>/holdtype-swift/releases/download/v1.0.0/
```

Optionally build a local preview DMG to validate packaging before release
secrets are configured:

```sh
scripts/release/build_preview_dmg.sh --version 1.0.0 --build 1
```

The preview DMG is not notarized and must not be published. It is useful only
for checking the Release build, Sparkle plist keys, DMG layout, DMG copy/install
path, ZIP, checksum, and preview manifest.

If you use `scripts/release/build_release.sh --skip-notarization` to validate
the archive/export path before notarization credentials are ready, treat that
output the same way: it is verification-only. Its `release-manifest.json` uses
`kind: notarization-skipped-release`, `notarized: false`, and
`public_release: false`, so it must not be uploaded to GitHub Releases, Sparkle,
or Homebrew.

## 7. Create The Release

Update the app version/build, then create and push a release tag:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The GitHub Actions release workflow should:

1. validate `version`, `build`, `tag`, release directory, and download URL
   inputs;
2. run tests;
3. import the Developer ID certificate;
4. build and export the Release archive;
5. verify that the exported app embeds the expected Sparkle feed URL and public
   EdDSA key;
6. notarize and staple the app and DMG;
7. generate checksums and verify `release-manifest.json`;
8. fetch the existing Sparkle appcast, treating 404 as first-release absence
   but stopping on server or network failures;
9. generate Sparkle `appcast.xml`;
10. verify signatures, stapled tickets, checksums, the DMG layout, and the DMG
   copy/install path;
11. verify that the appcast and Homebrew cask metadata point at the release DMG
   and SHA-256, and that the appcast build and marketing version match the
   release manifest;
12. prune unexpected assets from an existing GitHub Release so stale
    preview/notary/debug artifacts cannot remain public;
13. publish GitHub Release assets, forcing any existing release out of
    draft/prerelease state;
14. deploy `appcast.xml` to GitHub Pages;
15. verify the GitHub Release is not a draft or prerelease, has the expected
    uploaded non-empty assets, and matches the Pages appcast;
16. prepare and upload the official Homebrew Cask submission bundle using the
    configured `HOMEBREW_MINIMUM_MACOS` value;
17. render, verify, and audit the Homebrew tap cask;
18. open a Homebrew tap pull request.
19. open an official Homebrew Cask bump PR when the official cask has already
    been accepted and official bump automation is enabled.

The workflow wraps GitHub Release publication, tap clone/push, tap pull
request, and official cask bump commands in explicit timeouts. A hung external
service should fail the attempt instead of leaving the release job waiting
indefinitely.

## 8. Verify The Published Release

After the workflow passes, verify:

```sh
scripts/release/verify_published_release.py \
  --repository holdtype/holdtype-swift \
  --version 1.0.0 \
  --appcast-url https://holdtype.github.io/holdtype-swift/appcast.xml \
  --release-notes-file /path/to/release-notes.md \
  --download-dmg \
  --verify-downloaded-dmg-install
gh release view v1.0.0
gh release download v1.0.0 --pattern 'HoldType-1.0.0.dmg'
shasum -a 256 HoldType-1.0.0.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 HoldType-1.0.0.dmg
scripts/release/verify_dmg_install.sh --dmg HoldType-1.0.0.dmg
```

Open the DMG, drag `HoldType.app` into Applications, and launch it.

For Homebrew, merge the tap pull request, then run:

```sh
scripts/release/verify_homebrew_tap_release.py \
  --repository holdtype/holdtype-swift \
  --tap-repository holdtype/homebrew-tap \
  --expected-homebrew-tap holdtype/tap \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --minimum-macos ">= :tahoe"
brew install --cask holdtype/tap/holdtype
brew uninstall --cask holdtype
```

If the workflow uploaded `holdtype-official-homebrew-cask-1.0.0`, download the
artifact, inspect `SUBMISSION.md`, and use
`scripts/release/open_official_homebrew_cask_pr_from_bundle.sh` before opening
the upstream `Homebrew/homebrew-cask` PR. That bundle is evidence for the later
short-form install path:

```sh
brew install --cask holdtype
```

After the upstream PR is merged, run the setup verifier with
`--require-official-homebrew-cask` before using that short command in public
install instructions or enabling official cask bump automation.

For Sparkle, install an older signed build with a test appcast, then verify
that `Check for Updates...` offers the new version, downloads it, installs it,
and relaunches without the normal quit confirmation.
