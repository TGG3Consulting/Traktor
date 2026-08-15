import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'complaint_providers.dart';

/// Сводка площадки (ТЗ §4.1, п.1).
///
/// Пока сводки нет, владелец узнаёт о проблеме от тех, кто уже ушёл. Здесь
/// видно главное: сколько людей пришло, сколько заданий опубликовано, какая
/// доля дошла до сделки и что скопилось в очередях модерации.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(platformStatsProvider(_days));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Площадка'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(platformStatsProvider(_days)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final d in const [7, 30, 90])
                  TkChip(
                    label: d == 7 ? 'Неделя' : (d == 30 ? 'Месяц' : 'Квартал'),
                    selected: _days == d,
                    onTap: () => setState(() => _days = d),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            stats.when(
              loading: () => const TkSkeletonList(count: 3),
              error: (e, _) => TkErrorState(
                message: '$e',
                onRetry: () => ref.invalidate(platformStatsProvider(_days)),
              ),
              data: (s) => _Body(stats: s, days: _days),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.stats, required this.days});

  final PlatformStats stats;
  final int days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final s = stats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                title: 'Новые люди',
                value: '${s.users}',
                prev: s.prevUsers,
                current: s.users,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Metric(
                title: 'Задания',
                value: '${s.jobs}',
                prev: s.prevJobs,
                current: s.jobs,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Metric(
                title: 'Сделки',
                value: '${s.deals}',
                prev: s.prevDeals,
                current: s.deals,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Metric(
                title: 'Оборот',
                value: tkMoney(s.gmv),
                prev: s.prevGmv,
                current: s.gmv,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Задание → сделка', style: TkText.h3),
              const SizedBox(height: 4),
              Text(
                'Главная цифра площадки: задания без исполнителя означают, '
                'что заказчик не вернётся.',
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${s.conversion}%', style: TkText.h1),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _Delta(current: s.conversion, prev: s.prevConversion, suffix: ' п.п.'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (s.conversion / 100).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Small(title: 'Завершено сделок', value: '${s.completed}'),
                  ),
                  Expanded(
                    child: _Small(title: 'Средний чек', value: tkMoney(s.avgCheck)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text('Очереди модерации', style: TkText.h3),
        const SizedBox(height: 8),
        TkCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const TkIcon(TkIcons.scales),
                title: const Text('Споры'),
                subtitle: Text(s.openDisputes == 0
                    ? 'Разбирать нечего'
                    : 'Ждут решения: ${s.openDisputes}'),
                trailing: const TkIcon(TkIcons.caretRight, size: 16),
                onTap: () => context.push('/moderation/disputes'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const TkIcon(TkIcons.flag),
                title: const Text('Жалобы'),
                subtitle: Text(s.openComplaints == 0
                    ? 'Жалоб нет'
                    : 'Ждут разбора: ${s.openComplaints}'),
                trailing: const TkIcon(TkIcons.caretRight, size: 16),
                onTap: () => context.push('/moderation/complaints'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const TkIcon(TkIcons.shield),
                title: const Text('Проверка техники'),
                trailing: const TkIcon(TkIcons.caretRight, size: 16),
                onTap: () => context.push('/moderation'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Период: последние $days дн. Сравнение — с таким же отрезком до него.',
          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.title,
    required this.value,
    required this.current,
    required this.prev,
  });

  final String title;
  final String value;
  final int current;
  final int prev;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(value, style: TkText.h2, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          _Delta(current: current, prev: prev),
        ],
      ),
    );
  }
}

/// Изменение к прошлому периоду. Цифра без сравнения ничего не говорит:
/// «120 заданий» — это много или мало, понятно только рядом с прошлым месяцем.
class _Delta extends StatelessWidget {
  const _Delta({required this.current, required this.prev, this.suffix = '%'});

  final int current;
  final int prev;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (prev == 0 && current == 0) {
      return Text('без изменений',
          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant));
    }
    if (prev == 0) {
      return Text('впервые за период',
          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant));
    }

    final diff = suffix == '%'
        ? ((current - prev) / prev * 100).round()
        : current - prev;
    if (diff == 0) {
      return Text('без изменений',
          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant));
    }
    final up = diff > 0;
    final color = up ? TkColors.success : TkColors.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TkIcon(up ? TkIcons.chartLineUp : TkIcons.chartLineDown, size: 14, color: color),
        const SizedBox(width: 4),
        Text('${up ? '+' : ''}$diff$suffix',
            style: TkText.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Small extends StatelessWidget {
  const _Small({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: TkText.body.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
