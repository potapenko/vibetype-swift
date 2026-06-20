# References

This directory stores source material used as behavior evidence for the native
Swift rewrite.

## OpenWhispr

`openwhispr-main/` is a copied reference implementation from:

```text
/Users/eugenepotapenko/Downloads/openwhispr-main
```

It is kept to study behavior, not architecture. The target VibeType app remains
a native macOS Swift/SwiftUI application without Electron, React, Node.js
runtime, accounts, subscriptions, telemetry, cloud sync, local model
downloaders, semantic notes, meeting transcription, or updater scope in the
MVP.

Useful reference areas:

- hotkey activation;
- recording lifecycle;
- active-app paste behavior;
- settings and permission states;
- recording/transcribing/done/error UI states;
- small macOS helper experiments under `resources/macos-*.swift`.

When importing behavior from this reference, first preserve it as a product
spec under `docs/specs/`, then implement the native Swift version against that
spec.
