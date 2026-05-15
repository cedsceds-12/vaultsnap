/// In-memory exponential backoff for recovery-answer attempts.
///
/// This intentionally is not persisted: it slows rapid local guessing in the
/// current unlock session without creating extra state that could lock out a
/// legitimate user after an app restart.
class RecoveryBackoffController {
  final DateTime Function() _now;

  int _failures = 0;
  DateTime? _lockedUntil;

  RecoveryBackoffController({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  Duration get remaining {
    final until = _lockedUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get isLocked => remaining > Duration.zero;

  void registerFailure() {
    _failures++;
    final seconds = switch (_failures) {
      1 => 2,
      2 => 4,
      3 => 8,
      4 => 16,
      _ => 30,
    };
    _lockedUntil = _now().add(Duration(seconds: seconds));
  }

  void reset() {
    _failures = 0;
    _lockedUntil = null;
  }
}
