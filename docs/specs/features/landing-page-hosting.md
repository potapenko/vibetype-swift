# Landing Page Hosting

## Goal

Publish the static HoldType product landing page at `https://holdtype.app/`
through DigitalOcean App Platform without breaking the Sparkle update feed
that already uses GitHub Pages.

## Scope

- the static files under `website/`;
- a DigitalOcean App Platform static-site deployment from this repository;
- GitHub Pages deployment of the existing update metadata;
- the existing Sparkle `appcast.xml` and versioned release-notes pages;
- the `holdtype.app` and `www.holdtype.app` custom domains.

## User-visible behavior

- `https://holdtype.app/` serves the HoldType landing page through DigitalOcean
  App Platform's static-site service, managed HTTPS, and CDN.
- `www.holdtype.app` redirects to the canonical apex domain.
- The generated pages remain usable at the DigitalOcean technical hostname and
  at the custom-domain routes without a server-side application runtime.
- Download links continue to use the stable GitHub latest-release URL.
- The Homebrew Copy button copies the complete project-tap installation block.
- The hero may present 100 dictations as about `$0.10` at the current
  estimated `gpt-4o-transcribe` rate. It frames that volume as intensive use;
  the detailed cost section explains that it is roughly 17 minutes of audio.
- API-key setup is explained in short written steps with direct links to the
  official OpenAI key page and Help Center article. A third-party video is
  supplementary and never the only setup path.
- The embedded tutorial starts as a local facade. YouTube content loads only
  after the user explicitly chooses Play; without JavaScript, a normal YouTube
  link remains available.
- Full-size product-image links open the original image in an in-page modal when
  JavaScript is available. The image fits inside the viewport and keeps its
  product-specific alternative text.
- The image modal closes through its visible Close control, Escape, or a click
  outside the image. Closing returns focus to the link that opened it.
- `appcast.xml` remains available at the stable URL embedded in shipped apps.
- Every release-notes URL referenced by the published appcast remains reachable
  after later website or app releases.
- A push to the configured production branch automatically deploys landing-page
  changes. An explicit publish command can request a bounded rebuild and verify
  the resulting page without storing a DigitalOcean token in the repository.

## Invariants

- The App Platform static-site component publishes only the public files under
  `website/`; repository documentation and release automation are not exposed.
- A Pages deployment remains a complete artifact: landing files, appcast, and
  all release notes referenced by that appcast are deployed together so the
  existing update channel remains self-contained.
- A website-only deployment must source the appcast from the latest stable
  GitHub Release rather than regenerate update metadata.
- A release deployment must use the newly generated signed appcast and the
  same release-notes content published in the GitHub Release.
- Website documentation and local QA files are not part of the public artifact.
- Pages deployments are serialized so a website publish cannot race a release
  publish and leave a partial artifact live.
- GitHub Pages must not retain `holdtype.app` as its custom domain after the DNS
  cutover. Before DNS changes, the stable `github.io` appcast URL must return
  the feed directly without redirecting through `holdtype.app`.
- The DigitalOcean technical hostname must pass the landing health check before
  either custom domain is attached or DNS is changed.
- DNS changes preserve unrelated records and replace only the previous GitHub
  Pages apex and `www` records after DigitalOcean reports the required target.
- A 100-dictation day is an illustrative intensive-use scenario, not a usage
  cap, guaranteed maximum, or claim about typical behavior. The hero example
  stays visibly approximate; the detailed cost section names the
  OpenAI-controlled rate and excludes optional correction and translation
  requests.
- The API-key guide must not ask the user to paste a key into the website. It
  directs the user to paste the secret only into HoldType, where the app stores
  it locally in macOS Keychain.
- The video facade must not create a YouTube iframe or request YouTube media
  before Play. The loaded player uses YouTube's privacy-enhanced embed domain.
- While the image modal is open, the page behind it does not scroll. One shared
  modal serves every enhanced full-size product-image link, and background
  controls are removed from keyboard focus.

## Failure policy

- If the latest stable release, its appcast, or any referenced release notes
  cannot be resolved within a bounded timeout, the new deployment fails and the
  previously published Pages site remains in place.
- If an App Platform deployment does not reach a successful state within its
  bounded timeout, the publish command fails and does not change DNS.
- If the DigitalOcean technical hostname does not return the expected landing
  marker, custom-domain setup and DNS cutover stop.
- If the third-party tutorial is removed, blocked, or outdated, the official
  OpenAI links and written setup steps remain sufficient to finish setup.
- Without JavaScript, every full-size image remains a normal link to the
  original local asset.
- A landing-page failure must not replace or remove the existing Sparkle feed.
- A release must not report success if its Pages deployment removes the landing
  page or publishes update metadata that differs from the release asset.

## Route / state / data implications

- The public product root is `https://holdtype.app/`; the App Platform technical
  hostname remains a non-canonical deployment and diagnostic route.
- The existing update-feed route remains
  `https://holdtype.github.io/holdtype-swift/appcast.xml` until a separate
  updater migration changes the shipped `SUFeedURL`.
- Versioned release notes use `HoldType-<version>.md` at the same Pages root.
- The `holdtype.app` cutover changes landing hosting and DNS configuration, not
  the static page's relative asset paths or the shipped update-feed URL.

## Verification mapping

- Workflow checks verify that both website and release publishes construct the
  same complete Pages artifact.
- App Platform configuration checks verify a static-site component sourced from
  `website/`, the production branch, and automatic deployments.
- Publish-script checks verify bounded deployment polling, expected-site marker
  validation, and the absence of embedded credentials.
- Artifact tests verify the public-file allowlist, exact appcast copy, and
  reconstruction of every referenced release-notes file.
- Runtime verification checks the deployed root page, current appcast, current
  release notes, Copy interaction, responsive layouts, and browser console.
- Landing-page QA verifies that no YouTube iframe exists before Play, one
  privacy-enhanced iframe replaces the facade after Play, and the guide remains
  readable at desktop and phone widths.
- Landing-page QA opens both product screenshots in the shared modal and checks
  Close, Escape, outside-click dismissal, focus restoration, and phone sizing.
