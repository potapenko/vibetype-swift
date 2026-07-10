# HoldType Landing Page Working Plan

Status: working brief for the published `holdtype.app` landing page

Research snapshot: 2026-07-09

## Product Position

HoldType is the most honest Wispr Flow "clone": a native macOS dictation app
that returns text to the active cursor, uses the user's OpenAI Platform API key,
and adds no HoldType account or subscription. Model-based correction is
optional and off by default, so ordinary dictation does not require a second
model rewrite.

The exact transcription model is a secondary implementation detail, not the
positioning. Name it once in subdued technical copy; do not repeat it in
headlines, proof chips, section headings, founder copy, or the footer.

The landing page should lead with this concrete product and commercial
contract. The idea of speaking a complete thought may remain a supporting use
case, but it is not the product position.

Primary job:

> Let me hold one shortcut, dictate, and put the returned text at the cursor
> without paying for another dictation subscription.

Secondary job:

> Let me speak in the language where the thought comes naturally and insert the
> result in the language my work requires.

Recommended positioning line:

> The most honest Wispr Flow "clone".

Supporting line:

> No account. No mandatory rewrite pass. You pay OpenAI, not HoldType.

## Role Of Each Surface

The README and landing page should share the same positioning, but they do not
have the same job:

- **GitHub README:** convert an already interested visitor, establish technical
  trust, provide the direct download, and support source inspection.
- **Product landing page:** demonstrate the result to a first-time visitor,
  explain BYOK and privacy without repository context, and answer purchase or
  download objections.
- **Launch and ongoing content:** create attention outside either page through
  a reusable demo, founder story, measured examples, release notes, and factual
  comparison content.

A polished README can improve conversion and trust, but it cannot create
distribution on its own. The first demo asset should therefore work in the
README, on the landing page, and in external launch posts.

## What The Market Currently Emphasizes

This is a positioning study, not a feature checklist.

| Product | Strongest presentation pattern | Lesson for HoldType |
| --- | --- | --- |
| [Wispr Flow](https://wisprflow.ai/) | A quantified speed promise, immediate before/after demonstration, repeated download CTA, and extensive social proof | Show the result before explaining settings. Do not copy speed multipliers without HoldType-specific measurement. |
| [OpenWhispr](https://openwhispr.com/) | Privacy and user control directly after the hero, plus a concise GitHub README with direct downloads | Explain the data boundary early. Keep HoldType focused instead of matching OpenWhispr's meetings, notes, agents, and local-model breadth. |
| [Superwhisper](https://superwhisper.com/) | A short “speak → polished text” hero, visible demo, concrete coding workflows, and clear local/cloud data-flow documentation | Use a real end-to-end demo and show the apps where HoldType is useful. Do not turn model choice into the headline. |
| [VoiceInk](https://tryvoiceink.com/) | Native Mac and privacy positioning, concrete use cases, founder presence, pricing clarity, and public source as trust | Combine founder credibility with product proof. Avoid accuracy and speed claims without a reproducible method. |
| [MacWhisper](https://www.macwhisper.com/) | Use-case-led product breadth, UI proof, reviews, and a clear one-time purchase story | Borrow use-case clarity, not the all-in-one transcription-studio scope. |

## Recommended Page Order

### 1. Hero

Goal: explain the outcome, platform, and commercial boundary within five
seconds.

- Headline: `The most honest Wispr Flow "clone".`
- Supporting copy: `No account. No mandatory rewrite pass. You pay
  OpenAI, not HoldType.`
- Supporting copy explains that text returns to the cursor, the user's OpenAI
  key is used directly, and translation runs only when requested. Do not repeat
  these claims in a separate proof-chip row.
- Primary CTA: `Download free for macOS`.
- Source inspection remains in the footer rather than the hero.
- Qualification: `Free app · OpenAI API usage billed separately · macOS 14+`.

### 2. End-To-End Demo

Show the actual product result, not a Settings window:

1. The cursor is visible in Codex, Claude, ChatGPT, Mail, or Notes.
2. Right Command is held and the floating indicator appears.
3. A natural spoken paragraph is recorded.
4. The accepted text appears at the cursor after release.

The ideal asset is a silent 10–20 second video with a compact caption. A short
GIF can be the fallback for GitHub.

### 3. What "Honest" Means Here

Present this section under `What "honest" means here`:

1. **Text stays where the user works:** the result returns to the active cursor
   without a separate editor or browser tab.
2. **The bill has a source:** OpenAI deducts API usage from the Platform account
   connected through the user's key; HoldType adds no monthly fee.
3. **The rewrite pass is optional:** model-based correction is off by default.
4. **The data path is explicit:** Mac to OpenAI to the active cursor.
5. **The limits are visible:** HoldType is Mac-only and is not presented as a
   team cloud platform.

### 4. Work It Fits

Use real before/after examples rather than profession tiles:

- a detailed prompt for a coding agent;
- a review or explanation that would otherwise be shortened;
- a message or note dictated without opening another editor;
- Russian speech inserted as an English reply;
- a project name corrected with Dictionary spelling context.

### 5. Cost And Data Boundary

Explain the decision in one place:

- HoldType is free and has no recurring fee; OpenAI deducts API usage directly
  from the user's Platform balance;
- ChatGPT subscriptions and OpenAI Platform API billing are separate;
- new OpenAI API accounts may require prepaid credit;
- the local Billing view currently estimates successful audio transcriptions,
  not correction or translation requests;
- audio goes to OpenAI for transcription;
- optional correction and translation are separate text requests;
- the key stays in Keychain;
- completed audio is not retained by default, while a recoverable failed
  attempt may keep bounded session-only audio for Retry;
- HoldType has no account, product backend, telemetry, analytics, or cloud sync.

A simple data-flow visual can make this easier to scan:

`Microphone → HoldType → OpenAI transcription → optional text step → active app`

Use one factual, low-friction cost conversion rather than an abstract
minutes-per-day table:

> About $0.10 covers 100 voice messages at the current estimated OpenAI
> transcription rate—roughly 17 minutes of recorded speech in total.
> Repeating the same daily total for 30 days is about $3.

The hero may use the restrained
`Even 100 a day · ≈ $0.10 · for voice messages` badge and the supporting line
`A hundred messages is already a very talkative day.` Keep the 17-minute,
provider-rate, and $3 monthly qualifications in the detailed cost
section instead of the first viewport. The detailed example must still state
that optional correction and translation are separate.

### 6. Founder Story

Keep the story specific and short:

- open with `I wanted Wispr Flow. I didn't want the bullshit.`;
- explain the concrete frustration: another product account, opaque billing,
  and a mandatory rewrite pipeline between voice and cursor;
- answer it with the user's API key, direct OpenAI billing, optional correction,
  native Swift, and no extra account or subscription;
- HoldType is built and tested through the same Codex-heavy voice workflow;
- the desk microphone photo belongs here, with a note that special hardware is
  not required.

### 7. Trust And Proof

Use evidence that can be checked:

- signed and notarized current release;
- current macOS requirement;
- public source and release history;
- short privacy explanation;
- measured examples with the provider rate, recording length, date, and method;
- real user quotes only after permission and attribution.

### 8. Download, Setup, And FAQ

Repeat the primary download CTA, then provide the shortest setup path. Homebrew
is secondary to the disk image.

For people unfamiliar with API keys, add a compact guide directly under setup:

1. explain that an API key is a private OpenAI Platform credential, separate
   from a ChatGPT login or subscription;
2. link to OpenAI's official API-key page and Help Center article;
3. tell the user to create and copy the key, then paste it only into
   HoldType Settings → OpenAI;
4. state that the app stores it locally in macOS Keychain and that the website
   never asks for the secret.

A short third-party video may sit beside these steps, but it is supplementary.
Show an attributed local facade first and create a privacy-enhanced YouTube
iframe only after Play. Preserve a normal YouTube link without JavaScript, and
keep the written path complete if the video is removed, blocked, or outdated.

FAQ should answer:

- Why is an OpenAI API key required?
- Is ChatGPT Plus enough?
- What does dictation usually cost?
- What data is sent to OpenAI?
- Is audio stored?
- Which Mac apps work?
- Which languages are supported?
- Why are microphone, Accessibility, and Input Monitoring permissions needed?
- Is HoldType open source or source-available?

## Assets And Evidence Still Needed

Priority 0:

- 10–20 second end-to-end demo in a real target app;
- hero frame that shows the cursor, floating indicator, and inserted text;
- a first-run permissions walkthrough beyond the published API-key guide;
- a documented cost example that states what the estimate includes.

Priority 1:

- anonymized voice-to-text before/after examples;
- a Dictionary vocabulary example;
- screenshots for Transcript History, Permissions, and Updates;
- a list of tested apps and known insertion limitations;
- measured latency for a few recording lengths;
- early user quotes or usage stories.

Priority 2:

- a factual comparison page with dated sources;
- a privacy/data-flow graphic;
- an Open Graph image and small brand kit;
- a decision on English-only versus localized landing pages.

## Claims Policy

Do not publish `3x faster`, `5x faster`, `99% accurate`, `perfect`, `private`,
or `works in every app` without a documented HoldType-specific method and the
necessary qualifications.

Do not turn the current transcription model into a marketing claim. The landing
page may name it once in subdued technical copy and may link to OpenAI's own
model documentation. Do not claim that a competitor uses `whisper-1` or an
older Whisper model unless the competitor publishes that fact.

Do not describe 100 dictations as a daily maximum or typical usage, claim that
HoldType is always cheaper than a flat subscription, say that free and paid
competitor tiers use different recognition quality, or suggest that competing
providers deliberately reduce quality. Cost examples must name the reviewed
provider rate, recording duration, and excluded optional requests in the
detailed cost section; the hero may use the approved rounded example backed by
that explanation. Quality preference must not become a model slogan unless a
reproducible HoldType benchmark exists.

Prefer claims that are already observable:

- native macOS app;
- own OpenAI API key;
- no HoldType account or subscription;
- audio sent to OpenAI for transcription;
- optional separate correction and translation requests;
- local Keychain, settings, recovery, and recording-cache controls;
- source available for inspection.

## First Measurement Pass

The landing page can be validated without adding telemetry to the app. Start
with GitHub release-download counts, direct feedback, and a small set of
permissioned user interviews. Measure the page itself only if a separate,
privacy-conscious website analytics decision is made.
