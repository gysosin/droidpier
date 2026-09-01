import 'package:open_dex_api/open_dex_api.dart';

/// What a person can actually do about a failure.
///
/// The backend's `message` says what went wrong. It does not say what to do
/// next, and until this existed nothing did: every one of the twelve error
/// codes rendered identically, so "The Android companion could not start."
/// was the whole of what a person got. An error with no next step is a dead
/// end, which the interface rules here forbid.
///
/// Two rules shape the strings:
///
/// **Never restate the message.** It is printed directly above. Guidance that
/// repeats it spends the only line anyone reads.
///
/// **Point at the thing that must change.** Most of these are fixed on the
/// phone, not on the desktop, and saying which one saves the person checking
/// the wrong device first.
String? guidanceFor(OpenDexError error) => switch (error.code) {
  // Nothing to advise: the person cancelled it themselves.
  OpenDexErrorCode.cancelled => null,

  OpenDexErrorCode.adbUnavailable =>
    'DroidPier could not run ADB. It ships with its own copy, so this usually '
        'means the download was blocked or the file lost its execute bit — '
        'reinstalling is the quickest fix.',

  OpenDexErrorCode.deviceUnauthorized =>
    'The phone is waiting for you to allow this computer. Unlock it, look for '
        'the “Allow USB debugging?” prompt, and tick “Always allow” so it does '
        'not ask again. The prompt only appears while the phone is unlocked.',

  OpenDexErrorCode.deviceOffline =>
    'ADB can see the phone but it is not answering. Unplug the cable and plug '
        'it back in — or, if it is on Wi-Fi, check the phone has not dropped '
        'off the network or gone to sleep.',

  OpenDexErrorCode.multipleDevices =>
    'More than one phone is connected, so DroidPier cannot tell which you '
        'meant. Pick one in the phone list, or disconnect the others.',

  OpenDexErrorCode.connectionFailed =>
    'The connection did not come up. If this is Wi-Fi, the phone must be on '
        'the same network with Wireless debugging still open — that screen '
        'stops advertising the moment it closes.',

  OpenDexErrorCode.deploymentFailed =>
    'The companion could not be installed or started on the phone. Unlock the '
        'phone and look for an approval or Play Protect prompt; installs from '
        'a computer are refused silently while the screen is locked.',

  OpenDexErrorCode.permissionDenied =>
    'Android refused a permission DroidPier needs. Grant it on the phone — '
        'notification access and screen capture each have their own settings '
        'screen and neither can be granted from here.',

  OpenDexErrorCode.capabilityUnavailable => switch (error.capability) {
    final String c when c.trim().isNotEmpty =>
      'This build of Android does not offer $c. The rest of DroidPier works '
          'without it; only the parts that need it are unavailable.',
    _ =>
      'This phone or this build of Android does not offer what was asked for. '
          'The rest of DroidPier works without it.',
  },

  OpenDexErrorCode.protocolError =>
    'The desktop and the phone disagreed about the message they exchanged, '
        'which usually means their versions differ. Update both to the same '
        'release.',

  OpenDexErrorCode.timeout =>
    'The phone did not answer in time. A locked screen, a sleeping phone or a '
        'slow network all do this — wake the phone and try again.',

  OpenDexErrorCode.internal =>
    'Something failed inside DroidPier rather than on the phone. Copy the '
        'diagnostics from the stream panel and attach them to a report; that '
        'is the only thing here that tells a maintainer what happened.',
};
