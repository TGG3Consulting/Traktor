import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

import '../job_detail_screen.dart';
import '../../../core/realtime.dart';
import '../jobs_providers.dart';
import 'auction_providers.dart';

/// Экран обратного аукциона (ТЗ §2.9) — ключевой экран продукта.
///
/// Сверху живой таймер и текущая лучшая цена, ниже анонимная лента ставок,
/// внизу — панель своей ставки. Имена участников скрыты до конца торга: это
/// защита от сговора и переманивания, поэтому и в интерфейсе их нет.
class AuctionScreen extends ConsumerStatefulWidget {
  const AuctionScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<AuctionScreen> createState() => _AuctionScreenState();
}

class _AuctionScreenState extends ConsumerState<AuctionScreen> {
  void Function()? _unsubscribe;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  /// Подписка на канал задания: чужая ставка обновляет ленту и таймер сразу,
  /// без обновления экрана вручную (ADR-6). Если канал недоступен, экран
  /// работает как раньше — данные подтягиваются при заходе.
  Future<void> _listen() async {
    final off = await ref.read(realtimeProvider).subscribe(
      'job:${widget.jobId}',
      (event) {
        if (!mounted) return;
        ref.invalidate(jobBidsProvider(widget.jobId));
        // Продление торга меняет время финиша — карточку задания тоже
        // перечитываем, иначе таймер покажет старый срок.
        if (event['extended'] == true) ref.invalidate(jobProvider(widget.jobId));
      },
    );
    if (!mounted) {
      off();
      return;
    }
    _unsubscribe = off;
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final jobId = widget.jobId;
    final job = ref.watch(jobProvider(jobId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.auctionTitle),
        leading: IconButton(
          tooltip: l.back,
          onPressed: () => context.canPop() ? context.pop() : context.go('/jobs/$jobId'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
      ),
      body: job.when(
        loading: () => const TkSkeletonList(count: 3),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(jobProvider(jobId)),
        ),
        data: (j) => _Content(job: j),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final bids = ref.watch(jobBidsProvider(job.id));
    final myId = ref.watch(sessionUserIdProvider);
    final isMine = job.clientId == myId;

    return Column(
      children: [
        _Header(job: job, bids: bids.valueOrNull ?? const []),
        Expanded(
          child: bids.when(
            loading: () => const TkSkeletonList(count: 3),
            error: (e, _) => TkErrorState(
              message: '$e',
              onRetry: () => ref.invalidate(jobBidsProvider(job.id)),
            ),
            data: (list) {
              final active = list.where((b) => b.isActive || b.isWinner).toList();
              if (active.isEmpty) {
                return TkEmptyState(
                  icon: TkIcons.lightning,
                  title: l.noBidsYet,
                  description: l.noBidsDesc,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(jobBidsProvider(job.id)),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  itemCount: active.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _BidRow(
                    bid: active[i],
                    canChoose: isMine && job.status == JobStatus.deciding,
                    onChoose: () => _choose(context, ref, active[i]),
                  ),
                ),
              );
            },
          ),
        ),
        if (isMine)
          _OwnerPanel(job: job)
        else
          _BidPanel(job: job, best: _bestPrice(bids.valueOrNull ?? const [])),
      ],
    );
  }

  int? _bestPrice(List<BidRow> bids) {
    for (final b in bids) {
      if (b.isActive) return b.price;
    }
    return null;
  }

  Future<void> _choose(BuildContext context, WidgetRef ref, BidRow bid) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.chooseThisQ),
        content: Text(
          l.chooseBidBody(tkMoney(bid.price, currency: bid.currency)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.choose)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(auctionActionsProvider).accept(job.id, bid.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.contractorChosenConfirm)),
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.detail)));
      }
    }
  }
}

/// Закреплённая шапка: таймер, лучшая цена, число участников.
class _Header extends StatefulWidget {
  const _Header({required this.job, required this.bids});

  final Job job;
  final List<BidRow> bids;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final endsAt = widget.job.auction?.endsAt;
    final left = endsAt?.difference(DateTime.now());
    final finishing = left != null && !left.isNegative && left.inMinutes < 5;
    final over = left == null || left.isNegative;

    final active = widget.bids.where((b) => b.isActive || b.isWinner).toList();
    final best = active.isEmpty ? null : active.first.price;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TkIcon(TkIcons.lightning, size: 16,
                  color: finishing ? TkColors.error : TkColors.warning),
              const SizedBox(width: 6),
              Text(
                over ? l.auctionOver : l.auctionLeftLong(tkTimeLeft(left)),
                style: TkText.h3.copyWith(
                  color: finishing ? TkColors.error : TkColors.warning,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Text(l.bidsCount(active.length),
                  style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tkMoney(best ?? widget.job.budgetAmount, currency: widget.job.currency),
                style: TkText.price.copyWith(fontSize: 28, color: TkColors.primary),
              ),
              if (best != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    tkMoney(widget.job.budgetAmount, currency: widget.job.currency),
                    style: TkText.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (finishing) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TkColors.error.withValues(alpha: 0.12),
                borderRadius: TkRadius.cardR,
              ),
              child: Text(
                l.finalCountdown,
                style: TkText.caption.copyWith(color: TkColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Строка ленты: место, цена, время. Имя участника не показываем.
class _BidRow extends StatelessWidget {
  const _BidRow({required this.bid, required this.canChoose, required this.onChoose});

  final BidRow bid;
  final bool canChoose;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final leading = bid.rank == 1 || bid.isWinner;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: leading ? TkColors.primary.withValues(alpha: 0.08) : scheme.surface,
        borderRadius: TkRadius.cardR,
        border: Border.all(
          color: leading ? TkColors.primary : scheme.outlineVariant,
          width: leading ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    bid.mine ? l.yourBid : l.contractorNo(bid.rank),
                    style: TkText.body.copyWith(
                      fontWeight: bid.mine ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (bid.isWinner) ...[
                    const SizedBox(width: 6),
                    Text(l.winner,
                        style: TkText.caption.copyWith(
                            color: TkColors.success, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
              if (bid.comment.isNotEmpty)
                Text(bid.comment,
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const Spacer(),
          Text(
            tkMoney(bid.price, currency: bid.currency),
            style: TkText.price.copyWith(
              fontSize: 18,
              color: leading ? TkColors.primary : scheme.onSurface,
            ),
          ),
          if (canChoose) ...[
            const SizedBox(width: 10),
            FilledButton(
              onPressed: onChoose,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
              ),
              child: Text(l.choose),
            ),
          ],
        ],
      ),
    );
  }
}

/// Панель заказчика: пока идёт торг — только наблюдение; в окне решения —
/// выбор из списка или отказ от всех.
class _OwnerPanel extends ConsumerWidget {
  const _OwnerPanel({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final deciding = job.status == JobStatus.deciding;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: deciding
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.auctionOverPick,
                    textAlign: TextAlign.center,
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _declineAll(context, ref),
                    child: Text(l.declineAll),
                  ),
                ],
              )
            : Text(
                l.auctionRunning,
                textAlign: TextAlign.center,
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
      ),
    );
  }

  Future<void> _declineAll(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.declineAllQ),
        content: Text(l.declineAllBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.back)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TkColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.declineAllYes),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(auctionActionsProvider).declineAll(job.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.jobClosedNow)),
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.detail)));
      }
    }
  }
}

/// Панель ставки исполнителя: поле суммы, быстрые шаги вниз и подтверждение.
class _BidPanel extends ConsumerStatefulWidget {
  const _BidPanel({required this.job, this.best});

  final Job job;
  final int? best;

  @override
  ConsumerState<_BidPanel> createState() => _BidPanelState();
}

class _BidPanelState extends ConsumerState<_BidPanel> {
  late final TextEditingController _price;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(text: '${_suggested()}');
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  /// Подсказанная цена: на тысячу ниже текущей лучшей, иначе стартовая.
  int _suggested() {
    final best = widget.best;
    if (best != null && best > 1000) return best - 1000;
    return widget.job.budgetAmount ?? 0;
  }

  int get _value => int.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  bool get _valid {
    if (_value <= 0) return false;
    final best = widget.best;
    if (best != null && _value >= best) return false;
    final start = widget.job.budgetAmount ?? 0;
    return start == 0 || _value >= (start * 0.3).round();
  }

  void _step(int delta) {
    final next = _value + delta;
    if (next <= 0) return;
    _price.text = '$next';
    setState(() {});
  }

  Future<void> _place() async {
    final l = AppLocalizations.of(context);
    // Ставка — обязательство: подтверждаем явно (ТЗ §2.9).
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.placeBidQ(tkMoney(_value, currency: widget.job.currency))),
        content: Text(l.placeBidBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true), child: Text(l.placeBid)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(auctionActionsProvider).place(widget.job.id, _value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.bidAccepted)),
        );
      }
    } on ValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.fields.values.join('\n'))));
      }
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
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final mine = ref.watch(myBidProvider(widget.job.id)).valueOrNull;
    final open = widget.job.status == JobStatus.bidding;

    if (!open) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Text(
            mine != null && mine.isWinner
                ? l.yourBidBest
                : l.auctionOver,
            textAlign: TextAlign.center,
            style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (mine != null && mine.isActive)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l.yourCurrentBid(tkMoney(mine.price, currency: mine.currency)),
                  textAlign: TextAlign.center,
                  style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(suffixText: '֏', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _step(-1000),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('−1 000'),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: () => _step(-5000),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('−5 000'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_valid && _value > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  widget.best != null && _value >= widget.best!
                      ? l.bidMustBeLower
                      : l.bidTooLow,
                  textAlign: TextAlign.center,
                  style: TkText.caption.copyWith(color: TkColors.error),
                ),
              ),
            FilledButton(
              onPressed: _valid && !_busy ? _place : null,
              child: _busy
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.makeBidWith(tkMoney(_value, currency: widget.job.currency))),
            ),
          ],
        ),
      ),
    );
  }
}
