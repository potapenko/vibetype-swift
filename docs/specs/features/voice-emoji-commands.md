# Voice Emoji Commands

## Goal

Let users dictate common emoji through short spoken commands without adding a
separate editing or text-expansion product.

## Scope

- Built-in emoji command sets.
- A visible command catalog for each built-in set.
- User-authored custom emoji commands.
- Dictionary settings for enabling emoji commands and command-set languages.
- OpenAI transcription prompt hints for active command sets.
- Local post-transcription replacement of recognized commands.
- Handoff of emoji-expanded text to transcript history, Last Result, and
  automatic insertion.

## Non-goals

- Full Unicode emoji search or emoji picker behavior.
- Replacing ordinary words such as `smile` without an explicit command prefix.
- Cloud-synced command sets.
- A second OpenAI request for emoji expansion.

## User-visible behavior

- Settings should expose emoji commands inside Dictionary, not as a separate
  Settings navigation item.
- Emoji commands are controlled by one top-level toggle.
- When enabled, users choose one active built-in command set from the language
  tabs. The default active set is English.
- Dictionary should show the supported emoji commands in a compact tabbed
  catalog. Built-in tabs are English, Russian, Spanish, German, French, and
  Portuguese. A Custom tab lets users add their own emoji commands.
- Each built-in tab should show the emoji, primary spoken command, and supported
  aliases so users can discover the exact phrases without reading docs.
- The Custom tab should let users add an emoji output, a primary spoken command,
  and optional aliases. Custom commands may be enabled, disabled, or removed
  without affecting built-in sets.
- English commands use an explicit `emoji` prefix, such as `emoji smile`.
- Russian commands use the explicit `эмодзи` prefix, such as `эмодзи улыбка`.
- Built-in command prefixes must use the canonical emoji term for the selected
  language set. Ordinary translated words such as `эмоции` must not trigger
  emoji replacement.
- Selecting a built-in language tab makes that set active for both local emoji
  replacement and OpenAI transcription prompt hints.
- Selecting the Custom tab disables built-in command-set hints while keeping
  enabled custom commands active.
- Custom commands are active only when emoji commands are enabled and the custom
  row itself is enabled.
- Known commands are replaced locally with their configured emoji after a
  successful accepted transcript.
- Unknown commands remain dictated text.
- The app must not replace unprefixed ordinary words, so `I like your smile`
  remains normal text.
- Repeated commands should each be replaced.
- Punctuation next to a command should be preserved.
- Punctuation or whitespace between command words should not break a known
  command, so `эмодзи, смайл` and `emoji. smile` may still produce emoji.
- Known commands should work inline inside a longer dictation without requiring
  the user to stop and start recording around the emoji phrase.
- Last Transcript, transcript history, Last Result, and automatic
  insertion receive the final emoji-expanded text.

## Invariants

- Emoji replacement is local and must not make an additional OpenAI request.
- Default logs must not include raw transcript text, command input, prompt
  contents, or replacement output.
- Built-in emoji prompt hints are app-owned transcription hints. They must not
  appear as user-authored custom dictionary rows.
- Command matching must be case-insensitive where the writing system supports
  case.
- Emoji command matching must use word-token boundaries rather than broad
  substring replacement.
- Matching must prefer the longest known command phrase when aliases overlap.
- User-authored custom emoji commands take precedence over built-in commands
  when the same spoken phrase is configured in both places.
- User replacement rules run after built-in emoji command replacement so users
  can still customize final output.

## Route / state / data implications

Persistence is platform-owned:

- The macOS compatibility facade may continue to store the emoji-command
  enabled state, the optional selected built-in command-set identifier, and
  user-authored custom commands in its existing `UserDefaults` keys.
- On iOS, those same values are canonical app-private Library v1 content under
  `ios-settings-and-secret-storage.md`; they are never stored in
  `UserDefaults` or the App Group.
- The persisted built-in selection contains zero or one built-in identifier.
  English is selected by default. No selected built-in identifier represents
  the Custom tab and does not disable otherwise enabled custom commands.
- Built-in command catalogs are bundled app-owned data and are not copied into
  either persistence store.

The built-in command catalog should include these common emoji across every
built-in language set:

- ❤️, 😂, 🤣, 👍, 😭, 🙏, 😘, 🥰, 😍, 🙂, 😠, ✅, ❌, 🔥, ✨, 🥹, 👀, 💀, 🫶, 🫠, 💔.

The first supported built-in language sets are English, Russian, Spanish,
German, French, and Portuguese. Japanese and Chinese command sets are deferred
until there is dedicated dictation QA for those scripts.

## Verification mapping

- App settings tests should cover defaults, persistence, and prompt hint
  inclusion for enabled built-in and custom command sets.
- Local post-processing tests should cover English commands, Russian commands,
  custom commands, disabled commands, unknown commands, repeated commands,
  punctuation-tolerant inline matching, and user replacement rules running
  after emoji replacement.
- Settings presentation tests should cover the Dictionary placement if a stable
  UI test surface is added later.

## Unknowns requiring confirmation

- Whether the default selected built-in command set should follow the selected
  transcription language after dedicated dictation QA.
