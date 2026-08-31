# Using DroidPier

## Download status

The first beta is being prepared. Download only from
[GitHub Releases](https://github.com/gysosin/droidpier/releases) when a release
is published. Check the release's compatibility table before installing.
Windows and macOS are in development; there are no supported downloads yet.
Linux builds target x86-64, glibc 2.35 or newer, GTK 3, and a working OpenGL driver.
Musl-based distributions such as Alpine are not supported by these binaries.

DroidPier uses FFmpeg under LGPL-2.1-or-later. The matching source and build
instructions must accompany each binary release; see [third-party software](THIRD_PARTY.md).

## Verify a download

Download `SHA256SUMS` and the desired package from the same release.
Run `sha256sum --ignore-missing -c SHA256SUMS` in the download directory.
Require an `OK` result for every file you intend to use. Checksums detect
corruption; obtain both the files and checksums from the official repository.
Never install a package reported as failed or absent.

## Install on Linux

For Debian, Ubuntu or Mint, use `sudo apt install ./droidpier-VERSION-linux-amd64.deb`.
For Fedora, use `sudo dnf install ./droidpier-VERSION-linux-x86_64.rpm`.
Replace `VERSION` with the downloaded version. These commands install system
packages; launch DroidPier as your regular user, never as root.

For an AppImage, run `chmod +x droidpier-VERSION-linux-x86_64.AppImage`, then
open it. If FUSE mounting is unavailable, run it with `--appimage-extract-and-run`.
Alternatively use `--appimage-extract` and run `squashfs-root/AppRun`.

For the archive, extract it with `tar -xzf droidpier-VERSION-linux-x86_64.tar.gz`
and run `./droidpier/droidpier`. Keep its `data`, `lib`, and `resources` directories
next to the executable. Portable formats still need the documented system libraries.
No Flutter, Java, Android SDK or compiler is required to use a completed package.

## First connection over USB

1. Use a data-capable USB cable and unlock the phone.
2. Enable Developer options on Android (usually tap Build number seven times),
   then enable USB debugging. Manufacturer menus differ.
3. Start DroidPier and select the device. Accept Android's RSA authorization
   dialog only for a computer you trust. Do not post the dialog or device serial.
4. DroidPier deploys its companion and shell agent. Allow any installation prompt.
5. Open **DroidPier Companion** on the phone to check connection and permissions.
   Notification access is optional and can be revoked at any time.
6. Open an app from the desktop launcher. Apps that disallow secondary displays,
   secure capture, or resizing may not work correctly.

If Linux reports insufficient USB permissions, use your distribution's Android
udev rules package (commonly `android-sdk-platform-tools-common` on Debian/Ubuntu
or `android-tools` on Fedora), then unplug and reconnect. Log in again if your
distribution requires a group change. Do not fix this by running the desktop or
ADB as root, or by giving every USB device unrestricted permissions.

## Wireless pairing

Android 11 or later normally exposes **Developer options → Wireless debugging**.
Use a trusted local network. Choose **Pair device with pairing code**, then enter
the pairing address, port and code in DroidPier. The pairing port and subsequent
connection port can differ: use the addresses Android displays for each step.
Never paste a real pairing code in an issue. Wireless debugging can be disabled
on the phone after use. Older Android versions may need an initial USB connection
and are not advertised as validated wireless configurations.

## Companion status and permissions

The companion installs on Android 8 or later, but installation alone does not
establish full desktop compatibility. See [compatibility](COMPATIBILITY.md).
The setup screen reports a desktop connection only after the authenticated
connection opens. Its Disconnect button is enabled only when both applications
support the negotiated disconnect command. Disconnect ends the session; use the
desktop Connect action to resume.

On Android 13 or later, the notifications shortcut requests notification permission.
The separate notification-access shortcut opens Android's listener settings.
Denying either permission must not grant it implicitly. Notification access can
expose message contents; grant it only if you want notifications on the desktop.
Clipboard and remote input also move sensitive content between your devices.

## Upgrades and development APK migration

Use packages from the same release. Android updates require the same permanent
signing key and an increasing version code. A previously installed debug companion
has a different signing identity and cannot be updated in place. DroidPier reports
this conflict and never silently uninstalls it. If you choose to migrate, uninstall
the development companion yourself, install the signed APK, and regrant permissions.
Uninstalling removes its app data. Normal signed-to-signed updates preserve app data.

There is no silent updater: check GitHub Releases and install updates yourself.
Do not downgrade Android version codes or replace published binaries in place.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No phone listed | Data cable, unlocked phone, USB debugging and udev permissions |
| Device unauthorized | Accept the phone's RSA prompt; revoke old USB authorizations only if needed |
| Wireless connection fails | Same trusted network, correct pairing and connection ports, firewall rules |
| Companion install fails | Android version, permission prompt, or debug/release signature conflict |
| No notifications | Notification permission and separate notification-listener access |
| Black app window | Try an ordinary non-DRM app; check Android/display support and GPU drivers |
| Resize or orientation fails | Some apps lock orientation or reject secondary displays |
| No desktop sound | Audio forwarding is not implemented; media controls do not play audio |
| AppImage cannot mount | Use the extraction fallback above |
| Disconnect button unavailable | Wait for authentication; both ends need disconnect capability support |

Disconnect/reconnect after device removal. Avoid starting competing ADB servers
under different user accounts. When reporting a bug, include application versions,
distribution, Android version, device model (not serial), steps, and redacted logs.
Never upload pairing tokens, notifications, real clipboard contents or private captures.

## Uninstall

Quit DroidPier and disconnect first. Use `sudo apt remove droidpier` or
`sudo dnf remove droidpier` for system packages. Delete the extracted directory or
AppImage for portable installs. Uninstall DroidPier Companion from Android settings
if no longer wanted. Revoke USB debugging authorizations, wireless pairings and
notification access on the phone as appropriate. Package removal does not wipe
phone apps or their data, and it must not delete another application's ADB processes.
