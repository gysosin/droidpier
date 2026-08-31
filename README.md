# DroidPier

**Your Android. A bigger workspace.**

DroidPier brings your Android apps into a desktop workspace: launch apps, arrange
multiple windows, use your keyboard and mouse, and manage your connected phone.
Your apps run on your phone. Your computer provides the workspace.

[![Build](https://github.com/gysosin/droidpier/actions/workflows/ci.yml/badge.svg)](https://github.com/gysosin/droidpier/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gysosin/droidpier?include_prereleases)](https://github.com/gysosin/droidpier/releases)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/gysosin/droidpier)](https://github.com/gysosin/droidpier/stargazers)

![DroidPier desktop preview](apps/desktop/assets/branding/desktop-preview.png)

*Actual Flutter UI rendered with synthetic demo data; this preview is not a device compatibility test.*

[Documentation](docs/README.md) · [Wiki](https://github.com/gysosin/droidpier/wiki)

## Download

**The first Linux/Android beta is being prepared.** Source is available; a package
is supported only when its release notes list a completed validation result.
There are no Windows or macOS public downloads yet.

[Download published releases](https://github.com/gysosin/droidpier/releases)

| Platform | Planned package | Status |
| --- | --- | --- |
| Ubuntu / Debian / Linux Mint, x86-64 | `.deb` | Beta preparation |
| Fedora, x86-64 | `.rpm` | Beta preparation |
| Compatible Linux desktops, x86-64 | AppImage / `.tar.gz` | Beta preparation |
| Android | DroidPier Companion `.apk` | Beta preparation |
| Windows x64 | Installer / portable ZIP | In development |
| macOS Apple Silicon / Intel | Separate DMGs | In development |

Published desktop packages include the matching companion APK, shell agent, ADB,
scrcpy, and video decoder. End users do not need a development SDK. DroidPier uses
FFmpeg under LGPL-2.1-or-later; matching dependency source archives accompany binary
releases. [Licenses and source details](docs/THIRD_PARTY.md)

## What it does

- A desktop workspace with an app drawer and multiple embedded Android app windows.
- Move, resize, minimize, maximize, and close app windows.
- Keyboard and pointer input, including Android navigation actions.
- USB connections and Android wireless-debugging pairing.
- Optional clipboard synchronization and notification integration.
- Phone battery information, volume controls, and supported media actions.

**Known limits:** audio is not forwarded to computer speakers; media controls do
not imply audio playback. DRM-protected and secondary-display-restricted apps may
not work. Android behavior varies by device, OS version, and manufacturer. A
60 FPS target is not a performance guarantee. See [compatibility](docs/COMPATIBILITY.md).

## First connection

1. Install the appropriate published desktop package and open DroidPier.
2. On the phone, enable **Developer options → USB debugging**.
3. Connect a USB data cable. Unlock the phone and approve the computer's debugging
   authorization prompt only if you trust that computer.
4. Select the phone in DroidPier. The desktop installs its bundled companion.
5. Open **DroidPier Companion** on Android for setup/status. Notification access
   is optional and must be granted explicitly in Android settings.
6. Open an app from the desktop app drawer.

For wireless use on Android 11 or later, enable **Wireless debugging** while both
devices are on a trusted network. Enter the phone's pairing address, port, and
code in DroidPier, then connect using its separate connection port. Do not expose
ADB to the public internet. [Detailed setup and troubleshooting](docs/USER_GUIDE.md)

## Privacy and security

No DroidPier account, cloud relay, advertising, or analytics is required. Device
communication is authenticated and carried through ADB. Clipboard and notification
features expose that content to your connected computer when enabled; use them
only with trusted devices. [Privacy](docs/PRIVACY.md) · [Report a vulnerability](SECURITY.md)

## Build and contribute

[Development guide](docs/DEVELOPMENT.md) · [Architecture](docs/ARCHITECTURE.md) ·
[Contributing](CONTRIBUTING.md) · [Roadmap](docs/ROADMAP.md) · [Changelog](CHANGELOG.md)

Bug reports should describe your platform, app version, Android version, and
reproduction steps. Remove device identifiers, pairing codes, personal notifications,
clipboard text, and secrets from screenshots and logs.

## Star history

![Daily aggregate GitHub stars](https://raw.githubusercontent.com/gysosin/droidpier/metrics/star-history.svg)

[View DroidPier's star history](https://github.com/gysosin/droidpier/tree/metrics)

The repository records daily aggregate star counts, never individual profiles.
Zero stars is a valid starting point; API failures preserve the previous chart.

## Credits and license

Original DroidPier code is licensed under [Apache-2.0](LICENSE). Bundled components
retain their own licenses; see [NOTICE](NOTICE) and [third-party notices](docs/THIRD_PARTY.md).
DroidPier builds on Flutter, Android tooling, and scrcpy. It is independent of and
not endorsed by Google, Samsung, Genymobile, or their affiliated products.
