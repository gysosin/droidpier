# Releasing DroidPier

## Release policy

The initial target is `v0.1.0-beta.1`: Linux x86-64 and Android only.
Windows and macOS remain in development until native rendering and real-device
acceptance pass. A successful build is not permission to declare compatibility.
Record evidence in `release/acceptance.json`. Unknown or pending entries block
publication, including missing corresponding source or signing-key recovery.

1. Update `version.properties` and the matching desktop pubspec version. Increase
   Android versionCode for every published APK, even prereleases.
2. Run source checks, Dart/Flutter analysis and tests, Android tests and lint,
   shell syntax and whitespace checks from a fresh checkout.
3. Build the signed Android payload once. Verify its certificate with Android
   `apksigner verify --print-certs`; compare to `release/android-certificate-sha256.txt` and the previously published certificate.
4. Build Linux on the pinned Ubuntu 22.04 baseline. Package one common payload
   into DEB, RPM, AppImage and archive, including the identical APK and JAR.
5. Include notices, dependency inventory, exact dependency sources, patches and
   build configurations. Verify actual bundled dependencies, not only direct ones.
6. Install, launch, upgrade and uninstall on every claimed distribution without
   development SDKs. Test permissions, denied access, device removal, USB and Wi-Fi,
   input, windows, rotation, clipboard, notifications, disconnect and cleanup.
7. Inspect safe screenshots of the actual desktop and companion. Review download
   links, known issues and upgrade warnings.
8. Create a draft prerelease for the exact tested commit. Verify all files and
   `SHA256SUMS`. Publish only after every applicable acceptance item passes.

Never silently replace public release binaries. Corrections require a new version.
The source tag must resolve to the commit used to build the artifacts.
The publication workflow also requires the draft to target its exact checked-out
commit. If code or acceptance evidence changes after a candidate build, rebuild
and review the private draft for that commit before publication. A published
version must never be deleted or replaced to work around this check.

## Android signing

`tool/build_android.py` accepts `DROIDPIER_KEYSTORE`, `DROIDPIER_STORE_PASSWORD`,
`DROIDPIER_KEY_ALIAS` (default `droidpier`) and `DROIDPIER_KEY_PASSWORD` (defaults
to store password). For local maintainer use it can read a private keystore and
password from `~/.local/share/droidpier/signing/`. Restrict file permissions.

The build automatically verifies the APK against the permanent certificate,
release version, application ID, minimum SDK and production manifest before
copying it into the release payload. Run `python3 tool/verify_android.py PATH.apk`
to repeat those checks on a candidate using Android build-tools 35.0.0.

Keep at least one encrypted, independently stored backup and test recovery.
A second copy on the build computer does not protect against losing that computer.
Losing the key prevents in-place Android updates. Never include signing material
in logs, artifacts, source archives or pull-request workflows.

For GitHub releases, use the protected `release` environment with required review
and only the `main` branch. Store `ANDROID_KEYSTORE_BASE64` and
`ANDROID_KEYSTORE_PASSWORD` as environment secrets. Release workflows decode the
key into the runner's temporary directory and delete it after building. Fork and
pull-request jobs use debug builds and cannot access release secrets.

## Native desktop signing

Linux packages have SHA-256 release manifests; there is no hosted apt/rpm repository.
Windows initially has no trusted publisher signature. macOS uses ad-hoc signing
until Developer ID and notarization are configured. Document per-application OS
approval steps without telling users to disable protection globally. Review
[Apple's distribution guidance](https://developer.apple.com/support/developer-id/).

## Repository administration

Keep `gysosin` as administrator. Require CI on main and protect it from force
pushes and deletion. Enable issues, discussions, wiki, dependency alerts, private
vulnerability reporting and available secret scanning/push protection. Keep
workflow permissions minimal. Release jobs have write permission only where needed.

The public source history starts with a clean initial commit. Only public main and
new release tags belong on the public remote. Never mirror all local refs. Verify a
fresh clone has no private history, local tools, signing material or build output.

## Wiki and star chart

`tool/sync_wiki.py` renders the wiki into a selected output directory from reviewed
public docs. The wiki has its own Git repository and must be initialized in GitHub
before the first Git push. Review generated pages and push only that repository.

The star-history workflow reads only the repository's aggregate `stargazers_count`.
It writes one daily count and an SVG to an independent `metrics` branch, without
individual profiles. API failures leave the previous chart unchanged and do not
block releases. Zero stars is a valid chart.
