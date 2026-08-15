import 'package:flutter/widgets.dart';

/// Точки перелома и ширины контента (ТЗ §1.8, §4.2).
///
/// Макет рисовался под телефон. На мониторе он либо растягивается в строки
/// шириной в экран, либо сжимается в узкую колонку с пустыми полями — и то,
/// и другое читается плохо. Здесь одно место, где решается, что показывать
/// при какой ширине.
enum TkBreakpoint {
  /// < 600 — телефон: одна колонка, навигация снизу.
  phone,

  /// 600–1024 — планшет: те же экраны, но шире и с боковой навигацией.
  tablet,

  /// > 1024 — десктоп: список и деталка рядом.
  desktop,
}

class TkLayout {
  TkLayout._();

  static const double tabletFrom = 600;
  static const double desktopFrom = 1024;

  /// Ширина колонки чтения. Строка длиннее ~90 символов теряет строку при
  /// переносе взгляда, поэтому текстовые экраны не растягиваем.
  static const double readable = 720;

  /// Предел ширины всего контента на десктопе (ТЗ §1.8).
  static const double contentMax = 1200;

  /// Ширина списка в двухколоночной раскладке: карточка задания остаётся
  /// такой же, как на телефоне, — переучиваться не приходится.
  static const double listPane = 420;

  static TkBreakpoint of(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= desktopFrom) return TkBreakpoint.desktop;
    if (w >= tabletFrom) return TkBreakpoint.tablet;
    return TkBreakpoint.phone;
  }

  static bool isDesktop(BuildContext context) => of(context) == TkBreakpoint.desktop;
  static bool isPhone(BuildContext context) => of(context) == TkBreakpoint.phone;

  /// Отступы контента: 16 на телефоне, 24 на планшете и шире (ТЗ §1.8).
  static EdgeInsets pad(BuildContext context) =>
      EdgeInsets.all(isPhone(context) ? 16 : 24);
}

/// Колонка чтения по центру: тексты и формы не растягиваются на весь монитор.
class TkReadable extends StatelessWidget {
  const TkReadable({super.key, required this.child, this.maxWidth = TkLayout.readable});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
