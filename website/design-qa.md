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

- Added one restrained, magazine-style `Even 100 a day` badge to the hero with
  the human supporting line `A hundred quick messages is already a very
  talkative day.` The model rate and optional-request qualifications remain in
  the detailed cost section rather than the first viewport.
- Reframed the cost example as 100 quick voice messages: roughly 17 minutes of
  recorded speech, about `$0.10`, or about `$3` if the same total is repeated
  daily for 30 days. The page does not present 100 as a cap, guaranteed
  maximum, or typical day.
- Confirmed that the badge and supporting line remain inside the `1440×900`
  first viewport and that `390×844` and `320×568` layouts have no page-level
  horizontal overflow.
- Opened the new `What does dictation cost?` FAQ disclosure and verified its
  prepaid-credit and optional-request qualifications.
- Browser console remained at zero warnings and zero errors.
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

## Final result

final result: passed
