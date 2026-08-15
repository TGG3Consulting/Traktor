import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';

/// Календарь занятости исполнителя (ТЗ §3.1, прототип `crm_calendar`).
///
/// Дни с подтверждёнными сделками система знает сама, а отпуск и ремонт
/// техники человек отмечает руками. Без этого он получает ставки на даты, в
/// которые всё равно не выйдет, и вынужден отказываться уже после выбора.
final calendarProvider =
    FutureProvider.family<List<BusyDay>, String>((ref, month) async {
  final token = ref.watch(accessTokenProvider);
  if (token.isEmpty) return const [];
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).calendar(t, month: month));
});

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month;
  bool _busy = false;

  static const _weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
  static const _months = [
    'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
    'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  String _dayKey(DateTime day) => '${day.year}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// Тап по дню: свободный отмечаем «не работаю», свою отметку снимаем,
  /// день со сделкой открывает саму сделку.
  Future<void> _onDayTap(DateTime day, BusyDay? busy) async {
    if (busy != null && busy.fromDeal) {
      if (busy.dealId.isNotEmpty) context.push('/deals/${busy.dealId}');
      return;
    }
    if (_busy) return;

    setState(() => _busy = true);
    try {
      final api = ref.read(jobsApiProvider);
      final key = 'cal-${_dayKey(day)}-${DateTime.now().microsecondsSinceEpoch}';
      await ref.read(sessionRefresherProvider).run((t) async {
        if (busy == null) {
          await api.markBusy(t, _dayKey(day), idempotencyKey: key);
        } else {
          await api.unmarkBusy(t, _dayKey(day), idempotencyKey: key);
        }
      });
      ref.invalidate(calendarProvider(_monthKey));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не сохранилось: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = ref.watch(calendarProvider(_monthKey));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Занятость'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: days.when(
        loading: () => const TkSkeletonList(count: 2),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(calendarProvider(_monthKey)),
        ),
        data: (items) {
          final byDay = {for (final d in items) _dayKey(d.day): d};
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Прошлый месяц',
                    onPressed: () => setState(
                        () => _month = DateTime(_month.year, _month.month - 1)),
                    icon: TkIcon(TkIcons.caretLeft, size: 18, color: scheme.onSurface),
                  ),
                  Expanded(
                    child: Text(
                      '${_months[_month.month - 1]} ${_month.year}',
                      textAlign: TextAlign.center,
                      style: TkText.h3,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Следующий месяц',
                    onPressed: () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1)),
                    icon: TkIcon(TkIcons.caretRight, size: 18, color: scheme.onSurface),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final w in _weekdays)
                    Expanded(
                      child: Text(
                        w,
                        textAlign: TextAlign.center,
                        style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              _MonthGrid(
                month: _month,
                byDay: byDay,
                dayKey: _dayKey,
                onTap: _onDayTap,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const _Legend(color: TkColors.primary, label: 'Сделка'),
                  const SizedBox(width: 16),
                  _Legend(color: scheme.outline, label: 'Не работаю'),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Нажмите на свободный день, чтобы отметить «не работаю». Такие дни '
                'учитываются, когда вы делаете ставку: площадка предупредит, если '
                'дата уже занята. День со сделкой открывает саму сделку.',
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Занятые дни', style: TkText.h3),
                const SizedBox(height: 8),
                for (final d in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: d.fromDeal ? TkColors.primary : scheme.outline,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${tkShortDate(d.day)} — '
                            '${d.fromDeal ? (d.title.isEmpty ? 'сделка' : d.title) : (d.note.isEmpty ? 'не работаю' : d.note)}',
                            style: TkText.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Сетка месяца. Неделя начинается с понедельника — так принято в Армении.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.byDay,
    required this.dayKey,
    required this.onTap,
  });

  final DateTime month;
  final Map<String, BusyDay> byDay;
  final String Function(DateTime) dayKey;
  final void Function(DateTime day, BusyDay? busy) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // weekday: 1 = понедельник, поэтому пустых клеток ровно столько.
    final leading = first.weekday - 1;
    final today = DateTime.now();

    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(month.year, month.month, d);
      final busy = byDay[dayKey(day)];
      final isToday = day.year == today.year &&
          day.month == today.month &&
          day.day == today.day;

      cells.add(
        InkWell(
          onTap: () => onTap(day, busy),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.all(2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: busy == null
                  ? Colors.transparent
                  : (busy.fromDeal
                      ? TkColors.primary
                      : scheme.surfaceContainerHighest),
              borderRadius: BorderRadius.circular(8),
              border: isToday ? Border.all(color: TkColors.primary, width: 1.5) : null,
            ),
            child: Text(
              '$d',
              style: TkText.body.copyWith(
                color: busy?.fromDeal == true ? Colors.white : scheme.onSurface,
                fontWeight: busy != null ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1,
      children: cells,
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: TkText.caption),
      ],
    );
  }
}
