import 'package:flutter/material.dart';
import '../tokens.dart';

/// Карточка UI-kit (ТЗ §1.10). Мягкая тень, тонированная под фон (без чёрных
/// теней). Радиус 12. Используется как контейнер группировки, где нужна
/// иерархия; иначе группируем разделителями/отступами.
class TkCard extends StatelessWidget {
  const TkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: TkRadius.cardR,
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : TkColors.graphite)
                .withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}
