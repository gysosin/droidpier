# Linux runtime provenance

## Android update identity

The official companion retains the application ID
`io.github.shrey113.openandroiddex.companion`. The release certificate SHA-256 is:

```text
c7398c50671e0919461b38433a9bec4440817246d9e447b81c49a901d74b0a22
```

This fingerprint was verified from the published beta.1 APK. Official updates
must use the same signing identity and increasing Android version codes. Compare
an APK with `apksigner verify --print-certs path/to/companion.apk`; verify its file
hash against `SHA256SUMS` from the same official release as well. No private key
or password is distributed. Signing identifies the publisher of an update; it
is not a Play Protect endorsement and does not guarantee warning-free installs.



This record covers the Linux x86-64 candidate for 0.1.0-beta.1. Source collection
is separate from device compatibility validation. The release acceptance record
remains the authority for whether a candidate may be published.

## scrcpy

The pinned scrcpy 4.1 Linux archive was built by upstream
[run 29188298263](https://github.com/Genymobile/scrcpy/actions/runs/29188298263)
from commit `fa57d7c6b47139797a8e103f87719740718887d4`. The corresponding-source
collection pins that exact commit, rather than the subsequently moved release
tag. The later tag differs only in documentation and `install_release.sh`.

The build used Ubuntu 22.04 runner image `20260705.219.1`. Its source archive
contains `release/build_linux.sh` and `app/deps/` with build commands for:

| Input | Version | Distribution source |
| --- | --- | --- |
| FFmpeg | 8.1.2 | Upstream archive and scrcpy configure script |
| SDL | 3.4.12 | Upstream source, with optional repository guides omitted |
| dav1d | 1.5.3 | Unmodified upstream archive |
| libusb | 1.0.30 | Unmodified upstream archive |
| zlib | 1.2.11.dfsg-2ubuntu9.2 | Ubuntu source, patches and build rules |
| v4l-utils | 1.22.1-2build1 | Ubuntu source, patches and build rules |
| libjpeg-turbo | 2.1.2-0ubuntu1 | Ubuntu source, patches and build rules |

The last two inputs are included conservatively for the enabled V4L2 build
configuration. Their inclusion is not a claim that every library or utility in
these source packages is embedded in scrcpy. The libv4l libraries use LGPL terms;
the unrelated command-line utilities have separate GPL terms. The collected
copyright files preserve those distinctions. This software is based in part on
the work of the Independent JPEG Group.

SDL loads platform display/audio libraries dynamically. The upstream FFmpeg
configuration detects optional system libraries, but its enabled component list
excludes the TIFF and Matroska decoders, ALSA/sndio devices, XCB capture, and V4L2
input that use bzip2, lzma, ALSA, sndio, XCB and libv4l2. Reviewing the matching
source and Makefiles confirms these consumers are not selected. V4L2 output
uses operating-system calls directly; PNG decoding uses the included zlib.
Libraries supplied by the user's operating system are not copied into the
DroidPier payload.

## Separate FFmpeg decoder

DroidPier's decoder process uses FFmpeg 8.1.2, independently built with
`tool/build_ffmpeg.sh`. Automatic external-library selection is disabled; GPL
and nonfree components are not enabled. No source patches are applied. The
source collection includes the script, pinned source and actual configure
arguments. The packaged binary must pass the checked-in H.264 decoding probe.

## AppImage runtime

The pinned runtime reports commit
`75849dce7cc37e4319b633df1f116ca895c71a12`. Upstream
[run 28063784345](https://github.com/AppImage/type2-runtime/actions/runs/28063784345)
built it using Alpine 3.21 image digest
`sha256:48b0309ca019d89d40f670aa1bc06e426dc0931948452e8491e3d65087abc07d`.

| Linked input | Version | Included build information |
| --- | --- | --- |
| libfuse | 3.15.0 | Runtime source's build script and `mount.c.diff` |
| squashfuse | 0.5.2 | Runtime source's build script |
| musl | 1.2.5-r11 | Alpine APKBUILD and all listed patches/source files |
| zlib | 1.3.2-r0 | Alpine APKBUILD |
| zstd | 1.5.6-r2 | Alpine APKBUILD |
| mimalloc2 | 2.1.7-r0 | Alpine APKBUILD and packaging patch |

All source downloads and packaging files are pinned in `tool/runtime-lock.json`.
Alpine source archive and patch hashes were checked against the matching
APKBUILD's SHA-512 records before recording SHA-256 pins. Ubuntu archives and
patches were checked against their `.dsc` SHA-256 records. The source collection
preserves the recipes' original filenames under `alpine/<package>/`.

The runtime's own MIT license does not replace the licenses of these inputs.
In particular, libfuse contains LGPL library code and GPL utility code; both
texts accompany the package. Source archives retain all applicable notices.

## Source-built ADB

Linux packages use ADB 37.0.0 built from the pinned
[android-tools source release](https://github.com/nmeum/android-tools/releases/tag/37.0.0),
based on AOSP `android-17.0.0_r1`. The Google prebuilt ADB from the scrcpy archive
is not included in the Linux payload. Building it locally provides an exact
source match for its statically linked libusb code.

`tool/build_adb.sh` builds only the `adb` target, using bundled libusb and fmt,
and the vendored Android/BoringSSL code already present in the source archive.
The local patch selects static dependency archives and orders the brotli
libraries correctly for static linking. Ubuntu 22.04's protobuf compiler is
invoked with its proto3-optional flag. No Android protocol source is modified.

The source collection includes the exact Ubuntu source archives, patches and
build rules for protobuf, brotli, lz4, zstd and zlib. Google Test's build headers
and their source package are also covered. `tool/adb-build-inputs.tsv` records
the reviewed source-package versions; builds reject version drift. The resulting
ADB executable depends only on the operating system's C/C++/math runtime, with
no additional USB or compression shared libraries. `licenses/adb/` contains its
source and dependency notices; the legacy platform-tools notices are retained
for other development packaging inputs.

This android-tools build does not provide automatic mDNS discovery. DroidPier's
manual wireless pairing and connection use an explicit address and port. Real
phone validation of those workflows remains tracked separately.

## Other payloads

Android dependencies are resolved
and hashed during Gradle builds, with notices in the APK and desktop packages.
Flutter's generated `NOTICES.Z`, individual font licenses, and the resolved
Dart/Android component inventory accompany the desktop application.

Source collections provide buildable source and patches; they do not claim
byte-for-byte reproduction across arbitrary compiler or host versions. No
additional restriction on modifying or relinking LGPL components is imposed.
