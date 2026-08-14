import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Иконка интерфейса Traktor.
///
/// Рисует официальный SVG-путь Phosphor (см. [TkIcons]) нужного размера и
/// цвета. Используется вместо Material-иконок: правило 8 ORCHESTRATOR —
/// иконки интерфейса только Phosphor, эмодзи в интерфейсе запрещены.
class TkIcon extends StatelessWidget {
  const TkIcon(this.path, {super.key, this.size = 24, this.color});

  /// SVG-путь иконки — константа из [TkIcons].
  final String path;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">$path</svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
    );
  }
}
