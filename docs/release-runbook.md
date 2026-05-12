# Release Runbook

## One-time setup

1. **Apple Developer Account** — $99/yr, your team ID needed.
2. **Developer ID Application certificate** — Export from Keychain as `.p12`, base64-encode.
3. **App Store Connect API key** — Generate with `notarytool` permission, download `.p8`.
4. **Sparkle EdDSA private key** — Generated during Plan #11 implementation (see below). Keep `JubqNWmSAg370RpANzQRzHGpFSMTH4o6RnKWsK12jX8=` as your `SPARKLE_PRIVATE_KEY` secret and `SkLvM/Bko2VBmPvl3Nj/zt6qOTes7I6HPQxFizIwzq4=` as your `SPARKLE_PUBLIC_KEY` secret. The public key is already embedded in `FreeDroid/Info.plist` and `Resources/sparkle-public-key.pem`.

## GitHub Secrets to configure

| Secret | Source |
|---|---|
| `SIGNING_CERT_P12` | base64 of exported `.p12` (no newlines): `base64 -i cert.p12 | tr -d '\n'` |
| `SIGNING_CERT_PASSWORD` | Password for the `.p12` |
| `SIGNING_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `DEVELOPMENT_TEAM` | Your Apple Developer Team ID (10 chars) |
| `NOTARY_KEY_ID` | App Store Connect key ID |
| `NOTARY_ISSUER_ID` | App Store Connect issuer ID |
| `NOTARY_PRIVATE_KEY` | Contents of the `.p8` file |
| `SPARKLE_PRIVATE_KEY` | Contents of Sparkle's private key file (see one-time setup above) |
| `SPARKLE_PUBLIC_KEY` | `SkLvM/Bko2VBmPvl3Nj/zt6qOTes7I6HPQxFizIwzq4=` |
| `HOMEBREW_GITHUB_TOKEN` | Personal access token with `homebrew/cask` write |

## Apple entitlement requests

Email Apple Developer Support to request:
- `com.apple.developer.fskit.fsmodule` for your team

This is required for the FSKit extension to load in macOS 15.4+.

## Regenerating the Sparkle keypair (if needed)

If the private key is ever lost, generate a new one:

```bash
# Build generate_keys from the Sparkle SPM checkout
SPARKLE_CHECKOUT=$(find ~/Library/Developer/Xcode/DerivedData -path "*/checkouts/Sparkle" -type d 2>/dev/null | head -1)
xcodebuild -project "$SPARKLE_CHECKOUT/Sparkle.xcodeproj" \
  -scheme generate_keys -configuration Release \
  -derivedDataPath /tmp/sparkle-build CODE_SIGNING_ALLOWED=NO build

# Generate new keypair (stored in Keychain automatically)
/tmp/sparkle-build/Build/Products/Release/generate_keys

# Export private key
/tmp/sparkle-build/Build/Products/Release/generate_keys -x /tmp/sparkle-private.pem
cat /tmp/sparkle-private.pem  # add this as SPARKLE_PRIVATE_KEY secret

# Get public key
/tmp/sparkle-build/Build/Products/Release/generate_keys -p
# Paste the output into Info.plist SUPublicEDKey and as SPARKLE_PUBLIC_KEY secret
```

Note: After rotating keys, update `FreeDroid/Info.plist` `SUPublicEDKey` and re-release. Old builds will fail signature validation against the new key.

## Cutting a release

1. Ensure all PRs are merged and CI is green.
2. Bump `MARKETING_VERSION` in `project.yml` if not using release-please bot (or let the bot open a version bump PR).
3. Push a tag: `git tag v0.x.y && git push origin v0.x.y`.
4. GitHub Actions runs the release workflow: builds, signs, notarizes, packages, publishes.
5. The Homebrew Cask workflow opens a PR to homebrew/homebrew-cask on release.
6. Review the cask PR and merge once CI is green on the homebrew side.

## Verifying the release

After the release workflow completes:

- Download the DMG from the GitHub release.
- Mount and install: `hdiutil attach FreeDroid-x.y.z.dmg`.
- Check code signature: `codesign --verify --verbose FreeDroid.app`.
- Check notarization: `xcrun stapler validate FreeDroid.app`.
- Launch the app and confirm "Check for Updates…" appears under the application menu.
- Verify `docs/appcast.xml` on the `main` branch contains the new `<item>` entry.

## Troubleshooting

### Notarization fails

- Ensure hardened runtime is enabled (`ENABLE_HARDENED_RUNTIME = YES` in project.yml).
- Check that `FreeDroid.entitlements` does not contain entitlements that require provisioning profiles.
- Run `xcrun notarytool log <submission-id>` for detailed rejection reasons.

### Sparkle update not detected

- Confirm `SUFeedURL` in Info.plist points to the live `appcast.xml` URL.
- Confirm `SUPublicEDKey` matches the `SPARKLE_PUBLIC_KEY` used to sign the appcast item.
- Check `SUEnableAutomaticChecks` is `true` in Info.plist.

### FSKit extension not loading

- The `com.apple.developer.fskit.fsmodule` entitlement requires explicit Apple approval.
- Email `developer-provisioning@apple.com` with your Team ID and use case.
- Until approved, the extension will silently fail to load on user devices.
