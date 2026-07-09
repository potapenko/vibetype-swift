# HoldType landing design QA

- Source visual truth: `/Users/eugenepotapenko/.codex/generated_images/019f487c-99ed-7e60-b4d7-78f7d25bcb88/exec-68e9964a-0176-439d-92e0-0253be066833.png`
- Implementation URL: `http://localhost:4173/`
- Planned viewports: `1440×900`, `1280×800`, `768×1024`, `390×844`, `320×568`
- State: default light appearance; inserted hero state for the primary comparison

## Full-view comparison evidence

The source concept has been opened and inspected at original resolution. A
browser-rendered implementation screenshot is still required before a valid
full-view comparison can be made. The in-app Browser was attempted first. After
its local tab became available and the static server was restarted, Browser
policy still prevented opening or reloading the `localhost` target.

## Focused-region comparison evidence

Pending browser capture. The focused passes will cover:

1. Header, hero copy, editor illustration, and real floating indicator.
2. Workflow rail and three-decision strip.
3. Translation and menu-bar product screenshots.
4. Cost/data-boundary block.
5. Mobile header, hero, workflow, and CTA collapse.

## Current findings

- [P1] Browser visual evidence is missing.
  - Location: all rendered surfaces.
  - Evidence: the selected concept is available, but the in-app Browser policy
    rejected the local target before an implementation capture could be made.
  - Impact: composition, typography, spacing, responsive behavior, image
    framing, and interaction states cannot yet receive a defensible visual pass.
  - Fix: provide user-captured desktop and mobile screenshots plus the requested
    manual interaction evidence, or retry after the in-app Browser policy allows
    this local target. Policy-prohibited alternate browser workarounds are not
    acceptable.

## Patches made before the visual pass

- Implemented the selected true-white macOS-native palette and open container
  model.
- Replaced the concept's invented founder portrait and identity with the real
  first-person product story and existing microphone photo.
- Replaced absolute privacy wording with the actual OpenAI, Retry, and local
  recording-cache boundaries.
- Used real HoldType indicator, menu, Translation, and Billing assets.
- Labelled the hero workflow as an illustration rather than a recorded demo.
- Raised small muted text from 3.90:1 to 4.75:1 contrast on white.
- Kept critical content and Download CTAs available without JavaScript.
- Replaced the looping hero sequence with a finite sub-five-second sequence and
  a static final state.
- Preserved keyboard focus when a mobile navigation anchor closes the menu.
- Added truthful mobile focus crops of the real Translation and Billing
  screenshots so the important controls remain legible on narrow screens.
- Added a mobile Download CTA inside the navigation and preserved the same CTA
  in raw no-JavaScript markup.
- Reserved a common hero-state height and a separate lower indicator dock on
  phones to avoid state-change layout shift and text overlap.
- Restored explicit list semantics for Safari/VoiceOver and made the no-JS
  multirow mobile header non-sticky.

## Completed non-visual checks

- Local server root, stylesheet, script, and every used asset return HTTP 200.
- The document contains one `h1`, one `main`, valid internal fragment targets,
  no empty links, no missing local sources, and explicit dimensions/alt text for
  every raster image.
- JavaScript syntax and `git diff --check -- website` pass.
- All text-token pairs used for small copy meet WCAG AA on white; the lowest is
  4.75:1.
- No framework, package manager, runtime CDN, external font, form, cookie,
  analytics, tracker, backend call, or autoplay media is present.
- The GitHub latest-release URL currently resolves to public `v1.0.3` with a
  DMG, the Homebrew cask points to the same DMG, and every external landing link
  returns HTTP 200.

## Implementation checklist

- [ ] Capture the implementation at all five required viewports.
- [ ] Exercise mobile Menu → Escape → focus return.
- [ ] Verify all anchors and at least one native FAQ disclosure interaction.
- [ ] Inspect console warnings/errors and failed network resources.
- [ ] Verify the static inserted state under reduced motion.
- [ ] Verify the page with JavaScript disabled.
- [ ] Compare source and implementation together across the five required
  fidelity surfaces.
- [ ] Patch every actionable P0/P1/P2 finding and repeat the comparison.

## Final result

final result: blocked

Blocker: the in-app Browser security policy currently rejects the local
`http://localhost:4173/` target. Browser instructions explicitly prohibit using
Playwright, raw CDP, or another browser as a workaround for that rejection.
