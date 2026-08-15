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

/// Время сообщения: «09:02». Часы и минуты всегда двумя цифрами, иначе в
/// ленте переписки время «9:2» съезжает и читается как опечатка.
String tkClock(DateTime? at) {
  if (at == null) return '';
  return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

/// Отметка времени в списке чатов: сегодня — часы, вчера — «вчера»,
/// на этой неделе — день недели, дальше — дата (как в мессенджерах).
String tkChatStamp(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = startOfToday.difference(day).inDays;

  if (diff <= 0) return tkClock(at);
  if (diff == 1) return 'вчера';
  if (diff < 7) {
    const week = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
    return week[at.weekday - 1];
  }
  return tkShortDate(at, now: today);
}

/// Русское склонение после числа: 1 отклик, 2 отклика, 5 откликов.
/// Живёт рядом с остальным форматированием: «1 откликов» в интерфейсе выглядит
/// как недоделка, а склонение нужно в ленте, деталке и уведомлениях.
String tkPlural(int n, String one, String few, String many) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return many;
  return switch (n % 10) {
    1 => one,
    2 || 3 || 4 => few,
    _ => many,
  };
}
