# HoldType static landing page

This folder contains the source for HoldType's statically generated product
landing page. The build uses only Python's standard library and emits one
complete, self-contained site for all ten supported locales.

## Run locally

From the repository root:

```sh
SITE_PREVIEW_DIR="$(mktemp -d)"
python3 website/build_site.py --output-dir "$SITE_PREVIEW_DIR/public"
python3 -m http.server 4173 --directory "$SITE_PREVIEW_DIR/public"
```

Then open <http://localhost:4173/>.

The critical page content, navigation anchors, screenshots, FAQ content, and
download links remain available when JavaScript is disabled. JavaScript is used
only for progressive enhancements: mobile navigation, the labelled illustrative
hero sequence, the Homebrew Copy button, the opt-in video player, and the
full-size screenshot lightbox, the language menu, and the optional root-page
locale suggestion. Each localized URL contains its complete translated content
in generated HTML, so JavaScript is not required to read or navigate the site.

## Localization

The public routes are `/` (English and `x-default`), `/es/`, `/de/`, `/fr/`,
`/pt-br/`, `/ja/`, `/zh-hans/`, `/ko/`, `/ru/`, and `/ar/`. Every page includes
a canonical URL plus reciprocal `hreflang` links; `sitemap.xml` lists the same
route set. Arabic is generated with `dir="rtl"`.

The URL is authoritative. On `/` only, JavaScript may offer a non-blocking
language suggestion based on an explicit saved choice or `navigator.languages`.
It never silently redirects and does not use IP geolocation, browser location
permission, cookies, or a DigitalOcean-specific geo service. An explicit choice
is stored locally in the browser and can always be changed from the header.

Edit shared facts and trusted links in `i18n/site.json`, locale metadata in
`i18n/locales.json`, and copy in the corresponding locale catalog. The builder
fails on missing or extra keys, placeholder drift, raw catalog HTML, unsafe
output directories, and unexpected locale routes.

## Hosting

DigitalOcean App Platform serves the product landing page at
<https://holdtype.app/> as a static site with managed HTTPS and CDN delivery.
Its source component is `website/` on `master`, and automatic deployment is
enabled. The canonical App Platform configuration is `.do/app.yaml`.

GitHub Pages remains the canonical host for the Sparkle appcast and versioned
release notes at <https://holdtype.github.io/holdtype-swift/>. The Pages and
release workflows still build one complete Pages artifact so a website change
or app release cannot erase update metadata. Do not point the shipped update
feed at `holdtype.app` as part of a landing-only deployment.

`README.md`, `design-qa.md`, the generator, and the source catalogs are
repository inputs or documentation and are deliberately excluded from public
artifacts. App Platform runs `build_site.py` and publishes only generated HTML,
shared CSS/JavaScript/assets, `sitemap.xml`, and `robots.txt`.

### Publish explicitly

App Platform normally deploys a committed landing change after it reaches
`master`. To force a rebuild and verify the deployed page:

```sh
scripts/release/publish_digitalocean.py
```

The command uses the authenticated `doctl` context, discovers the app named
`holdtype` (or accepts `DIGITALOCEAN_APP_ID`), synchronizes the committed
`.do/app.yaml`, deploys its latest source within a bounded timeout, and verifies
all ten locale routes plus `sitemap.xml`. A DigitalOcean API token belongs in
the local `doctl` configuration, never in this repository.

The technical App Platform ingress is always verified first. After DNS cutover,
verify the public domain in the same run as an additional check:

```sh
scripts/release/publish_digitalocean.py --url https://holdtype.app/
```

The first domain cutover must be ordered carefully: verify the DigitalOcean
technical hostname, remove `holdtype.app` from the GitHub Pages custom-domain
setting, confirm the stable `github.io/appcast.xml` no longer redirects, then
attach the domains in App Platform and replace only the old apex and `www` DNS
records at the registrar.

## Files

- `index.html` — semantic page template with localization markers.
- `styles.css` — responsive visual system and reduced-motion behavior.
- `script.js` — language choice/suggestion plus the mobile menu, hero
  illustration, Copy, opt-in video, and image lightbox interactions.
- `build_site.py` — deterministic static-site generator and catalog validator.
- `build_site_test.py` — focused generator, route, SEO, RTL, and safety tests.
- `i18n/` — locale registry, shared trusted data, and ten copy catalogs.
- `assets/` — local copies of real HoldType product assets.
- `design-qa.md` — final concept-to-browser fidelity report, added after visual QA.

## Full-size screenshot behavior

The Translation and Billing screenshots themselves use one shared in-page
modal when JavaScript is available; captions do not duplicate the action with a
text link. The screenshots show the standard pointer cursor and keep a native
link to the original image as their no-JavaScript fallback. The modal keeps the
original image inside the viewport, provides a visible Close control, closes
with Escape or an outside click, locks background scrolling, and returns focus
to the opening screenshot.

## Design direction

The selected direction is **Native macOS Layer**: a true-white canvas, system
typography, thin separators, open section layouts, restrained shadows, and a
single blue-violet product accent. The hero uses a code-native generic editor
scene with real HoldType indicator artwork. It is explicitly labelled as an
illustration rather than a recorded product demo.

### Design-system lock

The implementation uses these fixed decisions from the selected concept:

| Surface | Locked value |
| --- | --- |
| Page background | True white, `#ffffff` |
| Primary text | Graphite, `#17181c` |
| Secondary text | `#5f636c` |
| Small muted text | `#6f737c`, 4.75:1 contrast on white |
| Primary accent | Blue, `#5165e8` |
| Supporting accent | Violet, `#844df2` |
| Dividers | Cool gray, `#e5e7ec` |
| Soft section band | `#f7f8fb` |
| Font stack | `-apple-system`, BlinkMacSystemFont, SF Pro/Segoe UI fallbacks |
| Display line height | `1.08` |
| Body line height | `1.62` |
| Small / medium / large radius | `10px` / `16px` / `24px` |
| Content width | Maximum `1160px`, with 24px desktop and 16px mobile gutters |
| Section rhythm | Responsive `80–132px`; `92px` tablet; `76px` mobile |
| Motion | One finite 3.4-second semantic state sequence and a restrained 3.8-second indicator movement |
| Reduced motion | Static inserted state; CSS animation and smooth scrolling disabled |

Typography scales fluidly from a 52–76px desktop hero to a 41–56px mobile
hero. Section headings use a 36–56px desktop range and a 32–44px mobile range.
Body copy remains at 16px or larger; captions are 12.5px with AA-compliant
foreground color.

The container model is deliberately open: thin page-width rules, one soft use-
case band, real screenshots in restrained macOS-style frames, and no repeated
card grid. Primary buttons are solid blue; navigation and secondary actions are
text links. Shadows are reserved for the hero editor and real product windows.

### Responsive anatomy

- `1021px+`: split hero, four-step horizontal workflow, five-point honesty
  contract, alternating feature rows, and two-column FAQ.
- `861–1020px`: narrower split hero and reduced product-window scale.
- `621–860px`: single-column hero and feature sections, two-step workflow rows,
  compact mobile navigation, and two-column data flow.
- `320–620px`: stacked actions and workflow, single-column data flow and FAQ,
  16px page gutters, and full-width primary CTAs.

The first viewport leads with `The most honest Wispr Flow "clone".` It must
immediately explain the provocation through text returning to the active
cursor, the user's OpenAI Platform API key, direct OpenAI billing, no HoldType
subscription, and no mandatory model rewrite. The hero has one action: the free
macOS download. Source inspection remains in the footer, and there is no
separate proof-chip row. No unsupported metric, comparative speed claim, or
undocumented claim about Wispr Flow's internal model is permitted above the
fold.

The code-native editor uses a dry, self-ironic fictional plan to build a tiny
SaaS and reach `$1M ARR`; the interface presents the request as if it were
ordinary. Its caption still identifies the scene as an illustration rather
than a recorded demo and makes no claim that Codex produced the business
result. The usage-cost badge remains visually secondary and must not present
100 as a usage cap, guaranteed maximum, or typical day.

### Page anatomy

1. Sticky brand/navigation header with a GitHub Releases CTA.
2. Split hero with the code-native editor illustration and real indicator art.
3. Hold → speak → release → inserted workflow rail.
4. Five-point `What "honest" means here` contract.
5. Real-use-case band.
6. Translation/vocabulary and Last Result recovery proof.
7. OpenAI billing, the qualified 100-dictation usage example, and exact
   data-boundary explanation.
8. Authentic first-person founder story and microphone photo.
9. GitHub/Homebrew setup, a three-step API-key guide with an opt-in video, and
   native FAQ disclosures.
10. Final download CTA and source-available footer.

## Asset provenance

The initial page and its visual assets are self-contained under `website/`.
The optional API-key tutorial creates a YouTube privacy-enhanced iframe only
after the user presses Play; the default page makes no YouTube media request.
Original repository assets are not modified.

| Landing asset | Repository source | Treatment |
| --- | --- | --- |
| `app-icon.png` | `docs/readme-assets/app-icon.png` | Copied unchanged |
| `indicator-listening.png` | `HoldType/Assets.xcassets/ActivityRecordingIndicatorLight.imageset/ActivityRecordingIndicatorLight@2x.png` | Copied unchanged |
| `indicator-transcribing.png` | `HoldType/Assets.xcassets/ActivityTranscribingIndicatorLight.imageset/ActivityTranscribingIndicatorLight@2x.png` | Copied unchanged |
| `menu-popover.png` | `docs/readme-assets/menu-popover.png` | Copied unchanged |
| `settings-translation.png` | `docs/readme-assets/settings-translation.png` | Proportionally resized to 1400 × 1066 |
| `settings-translation-mobile.png` | `docs/readme-assets/settings-translation.png` | Truthful 1100 × 1000 focus crop of the main settings panel |
| `settings-billing.png` | `docs/readme-assets/settings-billing.png` | Proportionally resized to 1400 × 1066 |
| `settings-billing-mobile.png` | `docs/readme-assets/settings-billing.png` | Truthful 1100 × 1000 focus crop of the main estimate panel |
| `workflow-microphone.jpg` | `docs/readme-assets/workflow-microphone.jpg` | Copied unchanged |

The public page intentionally does not use the Dictionary screenshot because it
contains personal vocabulary examples. The microphone photo is used only with a
caption that special hardware is not required. The two phone crops contain only
pixels from the corresponding real product screenshots; no controls, values, or
UI states were redrawn or retouched.

## Product-copy boundaries

- HoldType is a native macOS app for macOS 14 or newer.
- The exact transcription-model name appears at most once in subdued secondary
  copy. It is not used in metadata, headlines, hero lead or support copy, proof
  chips, section headings, founder copy, the final CTA, or the footer.
- Model-based correction is optional and off by default. Local typography
  cleanup may still run without another model request.
- It inserts accepted text in **most** Mac apps; it does not claim universal
  compatibility.
- HoldType has no account or recurring fee. OpenAI may require prepaid API
  credit and deducts actual request usage from the user's Platform balance.
- The approved cost examples use the current estimated
  `gpt-4o-transcribe` rate of `$0.006/minute`: about `$0.10` for 100 messages
  representing roughly 17 minutes of recorded speech, or about `$3`
  if the same total is repeated daily for 30 days. These are illustrations, not
  a fixed price, usage cap, or typical-day claim, and optional correction and
  translation are separate requests.
- It uses the user's OpenAI Platform API key, and OpenAI bills API usage
  separately.
- The setup guide never asks for the API key on the website. It links to the
  official OpenAI key page, tells the user to paste the secret only into
  HoldType, and explains that the app stores it locally in macOS Keychain.
- The third-party API-key video is supplementary, attributed, and click-to-load.
  Written steps and official OpenAI links remain sufficient if YouTube is
  unavailable or the tutorial becomes outdated.
- Audio goes to OpenAI for transcription. Optional correction and translation
  are separate text requests.
- Completed audio is not retained by default; bounded session-only Retry audio
  and optional local recording-cache retention are disclosed.
- HoldType has no product account, subscription, telemetry, analytics, backend,
  or cloud sync.
- The project is source-available under FSL 1.1 with an MIT future license; it
  is not described as open source during the FSL period.

## Distribution verification

Checked on 2026-07-09:

- `https://github.com/holdtype/holdtype-swift/releases/latest` resolves to the
  public, non-prerelease `v1.0.3` release and includes
  `HoldType-1.0.3.dmg`.
- Primary Download CTAs deliberately use GitHub's stable `releases/latest`
  pointer, which advances automatically; a secondary `All releases` link opens
  the full release history.
- `holdtype/homebrew-tap` contains `Casks/holdtype.rb` at version `1.0.3`,
  pointing to the same GitHub Release disk image and requiring macOS Sonoma.
- The Homebrew block keeps the explicit project-tap flow (`tap`, `trust`,
  `install`, then `open`) and its Copy button copies all four lines together.
- The page links to the current OpenAI API pricing documentation rather than
  embedding a rate that can become stale.

## Implementation constraints

There is no framework, package manager, external font, CDN, form, cookie,
analytics script, tracker, backend, or API route. The standard-library build is
bounded by the release tooling. All URLs used for local assets are relative so
the generated artifact can be served at a domain root or under a static-hosting
subpath.
