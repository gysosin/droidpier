# Developing DroidPier

## Requirements

The toolchain is Flutter 3.47.1 / Dart 3.13.1 (see `tool/flutter-sdk.version`), JDK 17,
the checked-in Gradle wrapper, Android platforms 35 and 36, and build-tools 35.0.0.
Linux packaging uses Ubuntu 22.04 with clang, CMake, Ninja, pkg-config, GTK 3
headers, liblzma development files, NASM, Python 3, RPM, dpkg-deb, and AppImage tooling.
The source-built ADB also needs protobuf/compiler, brotli, lz4, zstd, PCRE2,
zlib and Google Test development packages, plus `patch`. Its matching Ubuntu
source-package versions are recorded in `tool/adb-build-inputs.tsv`.
The container recipe is `tool/linux/Dockerfile`. Configure the Android SDK with
`ANDROID_HOME` or an ignored `android/local.properties` file.

```sh
git clone https://github.com/gysosin/droidpier.git
cd droidpier
export PATH="/path/to/flutter/bin:$PATH"
(cd apps/desktop && flutter pub get && flutter analyze && flutter test)
android/gradlew -p android agentJar :companion:assembleDebug test
```

Set `FLUTTER_BIN` for build scripts if Flutter is not in PATH. The scripts also
recognize a local `.tools/flutter` installation. SDKs and build output are not
part of the source repository. Run only one Flutter command at a time per SDK.

## Run and test

For device testing against an installed official Linux package, run:

```sh
DROIDPIER_DEBUG_RUNTIME_DIR=/path/to/extracted/droidpier tool/run_debug.sh
```

This invokes `flutter run -d linux --debug -t lib/main.dart` with explicit ADB,
scrcpy, FFmpeg, agent and companion paths. It does not modify the installed
application. Omit the runtime override if the release is installed at the script's
default user-local location. Do not run the release and debug application against
the same phone simultaneously, or restart a shared ADB server to switch builds.

A mock UI preview is available through
`flutter run -d linux -t lib/ui/preview/preview_app.dart`; it cannot test devices.
Test a debug-signed companion on an emulator. Physical upgrades must use a locally
built candidate signed with the existing release key; never silently uninstall
or replace data to resolve a [signature conflict](USER_GUIDE.md).

Beta.2 defaults to direct streaming on Linux. To diagnose a regression against the
older recording backend, set `OPEN_DEX_WINDOW_BACKEND=legacy` before the debug
script. That fallback is Linux-only and may deliver substantially fewer frames. `OPEN_DEX_FFMPEG` can select a locally rebuilt decoder. Neither override
changes the installed release. Measure presented FPS separately from decoded
FPS using synthetic motion; idle screens and debug-mode results are not a
60 FPS acceptance test. The direct path still requires performance validation.

For each package under `packages/` and `plugins/open_dex_platform`, run
`dart pub get`, `dart analyze` and `dart test`. For desktop changes, run the
existing Flutter suite and inspect actual rendered output. Golden updates need
visual review; a successful image comparison alone does not establish usability.

Run `python3 tool/verify_source.py`, `git diff --check` and `bash -n tool/*.sh`.
Use synthetic data for notification, clipboard, stream and screenshot checks.

## Layout and contracts

See [architecture](ARCHITECTURE.md). Keep backend integration out of UI code.
The public product is DroidPier; stable package names, environment variables,
application IDs and protocol version 1 retain their existing identifiers to
avoid breaking installations and clients. Do not rename these as cosmetic edits.

`version.properties` controls release metadata. `tool/version.py` translates
prereleases to Debian/RPM ordering. Build scripts pass the version explicitly to
Flutter; the pubspec version must remain consistent and is checked in CI.

## Release builds

See [releasing](RELEASING.md). Release APKs require your own signing key when
building a fork. Never commit a key or password. Official updates must use the
maintainer's permanent key. Build the Android payload once, then use the same APK
and shell-agent JAR across every desktop package.

`tool/fetch_runtime.py` verifies pinned upstream checksums; `tool/build_ffmpeg.sh`
builds the restricted FFmpeg configuration. `tool/build_linux.sh` creates Linux
packages. Windows and macOS code is experimental until their native builds and
real-device checks pass; build script availability does not imply support.
