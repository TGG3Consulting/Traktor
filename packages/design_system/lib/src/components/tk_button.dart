import 'package:flutter/material.dart';
import '../tokens.dart';

/// Кнопки UI-kit (ТЗ §1.10): primary / secondary / ghost / destructive.
/// Состояния: default / pressed (tactile scale) / loading / disabled.
/// Одна главная кнопка на экран, закреплена снизу (sticky CTA — на уровне экрана).
enum TkButtonKind { primary, secondary, ghost, destructive }

class TkButton extends StatefulWidget {
  const TkButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = TkButtonKind.primary,
    this.loading = false,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final TkButtonKind kind;
  final bool loading;
  final IconData? icon;
  final bool expand;

  @override
  State<TkButton> createState() => _TkButtonState();
}

class _TkButtonState extends State<TkButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = widget.onPressed == null || widget.loading;

    late final Color bg;
    late final Color fg;
    BorderSide side = BorderSide.none;
    switch (widget.kind) {
      case TkButtonKind.primary:
        bg = scheme.primary;
        fg = Colors.white;
      case TkButtonKind.destructive:
        bg = TkColors.error;
        fg = Colors.white;
      case TkButtonKind.secondary:
        bg = Colors.transparent;
        fg = scheme.primary;
        side = BorderSide(color: scheme.primary, width: 1.5);
      case TkButtonKind.ghost:
        bg = Colors.transparent;
        fg = scheme.onSurface.withValues(alpha: 0.7);
    }

    final child = AnimatedScale(
      scale: _down && !disabled ? 0.98 : 1,
      duration: const Duration(milliseconds: 70),
      child: Container(
        height: 50,
        width: widget.expand ? double.infinity : null,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: disabled && widget.kind == TkButtonKind.primary
              ? scheme.surfaceContainerHighest
              : bg,
          borderRadius: TkRadius.buttonR,
          border: Border.fromBorderSide(side),
        ),
        child: widget.loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 20, color: fg),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.label,
                    style: TkText.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: disabled ? scheme.onSurface.withValues(alpha: 0.4) : fg,
                    ),
                  ),
                ],
              ),
      ),
    );

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: disabled ? null : widget.onPressed,
      child: child,
    );
  }
}
