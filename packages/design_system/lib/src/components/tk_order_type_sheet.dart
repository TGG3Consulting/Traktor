import 'package:flutter/material.dart';
import '../tokens.dart';
import '../icons/tk_icons.dart';
import '../icons/tk_icon.dart';

/// Четыре типа заказа (ТЗ §5.1). Заказчик выбирает их в шите по кнопке «+».
enum TkOrderType {
  /// Задание с описанием — фикс-цена или обратный аукцион.
  job,

  /// Аренда техники: почасово, посменно, посуточно.
  rental,

  /// Перевозка А→Б грузовиком.
  transport,

  /// Разнорабочие без техники (также доступны опцией в любом заказе).
  workers,
}

/// Шит «Что вам нужно?» — то, что открывается по круглой кнопке у заказчика
/// (в прототипе `orderSheet()`). Возвращает выбранный тип заказа или null,
/// если пользователь закрыл шит.
Future<TkOrderType?> showTkOrderTypeSheet(BuildContext context) {
  return showModalBottomSheet<TkOrderType>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const _OrderTypeSheet(),
  );
}

class _OrderTypeSheet extends StatelessWidget {
  const _OrderTypeSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Полоска-хендл, как в прототипе (.grab)
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Что вам нужно?', style: TkText.h2),
          const SizedBox(height: 4),
          Text(
            'Выберите тип заказа — дальше всё подскажем',
            style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _row(
            context,
            icon: TkIcons.clipboardText,
            title: 'Задание с описанием',
            subtitle: 'Опишу работу — исполнители предложат цену',
            type: TkOrderType.job,
          ),
          _row(
            context,
            icon: TkIcons.tractor,
            title: 'Аренда техники',
            subtitle: 'Почасово, посменно или на сутки — с оператором',
            type: TkOrderType.rental,
          ),
          _row(
            context,
            icon: TkIcons.truck,
            title: 'Перевозка А→Б',
            subtitle: 'Отвезти груз из точки в точку',
            type: TkOrderType.transport,
          ),
          _row(
            context,
            icon: TkIcons.usersThree,
            title: 'Разнорабочие',
            subtitle: 'Люди без техники: погрузка, уборка, помощь',
            type: TkOrderType.workers,
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String icon,
    required String title,
    required String subtitle,
    required TkOrderType type,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(TkRadius.card),
      onTap: () => Navigator.of(context).pop(type),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: TkColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(TkRadius.button),
              ),
              child: Center(child: TkIcon(icon, size: 24, color: TkColors.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TkText.h3),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            TkIcon(TkIcons.arrowDown, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
