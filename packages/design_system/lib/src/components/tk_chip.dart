import 'package:flutter/material.dart';
import '../tokens.dart';

/// Чип-фильтр (ТЗ §1.10). Активное состояние — заливка primary-soft +
/// оранжевый текст/бордер. Используется в лентах, фильтрах, тегах.
class TkChip extends StatelessWidget {
  const TkChip({super.key, required this.label, this.selected = false, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.12) : scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
          ),
        ),
        child: Text(
          label,
          style: TkText.caption.copyWith(
            color: selected ? scheme.primary : scheme.onSurface,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
