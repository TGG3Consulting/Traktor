/// Форматирование чисел и времени в едином виде для всего приложения.
///
/// Живёт в дизайн-системе, а не в фичах: «120 000 ֏» и «3ч 12м» должны
/// выглядеть одинаково в карточке, деталке и CRM.
library;

/// Неразрывный пробел: разряды и знак валюты не должны разрываться переносом.
const nbsp = '\u00A0';

/// Сумма с разделителями разрядов и знаком валюты: 120000 → «120 000 ֏».
/// Для AMD дробная часть не используется (ТЗ §18: валюта AMD, поле currency
/// есть везде — на случай другой валюты знак подставляется по коду).
String tkMoney(num? amount, {String currency = 'AMD'}) {
  if (amount == null) return '—';
  final digits = amount.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(nbsp); // неразрывный: цена не должна переноситься по строкам
    buf.write(digits[i]);
  }
  final sign = amount < 0 ? '−' : '';
  return '$sign$buf$nbsp${tkCurrencySign(currency)}';
}

/// Знак валюты. ֏ — армянский драм.
String tkCurrencySign(String currency) => switch (currency) {
      'AMD' => '֏',
      'USD' => '\$',
      'EUR' => '€',
      'RUB' => '₽',
      _ => currency,
    };

/// Расстояние: 4200 м → «4,2 км», 800 м → «800 м», совсем близко → «рядом».
/// «0 м» в карточке выглядит как ошибка, хотя означает «на этом же месте».
String tkDistance(double? meters) {
  if (meters == null) return '';
  if (meters < 100) return 'рядом';
  if (meters < 1000) return '${meters.round()} м';
  final km = meters / 1000;
  final s = km < 10 ? km.toStringAsFixed(1).replaceAll('.', ',') : km.round().toString();
  return '$s км';
}

/// Остаток времени для таймера аукциона: «3ч 12м», «12м 30с», «завершён».
/// Секунды показываем только на последнем часе — иначе цифры прыгают без
/// пользы и отвлекают.
String tkTimeLeft(Duration? left) {
  if (left == null) return '';
  if (left.isNegative || left.inSeconds == 0) return 'завершён';
  final d = left.inDays;
  final h = left.inHours % 24;
  final m = left.inMinutes % 60;
  final s = left.inSeconds % 60;
  if (d > 0) return '${d}д ${h}ч';
  if (left.inHours > 0) return '${left.inHours}ч ${m}м';
  if (left.inMinutes > 0) return '${m}м ${s}с';
  return '${s}с';
}

/// Дата в человеческом виде без года, если он текущий: «16 авг», «16 авг 2027».
String tkShortDate(DateTime? date, {DateTime? now}) {
  if (date == null) return '';
  const months = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  final today = now ?? DateTime.now();
  final base = '${date.day} ${months[date.month - 1]}';
  return date.year == today.year ? base : '$base ${date.year}';
}
