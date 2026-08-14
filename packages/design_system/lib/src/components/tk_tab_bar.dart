import 'package:flutter/material.dart';
import '../tokens.dart';
import '../icons/tk_icons.dart';
import '../icons/tk_icon.dart';

/// Пункт нижней панели.
///
/// [badge] — число непрочитанного (красный кружок с цифрой, как в прототипе),
/// [dot] — красная точка без числа (например, «есть движение по вашим ставкам»).
class TkTabItem {
  const TkTabItem({
    required this.icon,
    required this.label,
    this.badge,
    this.dot = false,
  });

  /// SVG-путь иконки из [TkIcons].
  final String icon;
  final String label;
  final int? badge;
  final bool dot;
}

/// Нижняя панель навигации Traktor — 1:1 с прототипом (`.tabbar`):
/// четыре пункта и вырез по центру, над которым «висит» круглая кнопка
/// создания. Размеры, цвета и подписи — из брендбука и прототипа:
/// высота 82 (66 + 16 под жест-бар), иконка 21, подпись 10.5, активный —
/// цветом бренда.
///
/// Саму круглую кнопку рисует [TkCreateButton] через `floatingActionButton`
/// у Scaffold — так вырез и тень ложатся правильно.
class TkTabBar extends StatelessWidget {
  const TkTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelected,
  }) : assert(items.length == 4, 'В панели ровно 4 пункта: центр занят кнопкой');

  final List<TkTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      height: 82,
      padding: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).colorScheme.surface,
      elevation: 0,
      child: Row(
        children: [
          _item(context, 0),
          _item(context, 1),
          const SizedBox(width: 64), // вырез под круглую кнопку
          _item(context, 2),
          _item(context, 3),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, int i) {
    final it = items[i];
    final selected = currentIndex == i;
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        onTap: () => onSelected(i),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TkIcon(it.icon, size: 21, color: color),
                const SizedBox(height: 3),
                Text(
                  it.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
            if (it.badge != null) _badge(it.badge!),
            if (it.dot && it.badge == null) _dot(),
          ],
        ),
      ),
    );
  }

  /// Красный кружок с числом — по прототипу смещён вправо-вверх от иконки.
  Widget _badge(int count) => Positioned(
        top: 4,
        right: 8,
        child: Container(
          constraints: const BoxConstraints(minWidth: 16),
          height: 16,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: TkColors.error,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1,
            ),
          ),
        ),
      );

  Widget _dot() => Positioned(
        top: 6,
        right: 14,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(color: TkColors.error, shape: BoxShape.circle),
        ),
      );
}

/// Круглая кнопка создания по центру панели (`.fab` в прототипе):
/// 56×56, цвет бренда, обводка цветом фона (она и делает «вырез»),
/// мягкая оранжевая тень.
class TkCreateButton extends StatelessWidget {
  const TkCreateButton({super.key, required this.onPressed, this.tooltip});

  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surface, // обводка = фон, как border 4px в прототипе
        boxShadow: [
          BoxShadow(
            color: TkColors.primary.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Material(
        color: scheme.primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Tooltip(
            message: tooltip ?? '',
            child: const Center(child: TkIcon(TkIcons.plus, size: 26, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
