# Releasing

A release is a disk image with the app, signed with a Developer ID certificate and notarized by
Apple, attached to a GitHub release. The Mac App Store is not an option: it requires the App
Sandbox, in which the app can reach neither the desktop app's helper nor its socket (see
[desktop-integration.md](desktop-integration.md)).

## Cutting a release

```sh
just release X.Y.Z
```

opens a pull request that sets the version in `Bundle/Info.plist`. Merging it starts
`.github/workflows/release.yml`. The workflow can also be started by hand (Actions → release → Run
workflow), which releases the version currently on `main`: that is how the first release is cut and
how a failed one is tried again. A version that already has a release is never released twice.

The workflow does:

1. `scripts/release.sh`, on GitHub's macOS runner:
   - creates a keychain for the run and fetches the Developer ID certificate into it with
     `fastlane match`, read-only;
   - builds and signs the app (`scripts/bundle-app.sh`), has Apple notarize it with `notarytool`
     and staples the ticket;
   - packs the app into a disk image (`scripts/make-disk-image.sh`), signs the image and has it
     notarized and stapled as well;
   - deletes the keychain and the notarization key again.
2. A build provenance attestation for the disk image.
3. The GitHub release `vX.Y.Z` on the merged commit, with the disk image and generated notes.

The build is for Apple silicon only.

## The Homebrew tap

The cask lives in [lifo9/homebrew-tap](https://github.com/lifo9/homebrew-tap). Once a day a
workflow there looks at the newest release here and moves the cask to it;
`gh workflow run update.yml --repo lifo9/homebrew-tap` does so at once. Nothing in this
repository takes part, and the tap needs no secret.

The tap passes on only a disk image whose provenance attestation says it was built by
`.github/workflows/release.yml` from `main` on a GitHub runner, and it expects a tag of the form
`vX.Y.Z` with exactly one disk image. Renaming the workflow file or the branch, or changing what
a release carries, means changing `scripts/update-cask.sh` in the tap with it.

## One-time setup

**The certificate.** A "Developer ID Application" certificate can only be created by the account
holder of the Apple Developer team, signed in with the Apple ID; an App Store Connect API key
cannot create it. Create it once, into the `match` repository, from a Mac:

```sh
MATCH_GIT_URL=<the match repository> \
MATCH_TYPE=developer_id MATCH_PLATFORM=macos MATCH_SKIP_PROVISIONING_PROFILES=true \
MATCH_APP_IDENTIFIER=<the bundle identifier of an app the team has registered> \
    bundle exec fastlane match
```

`match` asks for the Apple ID and for the passphrase of the repository. The app uses no capability
that needs a provisioning profile, so none is created.

The identifier is not this app's: whenever `match` may create something it first checks that the
App ID exists in the developer portal, also with profiles skipped, and this app has none there,
since only a provisioning profile would need one. The certificate belongs to the team, not to an
App ID, so any registered one will do. The release runs `match` read-only, which does not ask
the portal.

Run it through `bundle exec`, which uses the fastlane version the lock file pins. Signing in with
an Apple ID needs fastlane 2.240.0 or later: Apple removed the endpoint older versions use for
it, and they fail with "Service key is empty". Without a Ruby at hand:
`BUNDLE_PATH=vendor/bundle nix shell nixpkgs#ruby -c sh -c 'bundle install && bundle exec fastlane match'`,
with the variables above.

**The secrets** belong to the `release` environment of the repository (Settings → Environments),
which only jobs running from `main` can use:

| Secret                          | Content                                                       |
| ------------------------------- | ------------------------------------------------------------- |
| `MATCH_GIT_URL`                 | HTTPS address of the `match` repository                       |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `user:token` with read access to that repository              |
| `MATCH_PASSWORD`                | Passphrase the `match` repository is encrypted with           |
| `APPLE_KEY_ID`                  | Id of an App Store Connect API key, used for notarization     |
| `APPLE_ISSUER_ID`               | Issuer id of that key                                         |
| `APPLE_KEY_CONTENT`             | The key's `.p8` file, Base64 encoded                          |
| `TEMP_KEYCHAIN_PASSWORD`        | Password for the keychain created for the run; any value      |

## Trying the packaging locally

`scripts/bundle-app.sh && scripts/make-disk-image.sh` builds the same disk image signed ad hoc.
It runs on the Mac that built it; elsewhere Gatekeeper refuses it, which is what the Developer ID
signature and the notarization are for. `scripts/release.sh` needs the secrets above.
