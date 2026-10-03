import 'package:intl/intl.dart';

class Money {
  const Money(this.minor, {this.currencyCode = 'PEN', this.fractionDigits = 2});

  final int minor;
  final String currencyCode;
  final int fractionDigits;

  Money operator +(Money other) {
    if (currencyCode != other.currencyCode) {
      throw ArgumentError('Currency mismatch');
    }
    return Money(
      minor + other.minor,
      currencyCode: currencyCode,
      fractionDigits: fractionDigits,
    );
  }

  String format({String locale = 'es_PE', bool hidden = false}) {
    if (hidden) return '••••••';
    final amount = minor / _pow10(fractionDigits);
    return NumberFormat.simpleCurrency(
      locale: locale,
      name: currencyCode,
      decimalDigits: fractionDigits,
    ).format(amount);
  }

  static int _pow10(int exponent) {
    var value = 1;
    for (var i = 0; i < exponent; i++) {
      value *= 10;
    }
    return value;
  }

  static int? tryParseMinor(String input, {int fractionDigits = 2}) {
    final normalized = input.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(normalized)) return null;
    final parts = normalized.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;
    final fraction = parts.length == 1 ? '' : parts[1];
    final padded = fraction
        .padRight(fractionDigits, '0')
        .substring(0, fractionDigits);
    final minorFraction = padded.isEmpty ? 0 : int.parse(padded);
    return whole * _pow10(fractionDigits) + minorFraction;
  }
}
