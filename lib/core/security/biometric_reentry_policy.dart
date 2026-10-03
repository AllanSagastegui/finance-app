class BiometricReentryPolicy {
  BiometricReentryPolicy({this.lockAfter = const Duration(minutes: 1)});

  final Duration lockAfter;
  DateTime? _backgroundedAt;

  void enteredBackground(DateTime now) {
    _backgroundedAt ??= now;
  }

  bool resumed(DateTime now) {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    return backgroundedAt != null &&
        now.difference(backgroundedAt) >= lockAfter;
  }
}
