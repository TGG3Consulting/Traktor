/// Дизайн-система Traktor.
///
/// Единственный источник визуала в приложении: цвета, типографика, темы и
/// компоненты UI-kit (ТЗ §1.10). Значения — из брендбука `design/brand/`
/// (концепт логотипа B «T-балка»). Никакого хардкода цветов/радиусов в фичах —
/// только через эти токены и компоненты.
library design_system;

export 'src/tokens.dart';
export 'src/status.dart';
export 'src/theme.dart';
export 'src/components/tk_button.dart';
export 'src/components/tk_status_badge.dart';
export 'src/components/tk_chip.dart';
export 'src/components/tk_card.dart';
export 'src/components/tk_text_field.dart';
