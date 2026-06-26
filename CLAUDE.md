# ClipMenu 2 (free build)

macOS clipboard-history menu-bar app. The app source and dev guidelines live in
`app/` — see [`app/CLAUDE.md`](app/CLAUDE.md). This public repo is the free,
open-source build; the Mac App Store variant is built separately.

## Release
Tag `vX.Y.Z` → CI builds, signs (Developer ID), notarizes, publishes the binary
here, pushes the Sparkle appcast to www.dragonapp.com, and bumps the Homebrew
cask. (Owner Claude sessions: the shared build/sign/release SOP is in the
`dragon-mac-ops` skill.)
