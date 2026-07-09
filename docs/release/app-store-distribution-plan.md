# Mac App Store Distribution Research Note

Research date: 2026-07-09.

Current decision: Mac App Store distribution is not an execution target for the
current HoldType macOS product. The supported public distribution path is
direct download through a signed and notarized Developer ID build, with Sparkle
updates for the downloadable build and Homebrew as an optional install path.

The product-level contract is now in
`docs/specs/features/app-store-distribution.md`. This release note preserves
the research evidence and the practical plan for distribution work.

## Primary References

- Apple App Review Guidelines:
  https://developer.apple.com/app-store/review/guidelines/
- Apple App Sandbox:
  https://developer.apple.com/documentation/security/app-sandbox
- Apple App Store Connect build upload guide:
  https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- Apple TestFlight overview:
  https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
- Fixkey official site:
  https://www.fixkey.ai/
- Fixkey MacUpdate listing:
  https://fixkey.macupdate.com/
- Wispr Flow official site:
  https://wisprflow.ai/
- Wispr Flow Mac install guide:
  https://docs.wisprflow.ai/articles/7682075140-how-to-install-wispr-flow-on-mac
- Wispr Flow iPhone App Store listing:
  https://apps.apple.com/us/app/wispr-flow-ai-voice-keyboard/id6497229487

## Decision

Do not implement a Mac App Store release track now.

Do not create the App Store Connect app record, Store entitlements, Store CI
workflow, TestFlight upload automation, fastlane metadata, or review submission
automation while the current product contract is unchanged.

The direct distribution track is the realistic launch path because it preserves
HoldType's core value: system-wide voice input into the active Mac app.

## Why Direct Distribution Is Viable

The repository already points in the right direction for direct macOS
distribution:

- Developer ID signing is the right trust model for non-Store macOS utilities.
- Notarized DMG distribution gives users Gatekeeper validation without Mac App
  Store restrictions.
- Sparkle is appropriate for downloadable Mac apps and can be disabled only for
  hypothetical Store builds.
- GitHub Releases and a project Homebrew tap are enough for repeatable release
  automation.
- A clear download page, privacy page, changelog, and install guide can address
  the trust problem without changing the app's architecture.

This is also consistent with the market pattern for nearby products. Fixkey
and Wispr Flow both advertise system-wide Mac writing or dictation behavior and
use direct Mac downloads. Wispr Flow has an iPhone App Store app, but its Mac
install guide tells users to download a DMG from the website and drag the app
into Applications.

## Why Mac App Store Is Not Viable Now

Apple requires Mac App Store apps to be sandboxed and updated through the Mac
App Store. That is a poor fit for HoldType's current core workflow.

HoldType is not just a recorder. The product records speech, transcribes it,
and inserts the result into whichever app currently has focus. Current product
specs also include Accessibility-gated paste automation and nearby text context
behavior. `docs/specs/features/privacy-and-permissions.md` explicitly states
that the macOS MVP app target must not use App Sandbox while active-app
insertion, Paste Last Result, or nearby text context depend on
Accessibility-gated control of other apps.

The risky part is not microphone capture or OpenAI networking. Those are normal
sandbox capabilities. The risky part is broad, system-wide interaction with
other apps. A Store-safe version would likely need one of these compromises:

- remove or reduce automatic insertion;
- remove nearby text context;
- fall back to copy-to-clipboard/manual paste;
- rely on temporary sandbox exceptions that are review-risky and hard to
  justify for "any active app";
- maintain a separate Store edition that behaves worse than the direct build.

Those compromises undermine the reason a user would choose HoldType. A reduced
Mac App Store edition may look easier to install, but it would be a different
product with weaker value.

## Competitor Evidence

### Fixkey

Fixkey presents itself as a native macOS AI writing assistant that works across
Mac apps. Its official site uses a `Download for Mac` flow rather than a Mac App
Store link. Public MacUpdate data also lists Fixkey as a downloadable Mac app.

Apple's public Mac software search did not show an official Fixkey Mac App
Store listing during the 2026-07-09 review.

### Wispr Flow

Wispr Flow has an App Store app for iPhone. The listing is marked as an iPhone
app and references sync with desktop apps on Mac and Windows.

The Mac install guide is a direct download flow: download from `wisprflow.ai`,
choose Apple Silicon or Intel, open the DMG, and drag Wispr Flow into
Applications.

Apple's public Mac software search did not show an official Wispr AI, Inc. Mac
App Store listing during the 2026-07-09 review. A similarly named Mac App Store
app exists from another developer, and public reviews identify it as not the
real Wispr Flow.

### Interpretation

The closest comparable products do not treat the Mac App Store as their Mac
distribution channel. They use App Store distribution where the platform model
fits, such as iPhone keyboard apps, and direct downloads for the full macOS
system-wide utility.

That is the right model for HoldType unless the macOS product architecture
changes materially.

## Direct Distribution Plan

The implementation plan should now focus on the direct channel:

1. Keep the direct build as the production macOS product.
2. Keep Developer ID signing and notarization as the trust baseline.
3. Keep Sparkle only for downloadable builds.
4. Preserve the GitHub Release artifact pipeline for notarized DMG and ZIP
   assets.
5. Keep or add a Homebrew tap/cask path that installs the same notarized DMG.
6. Add a public install page that explains:
   - the app is signed with an Apple Developer ID;
   - the app is notarized by Apple;
   - why Accessibility, Input Monitoring, and microphone permissions are
     needed;
   - how updates work;
   - where privacy and support information live.
7. Add release QA that verifies:
   - code signing;
   - notarization and stapling;
   - Gatekeeper assessment;
   - Sparkle update metadata;
   - DMG layout;
   - Homebrew cask checksum;
   - no sensitive logs or transcripts in release artifacts.

## Work To Avoid For Now

Do not spend time on:

- App Store Connect app record setup;
- App Store screenshots and metadata;
- Mac App Store privacy questionnaire work;
- App Store sandbox entitlements;
- TestFlight upload automation;
- Store-specific CI environments and secrets;
- fastlane `deliver`/`pilot` integration for HoldType;
- reduced Store edition behavior.

Those items only become useful if the product decision changes.

## Reopen Criteria

Reopen Mac App Store distribution only if at least one of these becomes true:

- Apple introduces a Store-compatible permission model for this kind of
  system-wide text input utility.
- HoldType deliberately creates a separate Store edition with a product-level
  fallback that users would still value.
- A sandboxed prototype proves that automatic insertion, permission
  registration, and the required context behavior work reliably without
  temporary exceptions.
- A business decision accepts that the Store edition is materially weaker than
  the direct edition.

If reopened, create a fresh implementation plan from the spec rather than
reviving the old upload checklist.
