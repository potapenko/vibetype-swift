# App Store Distribution

## Goal

Define HoldType's macOS distribution decision.

HoldType's current macOS product should ship through direct download, not the
Mac App Store. The direct path is feasible because it preserves the system-wide
voice input workflow while still using Apple's Developer ID and notarization
trust model.

## Scope

- current macOS distribution channel
- Mac App Store viability for the current product shape
- direct-download trust requirements
- competitor evidence used for the channel decision
- conditions for reopening App Store work

## Non-goals

- iPhone, iPad, or keyboard-extension distribution
- App Store Connect setup
- TestFlight upload automation
- in-app purchase design
- Store-specific reduced product behavior
- legal privacy-policy wording

## Product Decision

HoldType must not target the Mac App Store for the current macOS product.

The supported macOS release channel is direct distribution:

- Developer ID signed app bundle;
- Apple notarized DMG or ZIP release artifact;
- Sparkle updates for downloadable builds;
- optional Homebrew cask that installs the same notarized artifact;
- public download, privacy, support, and changelog pages.

## Rationale

Apple requires Mac App Store apps to be sandboxed and updated through the Mac
App Store. HoldType's current value depends on working with the active app:
automatic insertion, Paste Last Result, and nearby text context are
Accessibility-gated system-wide behaviors.

The current permissions spec states that the macOS MVP app target must not use
App Sandbox while those active-app behaviors depend on Accessibility-gated
control of other apps. Microphone capture and OpenAI networking are not the
main blockers; broad interaction with arbitrary active apps is.

Comparable products support the same conclusion:

- Fixkey's Mac product is distributed through direct download, not an official
  Mac App Store listing found during the 2026-07-09 review.
- Wispr Flow has an iPhone App Store app, but its Mac product is installed by
  downloading a DMG from its website and moving the app to Applications.

This makes direct distribution a normal channel for this class of macOS
utility, not a second-best workaround.

## User-visible Behavior

- Users should be directed to the official HoldType download page for macOS.
- The download page should explain that the app is signed with an Apple
  Developer ID and notarized by Apple.
- The product should not promise Mac App Store availability.
- Settings should describe Sparkle updates only for downloadable builds.
- User-facing copy may say that HoldType is distributed directly because its
  core Mac workflow depends on system-wide input and text insertion features.
- If users ask for the Mac App Store, support copy should explain that the
  current Mac App Store sandbox model does not fit the full HoldType workflow.

## Invariants

- The direct build must remain signed and notarized before public release.
- The direct build may use Sparkle for updates.
- No Store build, Store entitlements, Store CI workflow, TestFlight upload, or
  App Store metadata should be created while this spec is unchanged.
- HoldType must not remove or weaken automatic insertion, Paste Last Result,
  or nearby text context solely to create a Store-compatible edition without a
  separate product decision.
- If a future Store edition is created, it must not use Sparkle or any external
  updater.

## Edge Cases And Failure Policy

- If Gatekeeper blocks a direct install, the install guide should tell the user
  how to confirm the signed and notarized app through normal macOS UI.
- If a third-party or clone appears in the Mac App Store under a similar name,
  HoldType support and website copy should identify the official download
  source.
- If Apple changes the Mac App Store sandbox model, App Store work may be
  reopened through a new spec update.
- If a business decision intentionally accepts a weaker Store edition, that
  edition must get its own product behavior spec before implementation.

## Route / State / Data Implications

- The production macOS bundle identity remains the direct-download app
  identity unless a future spec introduces a separate Store edition.
- Sparkle configuration belongs only to downloadable builds.
- App Store Connect identifiers, API keys, metadata, and review assets are not
  required for current HoldType macOS distribution.
- Public privacy and support pages must cover microphone audio, transcript
  text, OpenAI requests, local Keychain storage, Accessibility, Input
  Monitoring, local history, and diagnostics.

## Verification Mapping

- Release verification should validate Developer ID signing, notarization,
  stapling, Gatekeeper assessment, DMG layout, and Sparkle appcast metadata.
- Website/download QA should verify that install and trust copy matches this
  spec.
- Before any future App Store work, run a new sandbox feasibility spike and
  update this spec with evidence.

## Unknowns Requiring Confirmation

- Final public download URL.
- Final support and privacy policy URLs.
- Whether the first public release includes Homebrew in addition to DMG.
- Whether the product ever wants a deliberately reduced Store edition.

