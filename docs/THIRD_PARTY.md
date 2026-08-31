# Third-party software and redistribution

DroidPier's original code is Apache-2.0; dependencies retain their own licenses.
DroidPier is independent of Samsung, Google, Genymobile and other upstream projects.
See [LICENSE](../LICENSE), [NOTICE](../NOTICE) and the texts in [licenses](../licenses/).

| Component | Version authority | License / source |
| --- | --- | --- |
| Flutter engine and Dart runtime | `tool/flutter-sdk.version`, Flutter framework lock | BSD-style notices generated in the Flutter bundle |
| Dart packages | Each `pubspec.lock` | Package licenses included by Flutter; retain `NOTICES.Z` |
| AndroidX | Android Gradle dependency resolution | Apache-2.0; Google AndroidX |
| OkHttp / Okio | Android Gradle dependency resolution | Apache-2.0; Square |
| Kotlin standard library | Android Gradle dependency resolution | Apache-2.0; JetBrains |
| scrcpy / Android server | `tool/runtime-lock.json` | Apache-2.0; Genymobile/scrcpy |
| FFmpeg | `tool/runtime-lock.json` | LGPL-2.1-or-later for the selected non-GPL configuration |
| SDL | scrcpy's pinned build inputs | zlib license |
| dav1d | scrcpy's pinned build inputs | BSD-2-Clause |
| libusb | scrcpy's pinned build inputs | LGPL-2.1-or-later |
| ADB | Upstream runtime manifest | Apache/BSD and additional component notices; audit the shipped binary |
| Instrument Sans, Space Grotesk, Public Sans, IBM Plex Mono | Bundled font files | SIL Open Font License 1.1; individual notices in `licenses/fonts/` |
| AppImage runtime | Pinned runtime asset | See its included upstream license/source notices |

This inventory describes intended inputs; it is not a declaration that every
binary has completed redistribution review. The acceptance record must say when
the full transitive dependency audit is complete. The release includes both a file SBOM (payload hashes) and a component SBOM
(resolved Dart/Android dependencies and pinned runtime inputs). These inventories
do not replace the full license and corresponding-source review.

## FFmpeg and corresponding source

This software uses code of FFmpeg licensed under LGPL-2.1-or-later. Matching source
archives, patches (including an explicit statement when there are none), and build
instructions must be attached to the same GitHub Release as the executables.
`tool/build_ffmpeg.sh` disables GPL, nonfree and automatic external-library
selection. The desktop invokes FFmpeg as a separate process. The official scrcpy
bundle also contains linked third-party code and requires its own complete audit.

For each shipped static component, provide sufficient matching source and build
configuration to rebuild or relink it under its license. Do not assume a link to
a current upstream branch satisfies the requirement. `tool/prepare_sources.py`
collects pinned sources and build recipes, but publication remains blocked until
its contents match the actual shipped binaries and all notices are verified.

System libraries required from the user's distribution are declared package
requirements, rather than copied without their notices and source obligations.
Codec patents and trademark questions may require independent legal advice.
Consult [FFmpeg's licensing guidance](https://ffmpeg.org/legal.html).
