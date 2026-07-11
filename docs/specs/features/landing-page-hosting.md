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
- The first viewport may position HoldType as the most honest Wispr Flow
  "clone" when the same viewport immediately defines that claim: text returns
  to the active cursor, model-based correction is optional and off by default,
  the user supplies the OpenAI Platform API key, and OpenAI rather than HoldType
  bills API usage.
- The hero presents one action: the free macOS download. Source inspection
  remains available in the footer, and the hero does not repeat product claims
  as a separate row of proof chips.
- The primary navigation includes adjacent compact Patreon and GitHub links,
  with Patreon positioned to the left of GitHub. Both use the same neutral icon
  treatment, have localized accessible names, and show localized text in the
  expanded mobile navigation. Patreon opens the creator support page at
  `https://www.patreon.com/c/playphraseme`.
- The landing page must turn `honest` into a visible product contract rather
  than leaving it as praise. The contract covers the billing source, the
  default transcription model, optional rewrite pass, explicit Mac-to-OpenAI
  data path, and Mac-only product boundary.
- The exact transcription-model name may appear at most once in public copy,
  in the second card of the honesty contract. The card may repeat OpenAI's
  documented comparison with the original Whisper models, but must not claim
  an unmeasured HoldType-specific speed or accuracy result. The exact model
  name must not also appear in metadata, hero copy, founder copy, the final
  call to action, or the footer.
- The hero editor illustration uses a dry, self-ironic fictional plan to build
  a small SaaS and reach `$1M ARR`. Its caption explicitly identifies the scene
  as an illustration rather than a recorded demo and does not imply that Codex
  produced that business result. The listening and transcribing labels,
  animation states, outer hero, calls to action, and pricing sticker remain
  unchanged when this sample copy changes.
- Product copy may describe the request path, billing boundary, native
  implementation, and documented advantages of the default transcription
  model over OpenAI's original Whisper models. It must not claim that HoldType
  is the fastest or most accurate dictation product, publish a comparative
  speed multiplier, or attribute an undocumented recognition model to a
  competitor without a dated, reproducible evidence package.
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
- Clicking a product screenshot opens the original image in an in-page modal
  when JavaScript is available. Screenshot captions do not repeat this action
  as a separate text link, and pointer input shows the standard link cursor.
  The image fits inside the viewport and keeps its product-specific alternative
  text.
- The image modal closes through its visible Close control, Escape, or a click
  outside the image. Closing returns focus to the screenshot link that opened
  it. Pointer dismissal does not show a focus outline after closing; Escape and
  keyboard activation of Close keep the restored focus visible.
- `appcast.xml` remains available at the stable URL embedded in shipped apps.
- Every release-notes URL referenced by the published appcast remains reachable
  after later website or app releases.
- A push to the configured production branch automatically deploys landing-page
  changes. An explicit publish command can request a bounded rebuild and verify
  the resulting page without storing a DigitalOcean token in the repository.
- The explicit publish command synchronizes the committed `.do/app.yaml` with
  the existing DigitalOcean app before deploying the latest source. A stale
  server-side build command must not publish the source template in place of
  the generated locale artifact.

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
- The production artifact contains every supported locale route plus
  `sitemap.xml`; published HTML contains generated locale identity and no source
  `data-i18n` markers.
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
- If App Spec synchronization fails, any locale route is missing, the sitemap
  is missing, or the root still contains source localization markers, the
  publish command fails instead of reporting a healthy landing deployment.
- If the DigitalOcean technical hostname does not return the expected landing
  marker, custom-domain setup and DNS cutover stop.
- If the third-party tutorial is removed, blocked, or outdated, the official
  OpenAI links and written setup steps remain sufficient to finish setup.
- Without JavaScript, every expandable screenshot remains a normal image link
  to the original local asset.
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
- Publish-script checks verify bounded App Spec synchronization, all generated
  locale routes, sitemap content, expected-site markers, and the absence of
  embedded credentials.
- Artifact tests verify the public-file allowlist, exact appcast copy, and
  reconstruction of every referenced release-notes file.
- Runtime verification checks the deployed root page, current appcast, current
  release notes, Copy interaction, responsive layouts, and browser console.
- Landing-page QA verifies that no YouTube iframe exists before Play, one
  privacy-enhanced iframe replaces the facade after Play, and the guide remains
  readable at desktop and phone widths.
- Landing-page QA opens both product screenshots themselves in the shared modal
  and checks the pointer cursor, absence of duplicate caption links, Close,
  Escape, outside-click dismissal, focus restoration, and phone sizing.
