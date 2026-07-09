# HoldType static landing page

This folder is a self-contained, build-free product landing page for HoldType.

## Run locally

From the repository root:

```sh
python3 -m http.server 4173 --directory website
```

Then open <http://localhost:4173/>.

The critical page content, navigation anchors, screenshots, FAQ content, and
download links remain available when JavaScript is disabled. JavaScript is used
only for the mobile navigation and the labelled illustrative hero sequence.

## Files

- `index.html` — semantic page content and product copy.
- `styles.css` — responsive visual system and reduced-motion behavior.
- `script.js` — mobile menu and listening → transcribing → inserted illustration.
- `assets/` — local copies of real HoldType product assets.
- `design-qa.md` — final concept-to-browser fidelity report, added after visual QA.

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

- `1021px+`: split hero, four-step horizontal workflow, three-column reasons,
  alternating feature rows, and two-column FAQ.
- `861–1020px`: narrower split hero and reduced product-window scale.
- `621–860px`: single-column hero and feature sections, two-step workflow rows,
  compact mobile navigation, and two-column data flow.
- `320–620px`: stacked actions and workflow, single-column data flow and FAQ,
  16px page gutters, and full-width primary CTAs.

The allowed first-viewport copy is limited to the HoldType brand, essential
navigation, the approved headline `Speak the whole thought.`, the approved
support line `HoldType puts it where you’re working.`, the native macOS/BYOK
description, the two approved actions, the macOS/cost qualification, and the
explicit illustration caption. No eyebrow, metric, testimonial, badge, or
unavailable demo action is permitted above the fold.

### Page anatomy

1. Sticky brand/navigation header with a GitHub Releases CTA.
2. Split hero with the code-native editor illustration and real indicator art.
3. Hold → speak → release → inserted workflow rail.
4. Three product-decision columns.
5. Real-use-case band.
6. Translation/vocabulary and Last Result recovery proof.
7. OpenAI billing and exact data-boundary explanation.
8. Authentic first-person founder story and microphone photo.
9. GitHub/Homebrew setup and native FAQ disclosures.
10. Final download CTA and source-available footer.

## Asset provenance

All assets are copied from this repository so the page has no runtime asset
dependency outside `website/`. Original source files are not modified.

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
- It inserts accepted text in **most** Mac apps; it does not claim universal
  compatibility.
- It uses the user's OpenAI Platform API key, and OpenAI bills API usage
  separately.
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
- `holdtype/homebrew-tap` contains `Casks/holdtype.rb` at version `1.0.3`,
  pointing to the same GitHub Release disk image and requiring macOS Sonoma.
- The page links to the current OpenAI API pricing documentation rather than
  embedding a rate that can become stale.

## Implementation constraints

There is no framework, package manager, build step, external font, CDN, form,
cookie, analytics script, tracker, backend, or API route. All URLs used for local
assets are relative so the folder can be served at a domain root or under a
static-hosting subpath.
