# HoldType landing design QA

- Source visual truth: `/Users/eugenepotapenko/.codex/generated_images/019f487c-99ed-7e60-b4d7-78f7d25bcb88/exec-68e9964a-0176-439d-92e0-0253be066833.png`
- Implementation URL: `http://localhost:4173/`
- Tested viewports: `1440×900`, `1280×800`, `768×1024`, `390×844`, `320×568`
- State: default light appearance; inserted hero state for the primary comparison

## Full-view comparison evidence

The selected concept and the final browser implementation were opened together
and inspected at desktop, tablet, and phone widths. Final full-page browser
captures were produced outside the repository under
`/tmp/holdtype-landing-qa/`:

- `holdtype-1440x900-loaded.png`
- `holdtype-1280x800-loaded.png`
- `holdtype-768x1024-loaded.png`
- `holdtype-390x844-loaded.png`
- `holdtype-320x568-loaded.png`

The implementation preserves the concept's true-white native-macOS character,
system typography, restrained blue-violet accent, open section model, thin
rules, editor illustration, workflow rail, alternating product proof, and quiet
final CTA. The production page intentionally expands the concept with real
product screenshots, exact privacy/cost boundaries, an authentic founder
story, installation instructions, and a fuller FAQ.

## Focused-region comparison evidence

1. Header and hero retain the sparse hierarchy, dominant headline, single
   primary CTA, editor window, and real HoldType indicator artwork.
2. Workflow and decision surfaces preserve the concept's linear rhythm without
   turning the page into a repeated card grid.
3. Translation and menu-bar sections use real product captures and preserve
   their proportions; narrow screens use truthful source-image focus crops.
4. Cost/data boundaries remain visually open and use the real Billing screen
   instead of unsupported absolute privacy claims.
5. Tablet and phone layouts collapse into a single reading column with a
   keyboard-operable menu, full-width CTAs, local screenshot scrollers, and no
   page-level horizontal overflow.

## Findings and patches

- [P1, fixed] The first `320×568` pass measured a `534px` document width.
  Fixed the single-column grid tracks to use `minmax(0, 1fr)`, containing the
  intentional `520px` screenshot scrollers inside the viewport. The repeated
  pass measured exactly `320px`.
- [P2, fixed] The Homebrew panel originally required manual selection. Added a
  progressive-enhancement Copy button with success/error states and an ARIA
  live status. It copies the complete four-line `tap`, `trust`, `install`, and
  `open` block.
- No remaining actionable P0, P1, or P2 visual, interaction, responsive, or
  accessibility finding was found in the final pass.

## Intentional deviations from the concept

- Replaced the concept's invented founder portrait and identity with the real
  first-person product story and repository microphone photo.
- Replaced absolute privacy language with the actual OpenAI, Retry, and local
  recording-cache boundaries.
- Used real HoldType indicator, menu, Translation, and Billing assets.
- Labelled the hero workflow as an illustration rather than a recorded demo.
- Added the complete setup, FAQ, release-history, and source-license context
  needed by a public product page.

## Completed browser checks

- All five required viewports were captured after lazy images had loaded; every
  image completed with a non-zero natural width.
- `document.documentElement.scrollWidth` equals the viewport width at all five
  required sizes.
- Mobile Menu opens, Escape closes it, `aria-expanded` returns to `false`, and
  focus returns to the Menu button.
- Homebrew Copy changes to `Copied`, announces success, and the in-app Browser
  clipboard contains the exact four-line command block.
- A native FAQ disclosure opens and exposes its answer.
- Internal navigation targets exist; primary downloads use
  `releases/latest`, while `All releases` points to the release history.
- The default finite hero sequence reaches the inserted state. With reduced
  motion it starts and remains inserted, and animation durations collapse to
  `0.01ms`.
- With JavaScript disabled, the full navigation and four visible Download CTAs
  remain available, the inserted hero state remains visible, and the optional
  Copy control is hidden.
- Browser console: zero warnings and zero errors. All requested local HTML,
  CSS, JavaScript, and image resources returned `200` or cache-valid `304`.
- JavaScript syntax, release/Pages tests, YAML parsing, and
  `git diff --check` pass.

## Pricing-message follow-up — 2026-07-10

- Added one restrained, magazine-style `Even 100 dictations a day` badge to the
  hero with the supporting line `for intensive use`. The model rate and
  optional-request qualifications remain in the detailed cost section rather
  than the first viewport.
- Reframed the cost example as 100 messages: roughly 17 minutes of
  recorded speech, about `$0.10`, or about `$3` if the same total is repeated
  daily for 30 days. The page does not present 100 as a cap, guaranteed
  maximum, or typical day.
- Confirmed that the badge and supporting line remain inside the `1440×900`
  first viewport and that `390×844` and `320×568` layouts have no page-level
  horizontal overflow.
- Opened the new `What does dictation cost?` FAQ disclosure and verified its
  prepaid-credit and optional-request qualifications.
- Browser console remained at zero warnings and zero errors.
- Removed message-length and message-speed labels from the 100-message pricing
  example in all ten locales; the example now names only messages or
  dictations.
- Rebuilt the static locale artifact and verified the revised Russian example
  at the desktop viewport and the Arabic RTL example at `390×844`. The Arabic
  page had no horizontal overflow, and both checks had zero console warnings or
  errors.
- Final captures were saved outside the repository at
  `/tmp/holdtype-ten-cent-human-desktop-1440x900.jpg`,
  `/tmp/holdtype-ten-cent-human-mobile-390x844.jpg`, and
  `/tmp/holdtype-ten-cent-human-billing-1440x900.jpg`.

## API-key guide follow-up — 2026-07-10

- Added a three-step beginner guide beneath installation with direct links to
  OpenAI's API-key page and current Help Center article. The page never asks the
  user to enter or paste a secret.
- Verified the supplementary GEEKrar tutorial metadata on YouTube: 2:16,
  published June 2026. The local facade is attributed and does not depend on a
  remote thumbnail.
- Before Play, the guide contained one facade, zero iframes, and zero YouTube,
  `ytimg`, or `googlevideo` resource entries. After Play, the facade was replaced
  by exactly one focused `youtube-nocookie.com` iframe with the expected video
  ID.
- With JavaScript disabled, the facade is hidden and a normal `Watch the API key
  tutorial on YouTube` link remains available.
- Checked `1440×900`, `390×844`, and `320×568`; the guide, actions, and video
  shell stay inside the viewport with no page-level horizontal overflow.
- Browser console remained at zero warnings and zero errors before and after
  loading the player.
- Browser captures were saved outside the repository at
  `/tmp/holdtype-api-key-guide-final-desktop-1440x900.jpg`,
  `/tmp/holdtype-api-key-guide-player-1440x900.jpg`, and
  `/tmp/holdtype-api-key-guide-mobile-390x844.jpg`.

## Full-size image lightbox follow-up — 2026-07-10

- Made both product screenshots themselves open the shared in-page modal; their
  original local-image `href` values remain the no-JavaScript fallback.
- Removed the duplicate full-size text links from every localized caption and
  confirmed both screenshot links expose the standard pointer cursor.
- Verified the Translation and Billing assets, product-specific alternative
  text and captions, and confirmed that opening the modal does not change the
  page URL.
- Verified the visible Close control and Escape. Both close paths remove the
  scroll lock, clear the deferred image source, and return focus to the
  screenshot that opened the modal; outside-click dismissal remains covered by
  the shared lightbox behavior.
- Verified keyboard focus starts on Close and stays inside the single-control
  modal while the background is inert.
- At `1280×720` and `390×844`, the original screenshot and Close control
  remain inside the viewport with no page-level horizontal overflow.
- Browser console remained at zero warnings and zero errors.
- Final captures were saved outside the repository at
  `/tmp/holdtype-screenshot-click-desktop.png`,
  `/tmp/holdtype-screenshot-click-mobile.png`, and
  `/tmp/holdtype-screenshot-caption-mobile.png`.

## Hero price-sticker placement follow-up — 2026-07-10

- Removed the price sticker and its supporting paragraph from the left hero
  flow, restoring the original single qualification line beneath the actions.
- Positioned the sticker as an independent layer over the demo window's upper
  right corner. It no longer changes either hero column's intrinsic height.
- Reframed the visible example as `Even 100 a day`, `≈ $0.10`, and
  `for intensive use`; the detailed section retains the rate and duration
  qualifications.
- At `1440×900`, the sticker straddles the demo-window corner and the complete
  hero remains inside the first viewport. At `390×844`, the qualification wraps
  to two lines, the sticker stays inside the viewport, and document width
  remains exactly `390px`.
- Page identity, meaningful hero content, absence of a framework error overlay,
  and zero browser warnings or errors were reconfirmed after the change.
- Final captures were saved outside the repository at
  `/tmp/holdtype-hero-badge-after-desktop-1440x900.png`,
  `/tmp/holdtype-hero-badge-mobile-top-390x844.png`, and
  `/tmp/holdtype-hero-badge-after-mobile-390x844.png`.

## Hero price-sticker edge alignment follow-up — 2026-07-10

- Used the current demo-window crop as an ImageGen component reference. The
  useful composition decision was to align the sticker's center with the
  window's right edge and raise it slightly; no generated pixels or invented UI
  were added to the site.
- Replaced the ambiguous `Even 100 a day` with
  `Even 100 dictations a day`. The price and intensive-use qualifier remain
  unchanged.
- At `1440×900`, measured sticker center and window right edge are both exactly
  `1284px`. The sticker remains fully inside the viewport and document width
  remains `1440px`.
- At `390×844`, the narrower safe offset keeps the sticker and all of its text
  inside the viewport; document width remains exactly `390px` with no browser
  warnings or errors.
- Evidence was saved outside the repository at
  `/tmp/holdtype-hero-sticker-component-before.png`,
  `/tmp/holdtype-hero-sticker-component-after.png`,
  `/tmp/holdtype-hero-badge-edge-desktop-1440x900.png`,
  `/tmp/holdtype-hero-badge-edge-mobile-top-390x844.png`, and
  `/tmp/holdtype-hero-badge-edge-mobile-visual-390x844.png`. The ImageGen design
  reference remains under the local Codex generated-images directory.

## Ten-locale landing follow-up — 2026-07-10

- Built and served the final generated artifact rather than the source template.
  Confirmed the exact route set for English, Spanish, German, French, Brazilian
  Portuguese, Japanese, Simplified Chinese, Korean, Russian, and Arabic.
- Verified a selector-driven Arabic-to-Japanese transition, correct `lang` and
  `dir` state, native language names, route-authoritative content, and zero
  page-level overflow at `1440×1000` and `390×844`.
- Arabic desktop and phone passes confirmed mirrored layout, readable isolated
  Latin product/UI terms, logical FAQ spacing, a physically LTR Homebrew command
  panel, and normal tracking for Arabic copy. Japanese and German phone passes
  confirmed CJK heading tracking, long-copy wrapping, and no horizontal overflow.
- Mobile Menu opened with localized labels; Escape closed it, reset
  `aria-expanded`, and returned focus to the button. The language selector
  exposed ten ordinary localized links at both desktop and phone widths.
- Selecting Japanese persisted that explicit preference. A fresh English-root
  tab offered the Japanese route without redirecting and localized the message,
  action, dismiss text, and accessible labels. Dismissing the equivalent Russian
  suggestion hid it for the browser session.
- With script execution disabled, the English phone layout retained the complete
  navigation, Download action, core content, and ten native `<details>` language
  links. Following the Spanish link loaded the complete Spanish static page.
- Browser console: zero warnings and zero errors. The bounded local server log
  contained successful or cache-valid responses and no missing-resource response.
- Evidence was saved outside the repository at
  `/tmp/holdtype-localization-ar-desktop.png`,
  `/tmp/holdtype-localization-ar-mobile.png`,
  `/tmp/holdtype-localization-ja-mobile.png`,
  `/tmp/holdtype-localization-nojs-mobile.png`, and
  `/tmp/holdtype-localization-nojs-menu-mobile.png`.
- No remaining actionable P0, P1, or P2 localization, responsive, interaction,
  accessibility, SEO, or RTL finding remained after the final pass.

## Final result

final result: passed
