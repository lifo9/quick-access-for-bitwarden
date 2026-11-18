# Releasing

A release is a disk image with the app, signed with a Developer ID certificate and notarized by
Apple, attached to a GitHub release. The Mac App Store is not an option: it requires the App
Sandbox, in which the app can reach neither the desktop app's helper nor its socket (see
[desktop-integration.md](desktop-integration.md)).

## Cutting a release

```sh
just release X.Y.Z
```

writes the version into `Bundle/Info.plist`, commits it as `chore(release): vX.Y.Z`, tags the
commit `vX.Y.Z` and pushes both. The tag starts `.github/workflows/release.yml`, which on GitHub's
macOS runner:

1. checks that the tag is the version in `Bundle/Info.plist`;
2. runs the `mac release` lane of `fastlane/Fastfile`, which
   - fetches the Developer ID certificate with `match` into a keychain made for the run,
   - builds and signs the app (`scripts/bundle-app.sh`), has it notarized and staples the ticket,
   - packs it into a disk image (`scripts/make-disk-image.sh`), signs the image and has it
     notarized and stapled as well;
3. creates the GitHub release for the tag with the disk image and generated notes.

The build is for Apple silicon only.

## One-time setup

**The certificate.** A "Developer ID Application" certificate can only be created by the account
holder of the Apple Developer team, signed in with the Apple ID; an App Store Connect API key
cannot create it. Create it once, into the `match` certificates repository, from a Mac:

```sh
FASTLANE_CERTIFICATES_REPO_URL=<the certificates repository> \
    bundle exec fastlane match developer_id --platform macos --skip_provisioning_profiles \
    --app_identifier dev.filo.quick-access-for-bitwarden
```

`match` asks for the Apple ID and for the passphrase of the certificates repository. The release
lane fetches the certificate read-only and needs no provisioning profile, since the app uses no
capability that requires one.

**The repository secrets**, read by the release workflow:

| Secret                           | Content                                                        |
| -------------------------------- | -------------------------------------------------------------- |
| `FASTLANE_CERTIFICATES_REPO_URL` | HTTPS address of the `match` certificates repository           |
| `GIT_AUTHORIZATION`              | `user:token` with read access to that repository               |
| `MATCH_PASSWORD`                 | Passphrase the certificates repository is encrypted with       |
| `APPLE_KEY_ID`                   | Id of an App Store Connect API key, used for notarization      |
| `APPLE_ISSUER_ID`                | Issuer id of that key                                          |
| `APPLE_KEY_CONTENT`              | Content of the key's `.p8` file                                |
| `TEMP_KEYCHAIN_USER`             | Name for the keychain created for the run                      |
| `TEMP_KEYCHAIN_PASSWORD`         | Password for that keychain; any value                          |

## Trying the packaging locally

`scripts/bundle-app.sh && scripts/make-disk-image.sh` builds the same disk image signed ad hoc.
It runs on the Mac that built it; elsewhere Gatekeeper refuses it, which is what the Developer ID
signature and the notarization are for.
