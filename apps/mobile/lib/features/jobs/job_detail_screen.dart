import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

import '../../core/session_refresh.dart';
import '../../core/share_link.dart';
import '../auth/auth_controller.dart';
import 'deal/deal_providers.dart';
import '../chat/open_chat.dart';
import '../complaints/complaint_sheet.dart';
import 'jobs_providers.dart';
import 'offers/offer_sheet.dart';
import 'offers/offers_providers.dart';
import 'spec_labels.dart';

/// Деталка задания (ТЗ §2.8, прототип `job_fixed` / `auction`).
///
/// Один экран для обеих ролей: заказчик видит своё задание с управлением,
/// исполнитель — условия и кнопку отклика. Резервную цену аукциона сервер
/// исполнителю не отдаёт вовсе, поэтому её нельзя показать по ошибке.
class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.jobId, this.embedded = false});

  final String jobId;

  /// Встроенный режим — правая колонка ленты на десктопе (ТЗ §4.2). Кнопки
  /// «назад» там нет: экран не открывался, а сменил содержимое.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobProvider(jobId));
    final myId = ref.watch(sessionUserIdProvider);
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.jobTitle),
        automaticallyImplyLeading: false,
        leading: embedded
            ? null
            : IconButton(
                tooltip: l.back,
                onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                icon: TkIcon(TkIcons.arrowLeft, size: 20,
                    color: Theme.of(context).colorScheme.onSurface),
              ),
        actions: [
          // Ссылками на задание делятся в мессенджерах — это основной канал
          // сарафана (ТЗ §4.2).
          TkShare.button(context, TkShare.job(jobId)),
          // Пожаловаться на чужое задание (ТЗ §4.1, п.6). На своё жаловаться
          // незачем, гостю сначала нужно войти — поэтому кнопка появляется
          // только у вошедшего и не у автора.
          if (myId.isNotEmpty && job.valueOrNull != null && job.value!.clientId != myId)
            IconButton(
              tooltip: l.complain,
              onPressed: () async {
                final sent = await showComplaintSheet(
                  context,
                  targetKind: 'job',
                  targetId: job.value!.id,
                  targetTitle: job.value!.title,
                );
                if (sent == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.complaintSent)),
                  );
                }
              },
              icon: TkIcon(TkIcons.flag, size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
        ],
      ),
      body: job.when(
        loading: () => const TkSkeletonList(count: 2),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(jobProvider(jobId)),
        ),
        data: (j) => _Content(job: j, isMine: j.clientId == myId),
      ),
    );
  }
}

/// Идентификатор текущего пользователя — по нему решаем, чьё это задание.
/// Профиль уже лежит в сессии, отдельный запрос не нужен.
final sessionUserIdProvider = Provider<String>((ref) {
  return ref.watch(sessionProvider)?.user.id ?? '';
});

class _Content extends ConsumerWidget {
  const _Content({required this.job, required this.isMine});

  final Job job;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final category = ref.watch(categoryByIdProvider(job.categoryId));
    final lang = Localizations.localeOf(context).languageCode;
    final l = AppLocalizations.of(context);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              Row(
                children: [
                  if (job.isAuction)
                    _AuctionTimer(endsAt: job.auction?.endsAt)
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: TkColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(l.fixedPrice,
                          style: TkText.caption.copyWith(
                              color: TkColors.primary, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(job.title, style: TkText.h1),
              const SizedBox(height: 8),
              Text(
                tkMoney(job.budgetAmount, currency: job.currency),
                style: TkText.price.copyWith(fontSize: 26, color: TkColors.primary),
              ),
              // Фотографии места: их видно раньше характеристик — по ним
              // исполнитель сразу понимает объём и подъезд (ТЗ §2.6).
              if (job.photos.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 160,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: job.photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => ClipRRect(
                      borderRadius: TkRadius.cardR,
                      child: Image.network(
                        job.photos[i],
                        width: 220,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 220,
                          color: scheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: TkIcon(TkIcons.image,
                              size: 24, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TkCard(
                child: Column(
                  children: [
                    _Line(
                      label: l.category,
                      value: category?.name.forLang(lang) ??
                          (job.openToAny ? l.ownerBringsUnit : '—'),
                    ),
                    if (job.params.isNotEmpty)
                      ...job.params.entries.map((e) => _Line(
                            label: tkSpecTitle(category, e.key, lang),
                            value: tkSpecValue(category, e.key, e.value, l),
                          )),
                    _Line(label: l.access, value: switch (job.access) {
                      'yes' => l.yes,
                      'no' => l.no,
                      _ => l.notSet,
                    }),
                    _Line(label: l.when, value: _needBy(job, l)),
                    _Line(
                      label: l.place,
                      value: isMine ? job.address : _approximate(job.address, l),
                      last: job.workersCount == 0,
                    ),
                    if (job.workersCount > 0)
                      _Line(
                          label: l.workers,
                          value: l.workersCount(job.workersCount),
                          last: true),
                  ],
                ),
              ),
              if (job.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(l.whatToDo, style: TkText.h3),
                const SizedBox(height: 6),
                Text(job.description, style: TkText.body),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  TkIcon(TkIcons.eye, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text('${job.viewsCount}',
                      style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 14),
                  TkIcon(TkIcons.chatCircle, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text(l.offersCount(job.offersCount),
                      style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
              if (isMine && job.auction?.reserveAmount != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: TkRadius.cardR,
                  ),
                  child: Row(
                    children: [
                      TkIcon(TkIcons.lock, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${l.reservePrefix}'
                          '${tkMoney(job.auction!.reserveAmount, currency: job.currency)}. '
                          '${l.reserveHidden}',
                          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        _Actions(job: job, isMine: isMine),
      ],
    );
  }

  String _needBy(Job j, AppLocalizations l) => switch (j.dateMode) {
        'exact' => tkShortDate(j.dateStart),
        'range' => '${tkShortDate(j.dateStart)} – ${tkShortDate(j.dateEnd)}',
        _ => l.asapWhen,
      };

  /// До сделки исполнитель видит только район (ТЗ §2.8).
  String _approximate(String address, AppLocalizations l) {
    if (address.isEmpty) return l.whenTbd;
    final parts = address.split(',');
    return l.approx(parts.length > 1 ? parts.first.trim() : address);
  }


}

/// Закреплённые действия внизу (ТЗ §2.8 sticky CTA).
class _Actions extends ConsumerWidget {
  const _Actions({required this.job, required this.isMine});

  final Job job;
  final bool isMine;

  bool get _open =>
      job.status == JobStatus.published ||
      job.status == JobStatus.collectingOffers ||
      job.status == JobStatus.bidding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: isMine ? _ownerActions(context, ref) : _executorActions(context, ref, scheme),
      ),
    );
  }

  Widget _ownerActions(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // Исполнитель выбран — заказчику остаётся подтвердить и работать.
    if (job.status == JobStatus.dealPending) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => _confirmDeal(context, ref),
          child: Text(l.confirmDeal),
        ),
      );
    }
    final deal = ref.watch(dealByJobProvider(job.id)).valueOrNull;
    if (deal != null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => context.go('/deals/${deal.id}'),
          child: Text(l.openDeal),
        ),
      );
    }
    if (!_open) {
      return Text(
        l.jobClosed,
        textAlign: TextAlign.center,
        style: TkText.caption.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _confirmCancel(context, ref),
            child: Text(l.cancelJob),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            // У аукциона решения принимаются в ленте торга, у фикс-цены — в
            // списке откликов.
            onPressed: job.isAuction
                ? () => context.go('/jobs/${job.id}/bids')
                : (job.offersCount > 0 ? () => context.go('/jobs/${job.id}/offers') : null),
            child: Text(job.isAuction
                ? l.watchAuction
                : (job.offersCount > 0 ? l.offersWith(job.offersCount) : l.noOffersYet)),
          ),
        ),
      ],
    );
  }

  Widget _executorActions(BuildContext context, WidgetRef ref, ColorScheme scheme) {
    final l = AppLocalizations.of(context);
    // Исполнителя выбрали — дальше вся работа идёт на экране сделки.
    final deal = ref.watch(dealByJobProvider(job.id)).valueOrNull;
    if (deal != null && deal.ownerId != '') {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => context.go('/deals/${deal.id}'),
          child: Text(l.openDeal),
        ),
      );
    }
    if (!_open) {
      return Text(
        l.jobNoMoreOffers,
        textAlign: TextAlign.center,
        style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    if (job.isAuction) {
      return Row(
        children: [
          TkChatIconButton(jobId: job.id),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: () => context.go('/jobs/${job.id}/bids'),
              child: Text(l.goToAuction),
            ),
          ),
        ],
      );
    }

    // Своё предложение уже отправлено — показываем его и даём изменить или
    // снять, вместо повторной кнопки «откликнуться».
    final mine = ref.watch(myOfferProvider(job.id)).valueOrNull;
    if (mine != null && mine.isActive) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            mine.hasCounter
                ? l.clientCountered(
                    tkMoney(mine.clientCounterPrice, currency: job.currency))
                : l.yourOffer(tkMoney(mine.price, currency: job.currency)),
            textAlign: TextAlign.center,
            style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _withdraw(context, ref, mine.id),
                  child: Text(l.withdraw),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _openOfferSheet(context, existing: mine),
                  child: Text(l.change),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Вопрос заказчику до отклика — обычное дело: «влезет ли техника во
    // двор» решает, стоит ли вообще откликаться (ТЗ §2.12).
    return Row(
      children: [
        TkChatIconButton(jobId: job.id),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: () => _openOfferSheet(context),
            child: Text(l.makeOfferWith(
                tkMoney(job.budgetAmount, currency: job.currency))),
          ),
        ),
      ],
    );
  }

  Future<void> _openOfferSheet(BuildContext context, {Offer? existing}) async {
    final l = AppLocalizations.of(context);
    final sent = await showOfferSheet(
      context,
      jobId: job.id,
      jobPrice: job.budgetAmount ?? 0,
      currency: job.currency,
      existing: existing,
    );
    if (sent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.offerSent)),
      );
    }
  }

  Future<void> _confirmDeal(BuildContext context, WidgetRef ref) async {
    try {
      final deal = await ref.read(dealActionsProvider).confirm(job.id);
      if (context.mounted) context.go('/deals/${deal.id}');
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.detail)));
      }
    }
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref, String offerId) async {
    try {
      await ref.read(offerActionsProvider).withdraw(job.id, offerId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).offerWithdrawn)),
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.detail)));
      }
    }
  }

  /// Снятие задания необратимо для исполнителей, которые уже откликнулись, —
  /// поэтому подтверждение с прямым описанием последствий (ТЗ §1.10).
  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.cancelJobQ),
        content: Text(l.cancelJobBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: Text(l.keepIt)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TkColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.withdraw),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(sessionRefresherProvider).run(
            (token) => ref.read(jobsApiProvider).cancel(
                  token,
                  job.id,
                  idempotencyKey: 'cancel-${job.id}',
                ),
          );
      ref.invalidate(jobProvider(job.id));
      ref.invalidate(myJobsProvider);
      ref.invalidate(feedProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.jobCancelled)),
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.detail)));
      }
    }
  }
}

/// Живой таймер аукциона (ТЗ §2.9): в последний час подсвечивается.
class _AuctionTimer extends StatefulWidget {
  const _AuctionTimer({this.endsAt});
  final DateTime? endsAt;

  @override
  State<_AuctionTimer> createState() => _AuctionTimerState();
}

class _AuctionTimerState extends State<_AuctionTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.endsAt != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.endsAt?.difference(DateTime.now());
    final urgent = left != null && left.inMinutes < 60 && !left.isNegative;
    final color = urgent ? TkColors.error : TkColors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TkIcon(TkIcons.lightning, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            left == null
                ? AppLocalizations.of(context).auction
                : AppLocalizations.of(context).auctionLeft(tkTimeLeft(left)),
            style: TkText.caption.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(label,
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(value.isEmpty ? '—' : value,
                    style: TkText.body.copyWith(fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
        if (!last) Divider(height: 1, color: scheme.outlineVariant),
      ],
    );
  }
}
