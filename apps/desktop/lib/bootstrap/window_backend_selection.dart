enum WindowBackendSelection { legacy, direct }

WindowBackendSelection resolveWindowBackend(
  Map<String, String> environment, {
  bool linux = true,
}) {
  final value = environment['OPEN_DEX_WINDOW_BACKEND']?.trim().toLowerCase();
  return switch (value) {
    null || '' => WindowBackendSelection.direct,
    'legacy' =>
      linux
          ? WindowBackendSelection.legacy
          : throw UnsupportedError(
              'The legacy video backend is Linux-only. Use direct on this platform.',
            ),
    'direct' => WindowBackendSelection.direct,
    _ => throw ArgumentError.value(
      value,
      'OPEN_DEX_WINDOW_BACKEND',
      'must be legacy or direct',
    ),
  };
}
