import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    return WizardScaffold(
      step: 5,
      subtitle: 'Проверьте — так задание увидят исполнители',
      onBack: () => context.go('/jobs/create/4'),
      error: state.error,
      saving: state.saving,
      primaryLabel: 'Опубликовать',
      onPrimary: job == null ? null : () => _publish(context, ref),
      child: job == null
          ? const TkEmptyState(
              icon: TkIcons.clipboardText,
              title: 'Черновик пуст',
              description: 'Вернитесь на первый шаг и выберите вид работ',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                TkJobCard(
                  title: job.title,
                  icon: TkIcons.byName(category?.icon ?? 'wrench'),
                  city: job.address,
                  needBy: _needBy(job.dateMode, job.dateStart, job.dateEnd),
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
                      _Line(label: 'Категория', value: category?.name.forLang(lang) ??
                          (job.openToAny ? 'Пусть предложат сами' : '—')),
                      _Line(label: 'Описание', value: job.description),
                      _Line(label: 'Место', value: job.address),
                      _Line(label: 'Подъезд', value: switch (job.access) {
                        'yes' => 'Есть',
                        'no' => 'Нет',
                        _ => 'Не знаю',
                      }),
                      _Line(
                        label: 'Когда',
                        value: _needBy(job.dateMode, job.dateStart, job.dateEnd),
                      ),
                      _Line(
                        label: job.isAuction ? 'Стартовая цена' : 'Цена',
                        value: tkMoney(job.budgetAmount, currency: job.currency),
                      ),
                      if (job.isAuction)
                        _Line(
                          label: 'Аукцион',
                          value: '${job.auction?.durationH ?? 24} ч · '
                              'решение ${job.auction?.decisionWindowH ?? 12} ч'
                              '${job.auction?.reserveAmount != null ? ' · мин. '
                                  '${tkMoney(job.auction!.reserveAmount, currency: job.currency)}' : ''}',
                        ),
                      if (job.workersCount > 0)
                        _Line(label: 'Разнорабочие', value: '${job.workersCount} чел.'),
                      const _Line(label: 'Просмотры', value: '—', last: true),
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
                          'Что-то поправить? Вернитесь назад — черновик сохранён.',
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

  String _needBy(String mode, DateTime? start, DateTime? end) => switch (mode) {
        'exact' => tkShortDate(start),
        'range' => '${tkShortDate(start)} – ${tkShortDate(end)}',
        _ => 'Как можно скорее',
      };
}

/// Разбор от сервера: что именно не даёт опубликовать.
class _Problems extends StatelessWidget {
  const _Problems({required this.fields});
  final Map<String, String> fields;

  static const _titles = {
    'categoryId': 'Категория',
    'title': 'Название',
    'description': 'Описание',
    'photos': 'Фотографии',
    'geo': 'Место',
    'dates': 'Даты',
    'budgetAmount': 'Цена',
    'currency': 'Валюта',
    'auction': 'Аукцион',
    'auction.durationH': 'Длительность аукциона',
    'auction.decisionWindowH': 'Окно решения',
    'auction.reserveAmount': 'Минимальная цена',
  };

  @override
  Widget build(BuildContext context) {
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
            Text('Чего не хватает', style: TkText.h3.copyWith(color: TkColors.error)),
            const SizedBox(height: 8),
            ...fields.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${_titles[e.key] ?? e.key}: ${e.value}',
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
