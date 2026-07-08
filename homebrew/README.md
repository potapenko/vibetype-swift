# Homebrew Cask

HoldType's first Homebrew distribution path is a project-owned tap. Prefer a
branded repository such as `holdtype/homebrew-tap` so the fallback install path
does not depend on a personal GitHub namespace. The tap repository should
contain a rendered cask at:

```text
Casks/holdtype.rb
```

Configure release automation with the GitHub repository name, for example
`HOMEBREW_TAP_REPOSITORY=holdtype/homebrew-tap`. Homebrew derives the user-facing
tap name `holdtype/tap` from the `homebrew-tap` repository suffix.

Also configure `HOMEBREW_EXPECTED_TAP=holdtype/tap`. Release preflight compares
that public tap prefix with the prefix derived from `HOMEBREW_TAP_REPOSITORY`,
so a mistaken personal tap configuration fails before publishing.
The release workflow opens the tap pull request against the tap repository's
actual default branch, resolved through the GitHub API during the release run.

Render it from this repository after a GitHub Release DMG exists:

```sh
scripts/release/update_homebrew_tap.sh \
  --tap-dir /path/to/homebrew-tap \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --repository <app-owner>/holdtype-swift
```

Run a local audit when Homebrew is available:

```sh
scripts/release/update_homebrew_tap.sh \
  --tap-dir /path/to/homebrew-tap \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --repository <app-owner>/holdtype-swift \
  --tap-repository holdtype/homebrew-tap \
  --audit
```

After the tap PR is merged, verify the published cask on the tap default branch:

```sh
scripts/release/verify_homebrew_tap_release.py \
  --repository <app-owner>/holdtype-swift \
  --tap-repository holdtype/homebrew-tap \
  --expected-homebrew-tap holdtype/tap \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --minimum-macos ">= :tahoe"
```

Install command for users:

```sh
brew install --cask holdtype/tap/holdtype
```

The unqualified command:

```sh
brew install --cask holdtype
```

requires acceptance into the official `Homebrew/homebrew-cask` repository with
the `holdtype` token. A project-owned tap cannot make that command work for new
users unless they have already tapped the repository.

After upstream acceptance, verify that the official cask exists and points back
to this release repository before advertising the short install command or
enabling automated official bump PRs:

```sh
GITHUB_TOKEN=<token-with-actions-secrets-variables-and-pages-read-access> \
scripts/release/verify_github_release_setup.py \
  --repository <app-owner>/holdtype-swift \
  --expected-homebrew-tap holdtype/tap \
  --require-homebrew-tap \
  --require-homebrew-minimum-macos \
  --require-official-homebrew-cask
```

That verifier decodes the upstream `Casks/h/holdtype.rb` file and checks the
short install contract: `holdtype` token, GitHub Release DMG URL,
`HoldType.app`, livecheck, uninstall/zap metadata, pinned numeric version,
pinned SHA-256, and no `version :latest`, `verified:`, or `sha256 :no_check`.

Prepare the official cask candidate in a local Homebrew Cask checkout or fork:

```sh
scripts/release/prepare_official_homebrew_cask.sh \
  --homebrew-cask-dir "$(brew --repository homebrew/cask)" \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --repository <app-owner>/holdtype-swift \
  --minimum-macos ">= :tahoe" \
  --audit
```

`--minimum-macos` is required for the official candidate so the upstream cask
does not accidentally omit HoldType's supported macOS boundary.

After a public release workflow succeeds with `HOMEBREW_MINIMUM_MACOS`
configured, download the Actions artifact named
`holdtype-official-homebrew-cask-<version>`. It contains the same official
layout candidate at `Casks/h/holdtype.rb`, plus `metadata.json` and
`SUBMISSION.md` for the upstream PR review path.

Verify a rendered official candidate without modifying the checkout:

```sh
scripts/release/verify_homebrew_cask.py \
  --cask-path "$(brew --repository homebrew/cask)/Casks/h/holdtype.rb" \
  --version 1.0.0 \
  --sha256 <sha256-of-HoldType-1.0.0.dmg> \
  --repository <app-owner>/holdtype-swift \
  --minimum-macos ">= :tahoe" \
  --official-layout
```

When the public DMG is live and ready for upstream review, prefer creating the
official PR branch from that submission bundle:

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

The rendered cask quits `app.holdtype.HoldType` during Homebrew uninstall and
supports optional zap cleanup for HoldType's preferences, cache directory, and
saved app state. Zap cleanup only runs when the user explicitly passes
`brew uninstall --zap`.

After the cask is accepted, subsequent official updates can use Homebrew's bump
PR flow:

```sh
scripts/release/bump_official_homebrew_cask_pr.sh \
  --version 1.0.1 \
  --sha256 <sha256-of-HoldType-1.0.1.dmg> \
  --repository <app-owner>/holdtype-swift
```

The helper runs `brew tap --force homebrew/cask` before `brew bump-cask-pr` so
the official cask tap is present as a local git checkout.

The release workflow can open that bump PR automatically after the first
official cask is merged. Configure `HOMEBREW_GITHUB_API_TOKEN`, then set
`HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED=true`. Keep the variable unset or `false`
until `brew install --cask holdtype` already resolves from
`Homebrew/homebrew-cask`.

Before publishing the first cask, confirm the public minimum macOS version. The
template leaves the `depends_on macos:` stanza commented for manual drafts until
that product choice is final, but the release workflow requires
`HOMEBREW_MINIMUM_MACOS` before it opens a tap pull request.
