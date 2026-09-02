/// What to call a volume stream, and what order to show them in.
///
/// Android reports volumes in a map keyed by stream name, and the control
/// centre printed those keys straight out — "music", "ring". They are internal
/// identifiers: nobody calls the media volume "music", and "ring" is a verb.
///
/// The agent only ever sends four keys, but this deliberately does not assume
/// that. A key nobody anticipated is still a control the person can move, so it
/// is tidied into something readable rather than hidden or left lowercase — the
/// alternative is a slider labelled `voice_call`, which is worse than either.
String volumeStreamLabel(String stream) {
  final String key = stream.trim().toLowerCase();
  return switch (key) {
    'music' => 'Media',
    'ring' => 'Ringtone',
    'alarm' => 'Alarm',
    'notification' => 'Notifications',
    'system' => 'System',
    'call' || 'voice_call' => 'Voice call',
    'dtmf' => 'Dial tones',
    'accessibility' => 'Accessibility',
    '' => 'Volume',
    // Underscores to spaces, first letter up. `voice_assistant` reads as
    // "Voice assistant" rather than as a variable name.
    _ => _sentence(key.replaceAll('_', ' ')),
  };
}

String _sentence(String s) =>
    s.isEmpty ? 'Volume' : '${s[0].toUpperCase()}${s.substring(1)}';

/// The order these belong in, which is not alphabetical.
///
/// Sorting by key put "alarm" above "music" — correct alphabetically and wrong
/// in every other sense, since media is the one people reach for. Streams that
/// are not in this list keep their relative order and follow the known ones.
const List<String> _order = <String>[
  'music',
  'ring',
  'notification',
  'alarm',
  'system',
  'call',
  'voice_call',
];

List<String> sortVolumeStreams(Iterable<String> streams) {
  final List<String> all = streams.toList();
  all.sort((String a, String b) {
    final int ia = _order.indexOf(a.toLowerCase());
    final int ib = _order.indexOf(b.toLowerCase());
    // Unknown keys sort after every known one, and among themselves stay in
    // whatever order they arrived, so the list does not shuffle between frames.
    if (ia == -1 && ib == -1) return 0;
    if (ia == -1) return 1;
    if (ib == -1) return -1;
    return ia.compareTo(ib);
  });
  return all;
}
