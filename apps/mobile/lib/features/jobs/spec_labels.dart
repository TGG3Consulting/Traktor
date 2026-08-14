import 'package:api_client/api_client.dart';

/// Человеческие подписи для значений справочника.
///
/// В базе характеристики хранятся ключами (`soft`, `need_workers`) — так их
/// можно переводить и менять текст, не трогая данные. Один общий словарь на
/// приложение: иначе в визарде будет «Мягкий», а в деталке — «soft», как и
/// случилось при первой сборке.
String tkOptionLabel(String key) => switch (key) {
      'soft' => 'Мягкий',
      'clay' => 'Глина',
      'rocky' => 'Скальный',
      'unknown' => 'Не знаю',
      'mine' => 'Погрузка моя',
      'need_workers' => 'Нужны грузчики',
      'plowing' => 'Вспашка',
      'harrowing' => 'Боронование',
      'sowing' => 'Посев',
      'harvest' => 'Уборка',
      'other' => 'Другое',
      _ => key,
    };

/// Название поля характеристик на языке приложения.
String tkSpecTitle(Category? category, String key, String lang) {
  final field = _fieldOf(category, key);
  final label = field?.label.forLang(lang) ?? '';
  return label.isEmpty ? key : label;
}

/// Значение характеристики с единицей измерения и человеческой подписью.
String tkSpecValue(Category? category, String key, Object? value) {
  if (value is bool) return value ? 'Да' : 'Нет';

  final field = _fieldOf(category, key);
  if (field?.type == 'select') return tkOptionLabel('$value');

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
