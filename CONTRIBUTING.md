# Contributing

Thanks for taking a look at Visitant.

## Development

Visitant is a Swift Package executable with an optional Xcode app target.

```sh
make test   # run the test suite
make        # build and run with the demo transcript
```

Use Xcode when you want to work on the bundled `.app` target, app icon, entitlements,
or privacy manifest.

## Pull requests

- Keep changes focused and small enough to review comfortably.
- Add or update tests when changing parser or playback behavior.
- Run `make test` before opening a pull request.
- Avoid committing local Xcode state, derived data, or generated build products.

## Reporting issues

When filing a bug, please include:

- macOS version
- How you launched Visitant: `make`, `swift run`, or the Xcode-built app
- The transcript snippet that reproduces the issue, if parser-related
- Whether the issue happens during tab capture, whole-screen capture, or normal use
