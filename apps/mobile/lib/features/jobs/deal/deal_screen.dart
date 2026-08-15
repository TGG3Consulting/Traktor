import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

import '../job_detail_screen.dart';
import '../../chat/open_chat.dart';
import '../../disputes/dispute_providers.dart';
import '../../disputes/dispute_sheet.dart';
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
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.dealTitle),
        leading: IconButton(
          tooltip: l.back,
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
    final l = AppLocalizations.of(context);
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
                  Text(l.priceFixed,
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
                      ? l.acceptanceOwner(tkShortDate(deal.acceptanceDeadline))
                      : l.acceptanceClient(tkShortDate(deal.acceptanceDeadline)),
                ),
              ],
              if (deal.status == 'cancelled' && deal.cancelReason.isNotEmpty) ...[
                const SizedBox(height: 14),
                _Banner(
                  color: TkColors.error,
                  icon: TkIcons.warning,
                  text: l.dealCancelledWith(deal.cancelReason),
                ),
              ],
              // Спор виден обеим сторонам: и жалоба, и решение модератора.
              _DisputeBanner(dealId: deal.id),
              if (deal.status == 'completed') ...[
                const SizedBox(height: 14),
                _Banner(
                  color: TkColors.success,
                  icon: TkIcons.checkCircle,
                  text: l.bothRateHint,
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

  /// Шаги сделки. Собираются на месте: подписи зависят от языка, а список
  /// с переводами нельзя объявить константой.
  List<(String, String)> _steps(AppLocalizations l) => [
        ('confirmed', l.stConfirmed),
        ('on_the_way', l.stOnTheWay),
        ('in_progress', l.stInProgress),
        ('work_done', l.finishWork),
        ('completed', l.stAccepted),
      ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final passed = {for (final e in deal.timeline) e.status: e};
    final steps = _steps(l);
    final currentIndex = steps.indexWhere((s) => s.$1 == deal.status);

    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            _Step(
              title: steps[i].$2,
              event: passed[steps[i].$1],
              done: passed.containsKey(steps[i].$1),
              current: i == currentIndex,
              last: i == steps.length - 1,
            ),
          ],
          if (deal.status == 'cancelled')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                l.stCancelled,
                style: TkText.caption.copyWith(
                  color: scheme.onSurfaceVariant,
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
                      _when(event!.at, AppLocalizations.of(context)),
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

  String _when(DateTime at, AppLocalizations l) {
    final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final today = DateTime.now();
    if (at.year == today.year && at.month == today.month && at.day == today.day) {
      return l.todayAt(time);
    }
    return '${tkShortDate(at)} $time';
  }
}

/// Контакты сторон. Телефоны раскрываются только в сделке (ТЗ §2.11) — до неё
/// площадка их прячет, чтобы договорённости не уходили мимо.
class _Contacts extends ConsumerWidget {
  const _Contacts({required this.deal, required this.isOwner});

  final Deal deal;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
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
                Text(isOwner ? deal.clientName : deal.ownerName, style: TkText.h3),
                Text(
                  l.phoneLater,
                  style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // В сделке переписка уже без маскировки — это основной канал
          // связи по ходу работы (ТЗ §2.11, прототип: кнопка «Чат»).
          IconButton(
            tooltip: l.writeMessage,
            onPressed: () => openChatAndGo(context, ref, deal.jobId,
                ownerId: isOwner ? null : deal.ownerId),
            icon: TkIcon(TkIcons.chatCircle, size: 20, color: scheme.onSurfaceVariant),
          ),
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
  (String status, String label)? _nextStep(AppLocalizations l) {
    if (deal.isClosed) return null;
    if (widget.isOwner) {
      return switch (deal.status) {
        'confirmed' => ('on_the_way', l.goOnTheWay),
        'on_the_way' => ('in_progress', l.startWork),
        'in_progress' => ('work_done', l.finishWork),
        _ => null,
      };
    }
    return switch (deal.status) {
      'work_done' => ('completed', l.acceptWork),
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
    final l = AppLocalizations.of(context);
    final next = _nextStep(l);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: deal.isClosed
            // Завершённая работа ведёт к взаимной оценке (ТЗ §2.13): без неё
            // рейтинг не набирается, а он — главный капитал исполнителя.
            ? (deal.status == 'completed'
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.dealDone,
                        textAlign: TextAlign.center,
                        style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () => context.push('/deals/${deal.id}/review'),
                        child: Text(l.rateIt),
                      ),
                    ],
                  )
                : Text(
                    l.stCancelled,
                    textAlign: TextAlign.center,
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                  ))
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
                          ? l.waitingClient
                          : l.waitingOwner,
                      textAlign: TextAlign.center,
                      style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Спор — не жалоба «в никуда», а обращение к арбитру:
                      // модератор увидит переписку, фото и отметки времени.
                      TextButton(
                        onPressed: _busy ? null : () => showDisputeSheet(context, dealId: deal.id),
                        child: Text(l.haveProblems,
                            style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _confirmCancel,
                        child: Text(l.cancelDeal,
                            style: TkText.caption.copyWith(color: TkColors.error)),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  /// Отмена после подтверждения — тяжёлое действие: у второй стороны сорван
  /// день. Поэтому причина обязательна и последствия названы прямо.
  Future<void> _confirmCancel() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.cancelDealQ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.cancelDealBody),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(hintText: l.cancelReason),
              maxLength: 200,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.keepIt)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TkColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.cancelDeal),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.cancelReasonHint)),
      );
      return;
    }
    await _run(() => ref
        .read(dealActionsProvider)
        .cancel(deal.jobId, deal.id, controller.text.trim()));
  }
}


/// Плашка спора: пока идёт разбор — что именно оспаривается, после решения —
/// исход и обоснование модератора. Обе стороны видят один и тот же текст.
class _DisputeBanner extends ConsumerWidget {
  const _DisputeBanner({required this.dealId});

  final String dealId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final dispute = ref.watch(disputeOfDealProvider(dealId)).valueOrNull;
    if (dispute == null) return const SizedBox.shrink();

    final open = dispute.isOpen;
    final color = open ? TkColors.warning : TkColors.info;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: TkRadius.cardR,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TkIcon(TkIcons.scales, size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  open ? l.disputeOngoing : l.disputeResolvedWith(dispute.outcomeLabel),
                  style: TkText.body.copyWith(fontWeight: FontWeight.w600, color: color),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              open ? dispute.reason : dispute.resolution,
              style: TkText.caption.copyWith(color: scheme.onSurface),
            ),
            if (open) ...[
              const SizedBox(height: 6),
              Text(
                l.disputeExplain,
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
