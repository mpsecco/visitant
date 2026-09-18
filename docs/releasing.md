# Releasing

Visitant's first-phase GitHub releases publish unsigned macOS app zips. This
keeps release automation simple while the Apple Developer ID signing and
notarization setup is still pending.

## Create a Release

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
   `Visitant.xcodeproj` when the app version changes.
2. Make sure CI is passing.
3. Create and push a version tag:

   ```sh
   git tag v1.0.0
   git push origin v1.0.0
   ```

4. The `Release` workflow will build `Visitant.app`, package
   `Visitant-<version>-macos-unsigned.zip`, generate a SHA-256 checksum, and
   upload both files to the GitHub Release.

## Current Limitations

The release zip is unsigned and not notarized. Users should expect macOS
Gatekeeper warnings when opening the downloaded app. This is acceptable for the
first phase, but public end-user releases should move to Developer ID signing and
notarization.

## Future Signed Releases

The next release phase should:

- Import a Distant Field Labs Developer ID Application certificate in GitHub Actions.
- Build with hardened runtime and the existing entitlements.
- Submit the zip to Apple notarization with `xcrun notarytool`.
- Staple the notarization ticket before packaging the final artifact.
