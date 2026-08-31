/// Relative time, in the words a person would use.
///
/// `now` is always passed in rather than read from the clock, so anything
/// rendering a timestamp stays deterministic under test.
String relativeAge(DateTime then, DateTime now) {
  final Duration d = now.difference(then);
  if (d.inMinutes < 1) {
    return 'just now';
  }
  if (d.inMinutes < 60) {
    return '${d.inMinutes} min ago';
  }
  if (d.inHours < 24) {
    return '${d.inHours} h ago';
  }
  return '${d.inDays} d ago';
}
