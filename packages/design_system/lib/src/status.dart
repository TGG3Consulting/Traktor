import 'package:flutter/widgets.dart';
import 'tokens.dart';

/// Единая статусная карта заказа/сделки (ТЗ §1.10). Используется везде
/// одинаково: карточки, деталки, CRM, таймлайны. Цвет статуса — только отсюда.
enum TkStatus {
  draft,
  published,
  bidding,
  deciding,
  confirmed,
  inProgress,
  acceptance,
  completed,
  dispute,
  cancelled,
}

extension TkStatusX on TkStatus {
  Color get color => switch (this) {
        TkStatus.draft => const Color(0xFF8A919B),
        TkStatus.published => TkColors.info,
        TkStatus.bidding => TkColors.warning,
        TkStatus.deciding => const Color(0xFF8B5CF6),
        TkStatus.confirmed => const Color(0xFF14B8A6),
        TkStatus.inProgress => TkColors.primary,
        TkStatus.acceptance => const Color(0xFF38BDF8),
        TkStatus.completed => TkColors.success,
        TkStatus.dispute => TkColors.error,
        TkStatus.cancelled => const Color(0xFF4B5563),
      };

  /// Ключ локализации (ARB) — подписи переводятся в packages/l10n (hy/ru/en).
  String get l10nKey => switch (this) {
        TkStatus.draft => 'status_draft',
        TkStatus.published => 'status_published',
        TkStatus.bidding => 'status_bidding',
        TkStatus.deciding => 'status_deciding',
        TkStatus.confirmed => 'status_confirmed',
        TkStatus.inProgress => 'status_in_progress',
        TkStatus.acceptance => 'status_acceptance',
        TkStatus.completed => 'status_completed',
        TkStatus.dispute => 'status_dispute',
        TkStatus.cancelled => 'status_cancelled',
      };
}
