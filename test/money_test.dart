import 'package:finance_app/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money', () {
    test('parses decimal input without binary floating point', () {
      expect(Money.tryParseMinor('12.50'), 1250);
      expect(Money.tryParseMinor('12,5'), 1250);
      expect(Money.tryParseMinor('0.01'), 1);
    });

    test('rejects malformed and excessive precision', () {
      expect(Money.tryParseMinor('12.999'), isNull);
      expect(Money.tryParseMinor('-1'), isNull);
      expect(Money.tryParseMinor('abc'), isNull);
    });

    test('adds only matching currencies', () {
      expect((const Money(100) + const Money(250)).minor, 350);
      expect(
        () =>
            const Money(100, currencyCode: 'PEN') +
            const Money(100, currencyCode: 'USD'),
        throwsArgumentError,
      );
    });
  });
}
