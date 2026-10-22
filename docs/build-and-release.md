# Build and release

## Signing and notarization

`create-app.sh` signs with the team's Developer ID Application identity when
the keychain has it (hardened runtime, the camera entitlement in
`WatchMeSleep.entitlements`, and with `RELEASE=1` a secure timestamp); without
it the bundle is signed ad hoc and camera access re-prompts after every
rebuild. `RELEASE=1 ./create-app.sh && ./notarize.sh` notarizes, staples, and
writes the release zip.

`./create-app.sh` produces `Watch Me While I Fall Asleep Dev.app`, with `Dev`
in both bundle name fields and the separate
`com.wiltodelta.watchmesleep.dev` identifier. This distinguishes it from the
release in Privacy & Security, Login Items, and other macOS app lists.
`RELEASE=1` produces **Watch Me While I Fall Asleep.app** with the release
identifier. CI branch builds use `./notarize.sh --zip-only` to package the Dev
bundle under the existing versioned zip filename; this mode does not notarize
or publish it.

## Release process

A pushed annotated `vX.Y.Z` tag runs `.github/workflows/build.yml`: lint and
tests, a temporary keychain with the Developer ID identity and the notarytool
profile, `RELEASE=1 ./create-app.sh`, `./notarize.sh`, then the Sparkle
`appcast.xml` (this release only, EdDSA-signed, with the tag body embedded as
Markdown release notes), and the GitHub Release with the zip, the appcast, the
tag's first line as its title and its body as the notes. CI refuses a
lightweight tag, one without a body, and one that is not `vX.Y.Z` or not above
every earlier tag: Sparkle offers only a higher version, so a lower number
never reaches anybody on the newer release (3.6.1 after 3.7, fixed by 3.7.1).

The repository secrets it reads are `DEVELOPER_ID_P12_BASE64`,
`DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`,
`NOTARY_ISSUER_ID`, and `SPARKLE_PRIVATE_KEY`. Only tag builds read them;
GitHub never passes them to pull requests from forks, and branch builds stay
ad hoc. Their source is the 1Password item "Apple Developer ID: Victor
Kuznetsov (K2GT9Q4S6U)" (Private vault), which also holds the restore commands
and the Sparkle key; the Developer ID certificate expires on 2031-09-17.

## Sparkle

`Updater` (the same file as translate-like-me's and rota's) runs `SPUStandardUpdaterController`
with gentle reminders. `create-app.sh` copies `Sparkle.framework` into
`Contents/Frameworks`, adds the `@executable_path/../Frameworks` rpath, removes
its XPC services (they exist for sandboxed apps), ships its MIT license, and
signs `Autoupdate`, `Updater.app`, the framework and the app in that order. One
EdDSA key serves every app of the team; `SUPublicEDKey` in `create-app.sh` is
its public half, and `SURequireSignedFeed` makes the app reject a feed that is
not signed with it.

## Bundle identifier

`com.wiltodelta.watchmesleep` is registered as an explicit App ID for team
K2GT9Q4S6U. Keep it: the Camera grant, the settings and the login item are
keyed to it.

## Verify a release

```bash
gh release download vX.Y.Z -p "*.zip" -D /tmp/asset-check && \
  ditto -x -k /tmp/asset-check/*.zip /tmp/asset-check/app && \
  spctl -a -vv "/tmp/asset-check/app/Watch Me While I Fall Asleep.app" && \
  xcrun stapler validate "/tmp/asset-check/app/Watch Me While I Fall Asleep.app"
```
