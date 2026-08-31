# Compatibility and validation

There is no stable release yet. The table below describes targets, not completed
certification. Each release must publish its own validation evidence.

| Target | Baseline / formats | Current status |
| --- | --- | --- |
| Ubuntu | 22.04 / 24.04 x86-64; DEB, AppImage, archive | Container package checks passed; full validation pending |
| Debian | 12 / 13 x86-64; DEB, AppImage, archive | Validation pending |
| Linux Mint | 22 x86-64; DEB, AppImage, archive | Validation pending |
| Fedora | Current release-date versions, x86-64; RPM | Fedora 44 container package checks passed; full validation pending |
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


## Beta.2 evidence and limits

A Redmi Note 7 Pro on Android 13 was exercised over USB for authenticated startup,
two embedded direct-stream windows, input, portrait/landscape resize, reconnect,
relaunch and owned-resource cleanup. Android 15 emulator testing covers the signed
beta.1-to-beta.2 upgrade, notification permission preservation and debug-signature
conflict; the updated setup UI is inspected on that emulator. These results are
specific checks, not certification of all features on either Android version.

Clean Ubuntu 22.04/24.04 and Fedora 44 containers passed beta.1-to-beta.2 package
upgrades, non-root launch, settings preservation and uninstall without development
SDKs. Ubuntu also passed the AppImage extraction/run fallback.

Physical Wi-Fi/QR pairing, restricted/managed-phone policies and the complete Linux
distribution matrix remain unverified. Container install/launch checks do not test
a distribution's actual compositor, USB stack or physical-device behavior.

60 FPS remains unresolved. Controlled direct-pipeline motion measured roughly
39–47 displayed frames/s on the development Linux computer, with about 60 decoded
frames/s. The recording fallback measured about 9 displayed frames/s. Static apps
naturally produce fewer frames; decoded rate is not a displayed-FPS guarantee.
