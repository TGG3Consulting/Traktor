import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../job_detail_screen.dart';
import '../jobs_providers.dart';
import 'deal_providers.dart';

/// Экран сделки — общий для обеих сторон (ТЗ §2.11).
///
/// Главное здесь — таймлайн: обе стороны видят одну и ту же историю с
/// временными отметками, поэтому «я выехал час назад» перестаёт быть вопросом
/// доверия. Кнопка внизу всегда одна: следующий разумный шаг для этой роли.
class DealScreen extends ConsumerWidget {
  const DealScreen({super.key, required this.dealId});

  final String dealId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deal = ref.watch(dealProvider(dealId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сделка'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: deal.when(
        loading: () => const TkSkeletonList(count: 2),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(dealProvider(dealId)),
        ),
        data: (d) => _Content(deal: d),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final myId = ref.watch(sessionUserIdProvider);
    final isOwner = myId == deal.ownerId;
    final job = ref.watch(jobProvider(deal.jobId)).valueOrNull;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              if (job != null) ...[
                Text(job.title, style: TkText.h2),
                const SizedBox(height: 4),
                Text(job.address,
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Text(
                    tkMoney(deal.price, currency: deal.currency),
                    style: TkText.price.copyWith(fontSize: 26, color: TkColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Text('цена зафиксирована',
                      style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 16),
              _Timeline(deal: deal),
              if (deal.status == 'work_done' && deal.acceptanceDeadline != null) ...[
                const SizedBox(height: 14),
                _Banner(
                  color: TkColors.info,
                  icon: TkIcons.hourglass,
                  text: isOwner
                      ? 'Заказчик проверяет работу. Если не ответит до '
                          '${tkShortDate(deal.acceptanceDeadline)}, приёмка пройдёт автоматически.'
                      : 'Проверьте работу. Если не ответить до '
                          '${tkShortDate(deal.acceptanceDeadline)}, она будет принята автоматически.',
                ),
              ],
              if (deal.status == 'cancelled' && deal.cancelReason.isNotEmpty) ...[
                const SizedBox(height: 14),
                _Banner(
                  color: TkColors.error,
                  icon: TkIcons.warning,
                  text: 'Сделка отменена: ${deal.cancelReason}',
                ),
              ],
              if (deal.status == 'completed') ...[
                const SizedBox(height: 14),
                const _Banner(
                  color: TkColors.success,
                  icon: TkIcons.checkCircle,
                  text: 'Работа принята. Оценки сторон появятся в следующем обновлении.',
                ),
              ],
              const SizedBox(height: 16),
              _Contacts(deal: deal, isOwner: isOwner),
            ],
          ),
        ),
        _Actions(deal: deal, isOwner: isOwner),
      ],
    );
  }
}

/// Таймлайн-степпер: пройденные шаги с отметками времени, будущие — бледные.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.deal});

  final Deal deal;

  static const _steps = [
    ('confirmed', 'Подтверждено'),
    ('on_the_way', 'Исполнитель выехал'),
    ('in_progress', 'Работа идёт'),
    ('work_done', 'Работа завершена'),
    ('completed', 'Принято заказчиком'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final passed = {for (final e in deal.timeline) e.status: e};
    final currentIndex = _steps.indexWhere((s) => s.$1 == deal.status);

    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            _Step(
              title: _steps[i].$2,
              event: passed[_steps[i].$1],
              done: passed.containsKey(_steps[i].$1),
              current: i == currentIndex,
              last: i == _steps.length - 1,
            ),
          ],
          if (deal.status == 'cancelled' || deal.status == 'disputed')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                deal.status == 'cancelled' ? 'Сделка отменена' : 'Открыт спор',
                style: TkText.caption.copyWith(
                  color: deal.status == 'cancelled' ? scheme.onSurfaceVariant : TkColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.title,
    required this.done,
    required this.current,
    required this.last,
    this.event,
  });

  final String title;
  final DealEvent? event;
  final bool done;
  final bool current;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = done ? TkColors.primary : scheme.outlineVariant;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: done ? TkColors.primary : Colors.transparent,
                  border: Border.all(color: color, width: 2),
                  shape: BoxShape.circle,
                ),
                child: done
                    ? const Center(child: TkIcon(TkIcons.check, size: 10, color: Colors.white))
                    : null,
              ),
              if (!last)
                Expanded(child: Container(width: 2, color: color)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TkText.body.copyWith(
                      fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                      color: done ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                  if (event != null)
                    Text(
                      _when(event!.at),
                      style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  if (event != null && event!.note.isNotEmpty)
                    Text(event!.note, style: TkText.caption),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _when(DateTime at) {
    final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final today = DateTime.now();
    if (at.year == today.year && at.month == today.month && at.day == today.day) {
      return 'сегодня $time';
    }
    return '${tkShortDate(at)} $time';
  }
}

/// Контакты сторон. Телефоны раскрываются только в сделке (ТЗ §2.11) — до неё
/// площадка их прячет, чтобы договорённости не уходили мимо.
class _Contacts extends StatelessWidget {
  const _Contacts({required this.deal, required this.isOwner});

  final Deal deal;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TkCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: scheme.surfaceContainerHighest,
            child: TkIcon(TkIcons.user, size: 20, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isOwner ? 'Заказчик' : 'Исполнитель', style: TkText.h3),
                Text(
                  'Телефон появится здесь вместе с профилями сторон',
                  style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TkIcon(TkIcons.phone, size: 20, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});

  final Color color;
  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: TkRadius.cardR,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TkIcon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TkText.caption.copyWith(color: color))),
        ],
      ),
    );
  }
}

/// Кнопка следующего шага — своя для каждой роли и состояния.
class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.deal, required this.isOwner});

  final Deal deal;
  final bool isOwner;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _busy = false;

  Deal get deal => widget.deal;

  /// Следующий шаг: что именно предложить нажать этому человеку сейчас.
  (String status, String label)? get _next {
    if (deal.isClosed) return null;
    if (widget.isOwner) {
      return switch (deal.status) {
        'confirmed' => ('on_the_way', 'Выехал на объект'),
        'on_the_way' => ('in_progress', 'Начал работу'),
        'in_progress' => ('work_done', 'Работа завершена'),
        _ => null,
      };
    }
    return switch (deal.status) {
      'work_done' => ('completed', 'Принять работу'),
      _ => null,
    };
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.detail)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final next = _next;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: deal.isClosed
            ? Text(
                deal.status == 'completed' ? 'Сделка завершена' : 'Сделка отменена',
                textAlign: TextAlign.center,
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                // Панель тянется на всю ширину: иначе она сжимается по кнопке
                // и на широком экране выглядит обрезанной полоской.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (next != null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() => ref
                                .read(dealActionsProvider)
                                .step(deal.jobId, deal.id, next.$1)),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(next.$2),
                      ),
                    )
                  else
                    Text(
                      widget.isOwner
                          ? 'Ждём действий заказчика'
                          : 'Ждём, пока исполнитель выполнит работу',
                      textAlign: TextAlign.center,
                      style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _confirmCancel,
                    child: Text('Отменить сделку',
                        style: TkText.caption.copyWith(color: TkColors.error)),
                  ),
                ],
              ),
      ),
    );
  }

  /// Отмена после подтверждения — тяжёлое действие: у второй стороны сорван
  /// день. Поэтому причина обязательна и последствия названы прямо.
  Future<void> _confirmCancel() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить сделку?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Вторая сторона получит уведомление с вашей причиной. '
              'Частые отмены отражаются на рейтинге.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'Причина отмены'),
              maxLength: 200,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Оставить')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TkColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отменить сделку'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите причину — её увидит вторая сторона')),
      );
      return;
    }
    await _run(() => ref
        .read(dealActionsProvider)
        .cancel(deal.jobId, deal.id, controller.text.trim()));
  }
}
