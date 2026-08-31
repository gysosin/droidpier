# Compatibility and validation

There is no stable release yet. The table below describes targets, not completed
certification. Each release must publish its own validation evidence.

| Target | Baseline / formats | Current status |
| --- | --- | --- |
| Ubuntu | 22.04 / 24.04 x86-64; DEB, AppImage, archive | Validation pending |
| Debian | 12 / 13 x86-64; DEB, AppImage, archive | Validation pending |
| Linux Mint | 22 x86-64; DEB, AppImage, archive | Validation pending |
| Fedora | Current release-date versions, x86-64; RPM | Validation pending |
| Arch / openSUSE | Recorded rolling snapshots; AppImage/archive | Validation pending |
| Windows | x64 installer/ZIP | In development; no public binaries |
| macOS | Apple Silicon and Intel, separate DMGs | In development; no public binaries |

Linux requires a graphical desktop with working GTK/OpenGL support. Do not assume
Alpine/musl, obsolete distributions, headless systems, or every Linux derivative
works. AppImage dependencies cannot replace the system kernel/graphics drivers.

The companion can install on Android 8/API 26 and later. This does not mean every
phone supports the complete workspace. scrcpy virtual displays require Android
10 or later, and application-launch restrictions can further limit older versions
and manufacturer builds. Wireless-debugging pairing requires Android 11 or later.
A release must list which device/Android combinations were actually tested, without
publishing serial numbers or other device identifiers.

DRM-protected apps may render black. Some apps refuse secondary displays or force
orientation. Clipboard and notification capabilities depend on Android policy and
explicit permission. Video targets up to 60 FPS but depends on the device and
connection. Desktop audio forwarding is not implemented; media controls are separate.
