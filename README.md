<p align="center">
  <img alt="HoldType app icon" src="docs/readme-assets/app-icon.png" width="116">
</p>

<h1 align="center">HoldType</h1>

<p align="center">
  <strong>Speak the whole thought. HoldType puts it where you're working.</strong>
</p>

<p align="center">
  Native macOS voice input for long AI prompts, messages, docs, and notes.<br>
  By default, hold <kbd>Right Command</kbd>, speak, and release. HoldType
  transcribes through your own OpenAI API key and inserts the accepted text at
  the cursor in most Mac apps.
</p>

<p align="center">
  <a href="https://github.com/holdtype/holdtype-swift/releases/latest"><strong>Download for macOS</strong></a>
  |
  <a href="#how-it-works">See how it works</a>
  |
  <a href="#privacy">Privacy</a>
  |
  <a href="#development">Build from source</a>
</p>

<p align="center">
  <sub>macOS 14 Sonoma or newer · Free app · No HoldType subscription · OpenAI API usage billed directly</sub>
</p>

<p align="center">
  <img alt="HoldType recording and transcribing indicator states" src="docs/readme-assets/indicator-states.png" width="920">
  <br>
  <sub>The optional floating indicator shows when HoldType is listening or transcribing without taking focus from the active app.</sub>
</p>

## How It Works

1. Add an OpenAI API key once. HoldType stores it locally in macOS Keychain.
2. Place the cursor in the Mac app where the text should go.
3. With the default shortcut, hold <kbd>Right Command</kbd> and speak. Release
   the key when the thought is complete.
4. HoldType transcribes the recording and inserts the accepted text at the
   cursor.

Translation has its own shortcut. With its default shortcut, choose a target
language in Settings, then hold <kbd>Right Command</kbd> +
<kbd>Right Option / Alt</kbd> to speak in one language and insert the result in
another.

<p align="center">
  <img alt="HoldType menu bar popover with transcribe, translate, paste, history, settings, and quit actions" src="docs/readme-assets/menu-popover.png" width="520">
</p>

## Where It Fits

- **AI work:** give Codex, Claude, or ChatGPT the context that is easy to skip
  when a prompt has to be typed line by line.
- **Everyday writing:** dictate mail, reviews, documentation, chats, and notes
  without moving the text through a separate editor.
- **Bilingual work:** speak in the language where the thought comes naturally
  and insert the result in the configured target language.

## What Makes It Different

### Stays Where You Work

Hold the shortcut, speak, and release. HoldType returns the accepted text to
the cursor in the Mac app already in front of you, without asking you to move
the draft through a separate editor or browser tab.

The app is written in Swift, lives in the menu bar, and keeps the recording
path close to macOS. Its source is available for inspection, including the
paths that record audio, send OpenAI requests, store local settings, and hand
text back to the active app.

### Your OpenAI Account, One Focused Path

HoldType sends requests through your OpenAI Platform account. OpenAI deducts
API usage from that account; HoldType has no recurring fee and does not meter
dictation through a separate product account.

HoldType is OpenAI-only by design and starts with `gpt-4o-transcribe`. You do
not have to compare providers or download local models before the first
dictation. Advanced model, language, prompt, and nearby-context settings remain
available when you want them.

### Vocabulary And Translation For Real Work

Dictionary entries are stored locally and added to the transcription prompt as
spelling context. They help with project names, file names, product terms, and
people's names that a general transcription model may miss.

<p align="center">
  <img alt="HoldType custom dictionary words and phrases" src="docs/readme-assets/settings-dictionary.png" width="820">
</p>

Translation runs only when requested from its shortcut or the menu action. It
takes the accepted transcript, translates it into the configured target
language, and inserts that result into the active app. The translation is a
separate OpenAI request.

<p align="center">
  <img alt="HoldType translation settings with Right Command plus Right Option or Alt and English target language" src="docs/readme-assets/settings-translation.png" width="820">
</p>

## Workflow Details That Matter

- **Optional minimal correction.** OpenAI correction is off by default. When
  enabled, it makes a second model request with a prompt that asks for small
  fixes to transcription, spacing, capitalization, and punctuation. Local
  typography cleanup can run without another API call.
- **Spoken emoji commands.** Explicit phrases such as `emoji heart`,
  `emoji laugh`, or `emoji thumbs up` can be replaced locally after
  transcription. Ordinary words are left alone.
- **A way back when insertion fails.** HoldType can keep the last accepted text
  as Last Result and insert it with <kbd>Control</kbd> + <kbd>Command</kbd> +
  <kbd>V</kbd>, without replacing the macOS system clipboard.

## What It Costs

HoldType has no subscription. OpenAI deducts API usage from the Platform
account connected through your key; new API accounts may require prepaid
credit.

At OpenAI's current estimated `gpt-4o-transcribe` rate, about **$0.10 covers 100
quick dictations**—roughly 17 minutes of recorded speech in total. Repeat the
same daily total for 30 days and the estimated transcription cost is about $3.
This is an illustration, not a usage cap or claim about typical behavior.

The Billing screen estimates successful audio transcriptions made on this Mac.
It does not include correction or translation requests, and it is not an
OpenAI invoice, balance, or account dashboard. Current model rates live on the
[OpenAI pricing page](https://developers.openai.com/api/docs/pricing), and new
accounts may use [prepaid billing](https://help.openai.com/en/articles/8264778-what-is-prepaid-billing).

<p align="center">
  <img alt="HoldType local OpenAI usage estimate with projected 30-day cost" src="docs/readme-assets/settings-billing.png" width="820">
</p>

## Privacy

HoldType keeps the product boundary explicit:

- The OpenAI API key is stored in macOS Keychain.
- Audio is sent to OpenAI when a recording is transcribed.
- Optional OpenAI correction sends transcript text in a second request.
- Translation sends transcript text in a separate request when translation is
  requested.
- Nearby text context is optional and limited to a short excerpt near the
  active cursor.
- Completed audio is not retained by default. A recoverable failed attempt may
  keep bounded session-only audio for Retry when recovery history is enabled.
  Optional recording-cache retention is local and user-controlled.
- Transcript recovery is local and session-only. Last Result does not use the
  macOS system clipboard.
- HoldType has no account system, server-side app state, analytics, telemetry,
  or cloud sync.

## Why I Built HoldType

Typing speed was not the problem for me. The problem was how often a long
prompt, review, or explanation became shorter before I finished typing it.
Speaking made it easier to include the full thought.

I tried Wispr Flow, OpenWhispr, Codex voice input, local Whisper models, and
other provider setups. They solve different problems. In my daily work, OpenAI
transcription gave me the first pass I trusted most often.

I wanted a narrower setup: one provider, a sensible default, direct API
billing, and no product subscription to remember. HoldType is the native Swift
menu bar app I wanted around that choice.

HoldType has also been built through Codex, directed and tested with the same
voice-first workflow it is meant to support.

<p align="center">
  <img alt="Personal microphone setup used for daily HoldType dictation" src="docs/readme-assets/workflow-microphone.jpg" width="760">
  <br>
  <sub>The microphone on my desk. HoldType uses the Mac's available audio input and does not require special recording hardware.</sub>
</p>

## Install

### GitHub Release

1. Download `HoldType-<version>.dmg` from the
   [latest GitHub Release](https://github.com/holdtype/holdtype-swift/releases/latest).
2. Open the disk image and drag `HoldType.app` into Applications.
3. Launch HoldType and grant the macOS permissions needed for microphone
   recording, the global shortcut, and active-app insertion.
4. Add an OpenAI API key in Settings.

### Homebrew Tap

The project-owned Homebrew tap installs the same disk image published on GitHub
Releases:

```sh
brew tap holdtype/tap && brew trust holdtype/tap && brew install --cask holdtype && open -a HoldType
```

## Platform

HoldType currently supports macOS 14 Sonoma and newer. This repository contains
the native macOS version.

<p align="center">
  <a href="https://github.com/holdtype/holdtype-swift/releases/latest"><strong>Download HoldType for macOS</strong></a>
  <br>
  <sub>Free app · No HoldType subscription · OpenAI API usage billed directly · macOS 14+</sub>
</p>

## License

HoldType is source-available under the Functional Source License 1.1 with an
MIT future license.

You may read, learn from, modify, build, and run HoldType from source for
personal or internal use, including inside a company, for security review,
internal evaluation, or private daily use.

The license is meant to prevent competing products, commercial repackaging, and
misuse of the HoldType brand. During the license period, you may not build,
distribute, sell, host, or provide a competing voice typing, dictation,
transcription, or text insertion product based on this code.

Each released version converts to the MIT License two years after its release.

See [LICENSE](LICENSE) for the full terms.

## Brand

The HoldType name, logo, icon, domain, screenshots, and visual identity are not
licensed for use in forks or derivative products.

Forks and derivative builds must use a clearly different name and must not
imply that they are official HoldType releases.

The official source and release page is
[github.com/holdtype/holdtype-swift](https://github.com/holdtype/holdtype-swift).

## Development

This repository is spec-first. Product behavior lives under `docs/specs/`,
while agent workflow rules live in `AGENTS.md`.

The working product-site brief lives in
[docs/marketing/landing-page-plan.md](docs/marketing/landing-page-plan.md).

For code work:

1. Read `AGENTS.md`.
2. Read `docs/agent-onboarding.md`.
3. Open `HoldType.xcodeproj` from the repository root.
4. Read `SWIFT.md` before Swift, SwiftUI, AppKit, Xcode project, or test
   changes.
5. Read `docs/specs/README.md` and `docs/specs/index.md` before behavior
   changes.

The current product focus is the native macOS menu bar app. iOS keyboard work
is future scope unless a task explicitly opts into it.
