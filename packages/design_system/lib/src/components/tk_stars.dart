import 'package:flutter/material.dart';

import '../icons/tk_icon.dart';
import '../icons/tk_icons.dart';
import '../tokens.dart';

/// Звёзды оценки (ТЗ §2.13).
///
/// Один компонент на две задачи: показать чужой рейтинг и поставить свой.
/// Разводить их по разным виджетам незачем — отличие только в onChanged.
class TkStars extends StatelessWidget {
  const TkStars({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 32,
  });

  /// Сколько звёзд закрашено. Ноль — оценки ещё нет.
  final int value;

  /// Если задан — звёзды можно нажимать.
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            button: onChanged != null,
            label: '$i из 5',
            child: GestureDetector(
              onTap: onChanged == null ? null : () => onChanged!(i),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size * 0.09),
                child: TkIcon(
                  i <= value ? TkIcons.starFill : TkIcons.star,
                  size: size,
                  color: i <= value ? TkColors.warning : scheme.outline,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Компактная строка рейтинга: «★ 4,8 · 36 оценок». Без оценок показывает
/// «нет оценок» — пустое место читается как ошибка загрузки.
class TkRatingLine extends StatelessWidget {
  const TkRatingLine({super.key, required this.rating, required this.count});

  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (count == 0) {
      return Text(
        'Нет оценок',
        style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const TkIcon(TkIcons.starFill, size: 14, color: TkColors.warning),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1).replaceAll('.', ','),
          style: TkText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 4),
        Text(
          '· $count ${_plural(count)}',
          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  static String _plural(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'оценок';
    return switch (n % 10) {
      1 => 'оценка',
      2 || 3 || 4 => 'оценки',
      _ => 'оценок',
    };
  }
}
