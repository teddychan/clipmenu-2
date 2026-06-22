# ClipMenu 2

A modern macOS clipboard-history menu-bar app, written in Swift 6. It lives in
`app/` as a SwiftPM executable that runs as a menu-bar agent (no Dock icon).

## Features
- Clipboard history shown in a menu popped at the cursor or from the menu bar.
- Text snippets organized in folders.
- JavaScript text "Actions" (case, trim, HTML, Base64, hashing, Japanese
  conversions, and more).
- Image thumbnails in the menu, numbered items, and tooltips.
- Global hotkeys (Carbon) and paste synthesis into the frontmost app
  (requires Accessibility permission).
- Settings window (General / Menu / Type / Action / Shortcuts), persisted via
  `UserDefaults`; history and snippets stored via SwiftData.

## Requirements
- Current macOS and a Swift 6 toolchain (Xcode or the Command Line Tools).

## Build & run
```bash
cd app
swift build
./scripts/run.sh        # assembles a .app bundle and launches it
```
Use `scripts/run.sh` rather than `swift run`: it builds, assembles
`.build/ClipMenu.app` (an `LSUIElement` agent), code-signs it, and launches it.
The status-bar icon and agent behavior only work from inside a `.app` bundle.

### First-run notes (Accessibility & signing)
- Pasting into the frontmost app needs Accessibility (TCC) permission — grant
  the app under System Settings ▸ Privacy & Security ▸ Accessibility.
- To keep that grant across rebuilds, create a stable self-signed
  "ClipMenu Dev" code-signing certificate (Keychain Access ▸ Certificate
  Assistant). Otherwise `run.sh` ad-hoc signs and the grant resets each build.

## Tests
```bash
cd app && swift test
```

## Project layout
- `app/` — the Swift app (sources, tests, bundled resources, `scripts/`).
- `CLAUDE.md` — how to work on this repo with Claude Code.
- `app/CLAUDE.md` — Swift engineering conventions.
- `docs/archive/` — historical docs from the original legacy-parity rebuild
  phase. Kept for reference only; their `/legacy` citations refer to a checkout
  that is not part of this repo.

## Fun fact
My first clipboard mangaer is CLCL
https://nakka.com/soft/clcl/index_eng.html#google_vignette

<img width="600" height="411" alt="image" src="https://github.com/user-attachments/assets/11cdd6d1-329f-40da-8127-76decbbba41f" />


## License
MIT — see [LICENSE](LICENSE).

## Credits
Based on the original [ClipMenu](https://github.com/naotaka/ClipMenu) by
Naotaka Morimoto, used under the MIT License.
