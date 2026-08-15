import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';

/// «Мой бизнес» — CRM исполнителя (ТЗ §3.1, прототип `crm_owner`).
///
/// Ничего не нужно заполнять руками: доход, воронка и клиентская база
/// собираются из завершённых сделок. Поэтому цифры всегда честные — и всегда
/// есть, начиная с первой работы.
final businessProvider = FutureProvider.family<Business, String>((ref, period) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const Business();
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).business(t, period: period));
});

class BusinessScreen extends ConsumerStatefulWidget {
  const BusinessScreen({super.key});

  @override
  ConsumerState<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends ConsumerState<BusinessScreen> {
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
    final data = ref.watch(businessProvider(_period));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой бизнес'),
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
                onRetry: () => ref.invalidate(businessProvider(_period)),
              ),
              data: (b) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(businessProvider(_period)),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  children: [
                    _IncomeCard(business: b),
                    const SizedBox(height: 12),
                    _FunnelCard(business: b),
                    const SizedBox(height: 12),
                    _ClientsCard(business: b),
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

/// Доход за период. Цифра без сравнения не говорит, стало лучше или хуже,
/// поэтому рядом идёт изменение к прошлому такому же отрезку.
class _IncomeCard extends StatelessWidget {
  const _IncomeCard({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grew = business.delta >= 0;

    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Доход', style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tkMoney(business.income, currency: business.currency),
                style: TkText.price.copyWith(fontSize: 28),
              ),
              const SizedBox(width: 10),
              if (business.deltaComparable)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '${grew ? '+' : ''}${business.delta}%',
                    style: TkText.caption.copyWith(
                      color: grew ? TkColors.success : TkColors.error,
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
                child: _Metric(
                  label: 'Сделок',
                  value: '${business.deals}',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Средний чек',
                  value: tkMoney(business.average, currency: business.currency),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Воронка: где теряются заказы. Подсвечиваем долю побед — именно она обычно
/// объясняет, почему работы мало.
class _FunnelCard extends StatelessWidget {
  const _FunnelCard({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = (business.winRate * 100).round();

    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Воронка', style: TkText.h3),
          const SizedBox(height: 10),
          _Step(label: 'Откликнулся', value: business.offers, total: business.offers),
          _Step(label: 'Выбрали', value: business.won, total: business.offers),
          _Step(label: 'Завершил', value: business.completed, total: business.offers),
          if (business.offers > 0) ...[
            const SizedBox(height: 10),
            Text(
              percent >= 15
                  ? 'Вы выигрываете $percent% откликов — это хороший результат.'
                  : 'Вы выигрываете $percent% откликов. Помогают фотографии техники, '
                      'быстрый отклик и отзывы: заказчик выбирает по ним.',
              style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.value, required this.total});

  final String label;
  final int value;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final share = total == 0 ? 0.0 : value / total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: TkText.body)),
              Text('$value', style: TkText.body.copyWith(fontWeight: FontWeight.w600)),
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
  }
}

/// Клиентская база: с кем работал, сколько раз и на какую сумму.
class _ClientsCard extends StatelessWidget {
  const _ClientsCard({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Клиенты', style: TkText.h3),
          const SizedBox(height: 8),
          if (business.clients.isEmpty)
            Text(
              'Пока пусто. После первой завершённой сделки заказчик появится здесь — '
              'вместе с суммой и датой.',
              style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            for (final c in business.clients) ...[
              InkWell(
                onTap: () => context.push('/users/${c.userId}'),
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
                                    c.name.isEmpty ? 'Заказчик' : c.name,
                                    style: TkText.body.copyWith(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (c.regular) ...[
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
                              '${c.deals} ${tkPlural(c.deals, 'сделка', 'сделки', 'сделок')}'
                              '${c.last != null ? ' · ${tkShortDate(c.last)}' : ''}',
                              style: TkText.caption
                                  .copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        tkMoney(c.total, currency: business.currency),
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
