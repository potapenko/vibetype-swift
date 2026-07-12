# Landing Page Localization

## Goal

Make the HoldType product landing page readable in ten supported locales while
keeping language choice predictable, accessible, and compatible with static
hosting.

## Scope

- localized landing-page copy, interactive labels, and metadata;
- stable locale routes, language switching, and language suggestions;
- static-search metadata and right-to-left presentation;
- DigitalOcean and GitHub Pages publication of the localized site.

## Non-goals

- localizing the HoldType macOS app or the English UI shown in screenshots;
- selecting language from IP address, country, or device geolocation;
- changing the shipped Sparkle feed or release-notes routes.

## Supported locales and routes

The site supports exactly these ten initial locales:

| Locale | Public route |
| --- | --- |
| `en` | `/` |
| `es` | `/es/` |
| `de` | `/de/` |
| `fr` | `/fr/` |
| `pt-BR` | `/pt-br/` |
| `ja` | `/ja/` |
| `zh-Hans` | `/zh-hans/` |
| `ko` | `/ko/` |
| `ru` | `/ru/` |
| `ar` | `/ar/` |

The root is the English canonical page and the `x-default` destination. There
is no separate `/en/` page.

## User-visible behavior

- Every supported route presents the same HoldType product and actions in its
  route's language, including navigation, interactive status, accessibility
  labels, and success or error messages.
- The language selector uses the languages' own names and ordinary links to
  the supported routes. It remains usable when JavaScript is unavailable.
- A directly opened locale URL is authoritative. Stored or browser preferences
  never redirect or replace a locale selected by its URL.
- On `/`, the site may first consult a previously selected locale and then
  `navigator.languages` to offer a supported non-English page. The offer is a
  visible suggestion that requires a user action; the English root does not
  redirect automatically on a first or later visit.
- Following a language-selector link may save that explicit choice in
  `localStorage`. Storage is an enhancement, not a requirement for navigation.
- Unsupported, unavailable, or ambiguous browser locales fall back to English
  without an error or a language prompt.
- Matching accepts common regional variants of a supported language. Portuguese
  variants may suggest `pt-BR`; only Simplified Chinese variants may suggest
  `zh-Hans` rather than silently mapping Traditional Chinese preferences.
- The Arabic page declares and presents a right-to-left document. Product
  names, code, commands, and other inherently left-to-right fragments remain
  readable within that layout.
- Website localization does not imply app localization. The shipped app UI and
  product screenshots remain English, and localized copy must not claim or
  suggest that the app interface is available in the page language.
- Every locale uses the same English launch artwork for social-link previews.
  Its accessible description is localized and explicitly identifies the words
  shown in English rather than implying that the artwork itself is translated.
- On phone-width viewports, the five honesty cards stack vertically and each
  card occupies the full available content width.

## Invariants

- Language detection never uses GeoIP, country headers, device location, or a
  third-party geolocation service.
- Every locale is a complete static page. Core content, download links, setup
  instructions, and language navigation work without JavaScript.
- English is the final fallback when locale matching, storage, or client-side
  enhancement is unavailable.
- Translation does not change commands, URLs, product names, pricing meaning,
  privacy promises, or the boundary that users supply their own OpenAI API key.
- A product-copy change that changes meaning ships with semantically equivalent
  updates in every supported locale. Matching JSON keys without updating the
  translated message is not a complete localization.
- Pricing examples describe the count as messages or dictations without
  characterizing their length, speed, or typical size in any locale.
- The shared social image is a 1200 × 630 PNG published at the same absolute
  HTTPS URL on every locale route. Open Graph exposes its type, dimensions, and
  localized alternative text; X/Twitter uses the large-image card.
- GitHub Pages publication remains a complete artifact containing the landing
  routes, the existing `appcast.xml`, and every release-notes page referenced
  by the appcast. A website-only publish must not regenerate, remove, or alter
  update metadata.

## Edge cases and failure policy

- If `localStorage` is blocked, throws, or contains an unsupported value, the
  selector still navigates by link and browser-language matching may continue.
- If `navigator.languages` is absent, empty, or contains no supported locale,
  the root remains English without showing a broken suggestion.
- If a translation is incomplete or its required metadata is missing, the
  localized artifact fails validation instead of publishing a mixed-language
  page.
- Failure to build or publish any locale must not replace the currently
  published site or damage the stable Sparkle feed.

## Route / state / data implications

- The locale route determines the rendered language and each page declares the
  corresponding BCP 47 `lang` value. Arabic additionally declares `dir="rtl"`.
- Each locale page has a self-referencing canonical URL, reciprocal `hreflang`
  links for all ten locales, and an `x-default` link to `/`.
- Titles, descriptions, social-sharing metadata, accessible image text, and
  other language-bearing metadata are localized. The social image itself is
  intentionally shared English campaign artwork. The sitemap contains every
  canonical locale URL.
- The only persisted locale state is the user's explicit language choice in
  local browser storage; it contains no account, location, or personal data.

## Verification mapping

- Static artifact checks verify the exact route set, complete locale keys,
  localized metadata, canonical and reciprocal `hreflang` links, sitemap
  entries, Arabic direction, the shared social-image URL, its exact PNG
  dimensions, and large-card metadata.
- Browser QA verifies direct-route precedence, root-only suggestions, browser
  locale matching, explicit-choice persistence, keyboard-accessible switching,
  and storage-failure fallback.
- No-JavaScript QA verifies readable content, working download and setup links,
  and ordinary language-selector navigation on every locale route.
- Responsive visual QA covers long German text, CJK wrapping, Arabic RTL, and
  the truthful presentation of English app screenshots.
- Pages artifact checks verify that adding locale routes does not change or
  omit the appcast or any referenced release notes.
