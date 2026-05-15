import 'package:flutter_test/flutter_test.dart';
import 'package:vault_snap/services/recovery_backoff_controller.dart';

void main() {
  test('recovery backoff grows and resets', () {
    var now = DateTime.utc(2026);
    final backoff = RecoveryBackoffController(now: () => now);

    expect(backoff.isLocked, isFalse);

    backoff.registerFailure();
    expect(backoff.isLocked, isTrue);
    expect(backoff.remaining, const Duration(seconds: 2));

    now = now.add(const Duration(seconds: 2));
    expect(backoff.isLocked, isFalse);

    backoff.registerFailure();
    expect(backoff.remaining, const Duration(seconds: 4));

    backoff.reset();
    expect(backoff.isLocked, isFalse);
    expect(backoff.remaining, Duration.zero);
  });

  test('recovery backoff caps at 30 seconds', () {
    var now = DateTime.utc(2026);
    final backoff = RecoveryBackoffController(now: () => now);

    for (var i = 0; i < 8; i++) {
      backoff.registerFailure();
      now = now.add(backoff.remaining);
    }

    backoff.registerFailure();
    expect(backoff.remaining, const Duration(seconds: 30));
  });
}
