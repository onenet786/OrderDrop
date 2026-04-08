import 'package:flutter_test/flutter_test.dart';

import 'package:servenow/services/notifier.dart';

void main() {
  group('Notifier.sanitizeMessage', () {
    test('extracts message from JSON-like errors', () {
      final result = Notifier.sanitizeMessage(
        'Exception: {"message":"Invalid credentials"}',
      );

      expect(result, 'Invalid credentials');
    });

    test('removes technical exception prefixes', () {
      final result = Notifier.sanitizeMessage(
        'Exception: UnauthorizedException: Session expired',
      );

      expect(result, 'Session expired');
    });

    test('returns fallback for empty strings', () {
      expect(Notifier.sanitizeMessage(''), 'Something went wrong');
    });
  });
}
