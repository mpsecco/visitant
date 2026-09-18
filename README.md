# Visitant

Visitant is an experimental native macOS teleprompter overlay for screen demos. It
shows a small translucent, "click-through" transcript window on your screen while
staying out of tab recordings.

It is a Swift Package executable, with an optional Xcode project for building the
bundled `.app`. The overlay uses `NSWindow` and SwiftUI, and requires macOS 14 or
newer.

## Features

- Click-through floating overlay for demo scripts and talking points
- Markdown transcript format with optional per-step timers
- Global hotkeys for play, pause, next, previous, restart, hide, and move mode
- Adjustable transparency from the menu bar
- Recent transcript menu using sandbox-safe security-scoped bookmarks
- Best-effort whole-screen capture exclusion toggle

## Quick Start

You need the Xcode Command Line Tools (`xcode-select --install`); full Xcode is
not required.

```sh
git clone https://github.com/distantfield/visitant.git
cd visitant
make
```

`make` builds a release binary and opens the demo transcript. To use your own:

```sh
make run FILE=path/to/talk.md
```

Visitant lives in the menu bar (no Dock icon); quit with `Ctrl` + `Option` + `Q`.

### Prebuilt App

Unsigned app zips are published from version tags on
[GitHub Releases](https://github.com/distantfield/visitant/releases). Because
they are not Developer ID signed or notarized, macOS will show a Gatekeeper
warning the first time you open the app.

## Transcript Format

Transcripts are Markdown files. List items become steps; optional timer markers
auto-advance a step after the requested duration.

```markdown
- Open the search bar [3s]
- Type "hello world" [5s]
- Wait for results to load [1m]
- Click the first result [30s]
- Static lines without a timer wait for manual next
```

Supported timer units are `s` for seconds and `m` for minutes. Blank lines,
headings, comments, and non-list text are ignored.

## Hotkeys

| Hotkey | Action |
| --- | --- |
| `Ctrl` + `Option` + `Space` | Play / pause |
| `Ctrl` + `Option` + `Right` | Next step |
| `Ctrl` + `Option` + `Left` | Previous step |
| `Ctrl` + `Option` + `R` | Restart |
| `Ctrl` + `Option` + `H` | Hide / show |
| `Ctrl` + `Option` + `M` | Toggle move mode |
| `Ctrl` + `Option` + `C` | Toggle screen-capture exclusion |
| `Ctrl` + `Option` + `Q` | Quit |

## Repositioning

The window is click-through and borderless by default. To move or resize it:

1. Press `Ctrl` + `Option` + `M`.
2. Drag the window background to move it, or drag the bottom-right handle to resize it.
3. Press `Ctrl` + `Option` + `M` again to return to click-through mode.

## Screen Recording Behavior

Chrome tab capture, such as `getDisplayMedia({ video: { chromeMediaSource:
"tab" } })`, composites the tab content rather than every OS window on top of
Chrome. Visitant is a separate macOS window, so it appears on your screen but
does not appear in the tab recording.

Whole-screen sharing or recording is different. Visitant can ask macOS to exclude
the overlay using `NSWindow.sharingType = .none`, exposed through the "Hide From
Screen Capture" menu item, but that is best-effort behavior. Test the exact
macOS, browser, meeting, and recording setup before relying on it.

## Development

```sh
make test                       # run the test suite
swift run Visitant demo/demo.md # debug build and run
```

Open `Visitant.xcodeproj` in Xcode to work on the bundled `.app`: bundle
metadata, entitlements, the app icon, and release builds. Release instructions
live in [docs/releasing.md](docs/releasing.md).

## Privacy

Visitant reads local transcript files selected by the user and stores recent-file
bookmarks in `UserDefaults`. It does not intentionally send network requests,
collect analytics, or upload transcript contents.

## License

Visitant is released under the MIT License. See [LICENSE](LICENSE).
