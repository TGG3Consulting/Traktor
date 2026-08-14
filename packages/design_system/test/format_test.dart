import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('деньги', () {
    test('разряды разделяются, знак валюты в конце', () {
      expect(tkMoney(120000), '120\u00A0000\u00A0֏');
      expect(tkMoney(1500), '1${nbsp}500$nbsp֏');
      expect(tkMoney(999), '999$nbsp֏');
      expect(tkMoney(1234567), '1${nbsp}234${nbsp}567$nbsp֏');
    });

    test('пустая сумма не превращается в 0 — это разные вещи', () {
      expect(tkMoney(null), '—');
    });

    test('другая валюта — свой знак', () {
      expect(tkMoney(50, currency: 'USD'), '50$nbsp\$');
      expect(tkMoney(50, currency: 'XYZ'), '50${nbsp}XYZ');
    });
  });

  group('расстояние', () {
    test('совсем близко — «рядом», а не «0 м»', () {
      expect(tkDistance(0), 'рядом');
      expect(tkDistance(45), 'рядом');
    });

    test('до километра — метры, дальше километры', () {
      expect(tkDistance(800), '800 м');
      expect(tkDistance(4200), '4,2 км');
      expect(tkDistance(26000), '26 км');
    });
  });

  group('таймер аукциона', () {
    test('секунды показываются только на последнем часе', () {
      expect(tkTimeLeft(const Duration(hours: 3, minutes: 12, seconds: 45)), '3ч 12м');
      expect(tkTimeLeft(const Duration(minutes: 12, seconds: 30)), '12м 30с');
      expect(tkTimeLeft(const Duration(seconds: 9)), '9с');
    });

    test('сутки и больше — дни и часы', () {
      expect(tkTimeLeft(const Duration(days: 2, hours: 5)), '2д 5ч');
    });

    test('истёкшее время не показывается отрицательным', () {
      expect(tkTimeLeft(const Duration(seconds: -10)), 'завершён');
      expect(tkTimeLeft(Duration.zero), 'завершён');
    });
  });

  group('дата', () {
    test('год показывается только если он не текущий', () {
      final now = DateTime(2026, 8, 15);
      expect(tkShortDate(DateTime(2026, 8, 16), now: now), '16 авг');
      expect(tkShortDate(DateTime(2027, 1, 3), now: now), '3 янв 2027');
    });
  });
}
