import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_settings.dart';
import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';
import 'export_button.dart';

/// «Мои расходы» — CRM заказчика (ТЗ §3.2, прототип `crm_client`).
///
/// Показывает не только сумму, но и на что она ушла, и сколько сэкономил торг:
/// именно эта цифра отвечает на вопрос «зачем мне площадка».
final spendingProvider = FutureProvider.family<Spending, String>((ref, period) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const Spending();
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).spending(t, period: period));
});

class SpendingScreen extends ConsumerStatefulWidget {
  const SpendingScreen({super.key});

  @override
  ConsumerState<SpendingScreen> createState() => _SpendingScreenState();
}

class _SpendingScreenState extends ConsumerState<SpendingScreen> {
  String _period = 'month';

  static const _periods = {
    'week': 'Неделя',
    'month': 'Месяц',
    'quarter': 'Квартал',
    'year': 'Год',
    'all': 'Всё время',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = ref.watch(spendingProvider(_period));
    final lang = (ref.watch(appSettingsProvider).locale ?? const Locale('ru')).languageCode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои расходы'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                for (final entry in _periods.entries) ...[
                  TkChip(
                    label: entry.value,
                    selected: _period == entry.key,
                    onTap: () => setState(() => _period = entry.key),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: data.when(
              loading: () => const TkSkeletonList(count: 3),
              error: (e, _) => TkErrorState(
                message: '$e',
                onRetry: () => ref.invalidate(spendingProvider(_period)),
              ),
              data: (s) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(spendingProvider(_period)),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  children: [
                    _SpentCard(spending: s),
                    if (s.saved > 0) ...[
                      const SizedBox(height: 12),
                      _SavedCard(spending: s),
                    ],
                    if (s.byCategory.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _CategoriesCard(spending: s, lang: lang),
                    ],
                    const SizedBox(height: 12),
                    _OwnersCard(spending: s),
                    const SizedBox(height: 16),
                    ExportButton(period: _period, asOwner: false),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpentCard extends StatelessWidget {
  const _SpentCard({required this.spending});

  final Spending spending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // У расходов рост — не всегда хорошо, поэтому цвет обратный доходу:
    // выросли траты — красный, снизились — зелёный.
    final grew = spending.delta >= 0;

    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Потрачено', style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tkMoney(spending.spent, currency: spending.currency),
                style: TkText.price.copyWith(fontSize: 28),
              ),
              const SizedBox(width: 10),
              if (spending.deltaComparable)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '${grew ? '+' : ''}${spending.delta}%',
                    style: TkText.caption.copyWith(
                      color: grew ? TkColors.error : TkColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Metric(label: 'Заданий', value: '${spending.deals}'),
              ),
              Expanded(
                child: _Metric(
                  label: 'Средний чек',
                  value: tkMoney(spending.average, currency: spending.currency),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Экономия на торге — то, ради чего заказчик остаётся на площадке.
class _SavedCard extends StatelessWidget {
  const _SavedCard({required this.spending});

  final Spending spending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TkColors.success.withValues(alpha: 0.12),
        borderRadius: TkRadius.cardR,
      ),
      child: Row(
        children: [
          const TkIcon(TkIcons.chartLineDown, size: 22, color: TkColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Аукцион сэкономил ${tkMoney(spending.saved, currency: spending.currency)}',
                  style: TkText.body.copyWith(
                      fontWeight: FontWeight.w600, color: TkColors.success),
                ),
                Text(
                  'Разница между стартовой ценой заданий и той, по которой закрылись сделки',
                  style: TkText.caption.copyWith(color: TkColors.success),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// На что уходят деньги. Долю показываем полосой: круговая диаграмма на
/// телефоне читается хуже, чем список с полосками.
class _CategoriesCard extends ConsumerWidget {
  const _CategoriesCard({required this.spending, required this.lang});

  final Spending spending;
  final String lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final total = spending.byCategory.fold<int>(0, (sum, c) => sum + c.total);

    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('На что уходят деньги', style: TkText.h3),
          const SizedBox(height: 10),
          for (final c in spending.byCategory) ...[
            Builder(builder: (context) {
              final category = ref.watch(categoryByIdProvider(c.categoryId));
              final share = total == 0 ? 0.0 : c.total / total;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            category?.name.forLang(lang) ?? 'Другое',
                            style: TkText.body,
                          ),
                        ),
                        Text(
                          '${tkMoney(c.total, currency: spending.currency)}'
                          '  ·  ${(share * 100).round()}%',
                          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: share,
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                        valueColor: const AlwaysStoppedAnimation(TkColors.primary),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _OwnersCard extends StatelessWidget {
  const _OwnersCard({required this.spending});

  final Spending spending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Исполнители', style: TkText.h3),
          const SizedBox(height: 8),
          if (spending.owners.isEmpty)
            Text(
              'Пока пусто. После первой завершённой работы исполнитель появится '
              'здесь — можно будет позвать его снова.',
              style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            for (final o in spending.owners) ...[
              InkWell(
                onTap: () => context.push('/users/${o.userId}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    o.name.isEmpty ? 'Исполнитель' : o.name,
                                    style: TkText.body
                                        .copyWith(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (o.regular) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: TkColors.success,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('Постоянный',
                                        style: TextStyle(
                                            fontSize: 10, color: Colors.white)),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              '${o.deals} ${tkPlural(o.deals, 'работа', 'работы', 'работ')}'
                              '${o.last != null ? ' · ${tkShortDate(o.last)}' : ''}',
                              style: TkText.caption
                                  .copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        tkMoney(o.total, currency: spending.currency),
                        style: TkText.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: TkText.body.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
