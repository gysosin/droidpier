# Developing DroidPier

## Requirements

The toolchain is Flutter 3.47.1 / Dart 3.13.1 (see `tool/flutter-sdk.version`), JDK 17,
the checked-in Gradle wrapper, Android platforms 35 and 36, and build-tools 35.0.0.
Linux packaging uses Ubuntu 22.04 with clang, CMake, Ninja, pkg-config, GTK 3
headers, liblzma development files, Python 3, RPM, dpkg-deb, and AppImage tooling.
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

`cd apps/desktop && flutter run -d linux` starts the application. For a safe
UI preview without a phone, use `flutter run -d linux -t lib/ui/preview/preview_app.dart`.
Development deployments use the debug companion; do not overwrite a release
installation without reviewing the [signature migration warning](USER_GUIDE.md).

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
