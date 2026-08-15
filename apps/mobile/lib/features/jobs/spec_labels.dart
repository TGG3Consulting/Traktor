import 'package:api_client/api_client.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

/// Человеческие подписи для значений справочника.
///
/// В базе характеристики хранятся ключами (`soft`, `need_workers`) — так их
/// можно переводить и менять текст, не трогая данные. Один общий словарь на
/// приложение: иначе в визарде будет «Мягкий», а в деталке — «soft», как и
/// случилось при первой сборке.
String tkOptionLabel(String key, AppLocalizations l) => switch (key) {
      'soft' => l.optSoft,
      'clay' => l.optClay,
      'rocky' => l.optRocky,
      'unknown' => l.optUnknown,
      'mine' => l.optMine,
      'need_workers' => l.optNeedWorkers,
      'plowing' => l.optPlowing,
      'harrowing' => l.optHarrowing,
      'sowing' => l.optSowing,
      'harvest' => l.optHarvest,
      'other' => l.optOther,
      _ => key,
    };

/// Название поля характеристик на языке приложения.
String tkSpecTitle(Category? category, String key, String lang) {
  final field = _fieldOf(category, key);
  final label = field?.label.forLang(lang) ?? '';
  return label.isEmpty ? key : label;
}

/// Значение характеристики с единицей измерения и человеческой подписью.
String tkSpecValue(Category? category, String key, Object? value, AppLocalizations l) {
  if (value is bool) return value ? l.yesShort : l.noShort;

  final field = _fieldOf(category, key);
  if (field?.type == 'select') return tkOptionLabel('$value', l);

  final unit = field?.unit ?? '';
  final text = value is double && value == value.roundToDouble()
      ? value.toInt().toString() // 40.0 → «40»: лишний ноль в карточке мешает
      : '$value';
  return unit.isEmpty ? text : '$text $unit';
}

SpecField? _fieldOf(Category? category, String key) {
  if (category == null) return null;
  for (final f in category.specTemplate) {
    if (f.key == key) return f;
  }
  return null;
}
