import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../jobs_providers.dart';
import 'wizard_controller.dart';
import 'wizard_scaffold.dart';

/// Шаг 5 из 5 — проверка и публикация (ТЗ §2.6, прототип `create5`).
///
/// Показываем ровно ту карточку, которую увидят исполнители: так заказчик
/// замечает «слишком коротко описал» до публикации, а не после.
class CreateStep5 extends ConsumerWidget {
  const CreateStep5({super.key});

  Future<void> _publish(BuildContext context, WidgetRef ref) async {
    final published = await ref.read(wizardControllerProvider.notifier).publish();
    if (published == null || !context.mounted) return;
    context.go('/jobs/published/${published.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wizardControllerProvider);
    final job = state.job;
    final category = ref.watch(categoryByIdProvider(job?.categoryId));
    final lang = Localizations.localeOf(context).languageCode;
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);

    return WizardScaffold(
      step: 5,
      subtitle: l.step5Title,
      onBack: () => context.go('/jobs/create/4'),
      error: state.error,
      saving: state.saving,
      primaryLabel: l.publish,
      onPrimary: job == null ? null : () => _publish(context, ref),
      child: job == null
          ? TkEmptyState(
              icon: TkIcons.clipboardText,
              title: l.draftEmpty,
              description: l.draftEmptyDesc,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                TkJobCard(
                  title: job.title,
                  icon: TkIcons.byName(category?.icon ?? 'wrench'),
                  city: job.address,
                  needBy: _needBy(job.dateMode, job.dateStart, job.dateEnd, l),
                  price: job.budgetAmount,
                  // Зачёркнутая стартовая появится, когда пойдут ставки:
                  // до этого она равна текущей цене и выглядит опечаткой.
                  startPrice: null,
                  currency: job.currency,
                  isAuction: job.isAuction,
                  workersCount: job.workersCount,
                ),
                const SizedBox(height: 14),
                if (state.fieldErrors.isNotEmpty) _Problems(fields: state.fieldErrors),
                TkCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Line(
                          label: l.category,
                          value: category?.name.forLang(lang) ??
                              (job.openToAny ? l.letThemSuggest : '—')),
                      _Line(label: l.descriptionLabel, value: job.description),
                      _Line(label: l.place, value: job.address),
                      _Line(label: l.access, value: switch (job.access) {
                        'yes' => l.accessYes,
                        'no' => l.accessNo,
                        _ => l.accessUnknown,
                      }),
                      _Line(
                        label: l.when,
                        value: _needBy(job.dateMode, job.dateStart, job.dateEnd, l),
                      ),
                      _Line(
                        label: job.isAuction ? l.startPriceLabel : l.priceLabel,
                        value: tkMoney(job.budgetAmount, currency: job.currency),
                      ),
                      if (job.isAuction)
                        _Line(
                          label: l.modeAuction,
                          value: l.auctionSummary(job.auction?.durationH ?? 24,
                                  job.auction?.decisionWindowH ?? 12) +
                              (job.auction?.reserveAmount != null
                                  ? l.minSuffix +
                                      tkMoney(job.auction!.reserveAmount,
                                          currency: job.currency)
                                  : ''),
                        ),
                      if (job.workersCount > 0)
                        _Line(label: l.workers, value: l.workersCount(job.workersCount)),
                      _Line(label: l.viewsLabel, value: '—', last: true),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: TkRadius.cardR,
                  ),
                  child: Row(
                    children: [
                      TkIcon(TkIcons.pencil, size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.fixSomething,
                          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  String _needBy(String mode, DateTime? start, DateTime? end, AppLocalizations l) =>
      switch (mode) {
        'exact' => tkShortDate(start),
        'range' => '${tkShortDate(start)} – ${tkShortDate(end)}',
        _ => l.asap,
      };
}

/// Разбор от сервера: что именно не даёт опубликовать.
class _Problems extends StatelessWidget {
  const _Problems({required this.fields});
  final Map<String, String> fields;

  /// Названия полей на языке приложения: «geo: обязательно» человек не поймёт.
  Map<String, String> _titles(AppLocalizations l) => {
        'categoryId': l.category,
        'title': l.titleLabel,
        'description': l.descriptionLabel,
        'photos': l.photosLabel,
        'geo': l.place,
        'dates': l.datesLabel,
        'budgetAmount': l.priceLabel,
        'currency': l.currencyLabel,
        'auction': l.modeAuction,
        'auction.durationH': l.auctionDurationLabel,
        'auction.decisionWindowH': l.decisionWindowLabel,
        'auction.reserveAmount': l.reserveLabel,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final titles = _titles(l);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TkColors.error.withValues(alpha: 0.10),
          borderRadius: TkRadius.cardR,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.missingTitle, style: TkText.h3.copyWith(color: TkColors.error)),
            const SizedBox(height: 8),
            ...fields.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${titles[e.key] ?? e.key}: ${e.value}',
                    style: TkText.caption.copyWith(color: TkColors.error),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(label,
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(
                  value.isEmpty ? '—' : value,
                  style: TkText.body.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          if (!last) Divider(height: 18, color: scheme.outlineVariant),
        ],
      ),
    );
  }
}
