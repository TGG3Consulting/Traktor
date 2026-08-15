import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_refresh.dart';
import '../auth/auth_controller.dart';
import 'deal/deal_providers.dart';
import '../chat/open_chat.dart';
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
  const JobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobProvider(jobId));
    final myId = ref.watch(sessionUserIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Задание'),
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20,
              color: Theme.of(context).colorScheme.onSurface),
        ),
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
                      child: Text('Фиксированная цена',
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
              const SizedBox(height: 16),
              TkCard(
                child: Column(
                  children: [
                    _Line(
                      label: 'Категория',
                      value: category?.name.forLang(lang) ??
                          (job.openToAny ? 'Исполнитель предложит технику' : '—'),
                    ),
                    if (job.params.isNotEmpty)
                      ...job.params.entries.map((e) => _Line(
                            label: tkSpecTitle(category, e.key, lang),
                            value: tkSpecValue(category, e.key, e.value),
                          )),
                    _Line(label: 'Подъезд', value: switch (job.access) {
                      'yes' => 'Есть',
                      'no' => 'Нет',
                      _ => 'Не уточнён',
                    }),
                    _Line(label: 'Когда', value: _needBy(job)),
                    _Line(
                      label: 'Место',
                      value: isMine ? job.address : _approximate(job.address),
                      last: job.workersCount == 0,
                    ),
                    if (job.workersCount > 0)
                      _Line(label: 'Разнорабочие', value: '${job.workersCount} чел.', last: true),
                  ],
                ),
              ),
              if (job.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Что нужно сделать', style: TkText.h3),
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
                  Text(
                      '${job.offersCount} '
                      '${tkPlural(job.offersCount, 'отклик', 'отклика', 'откликов')}',
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
                          'Ваша минимальная цена: '
                          '${tkMoney(job.auction!.reserveAmount, currency: job.currency)}. '
                          'Исполнители её не видят.',
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

  String _needBy(Job j) => switch (j.dateMode) {
        'exact' => tkShortDate(j.dateStart),
        'range' => '${tkShortDate(j.dateStart)} – ${tkShortDate(j.dateEnd)}',
        _ => 'Как можно скорее',
      };

  /// До сделки исполнитель видит только район (ТЗ §2.8).
  String _approximate(String address) {
    if (address.isEmpty) return 'Уточняется';
    final parts = address.split(',');
    return parts.length > 1 ? '${parts.first.trim()} (примерно)' : '$address (примерно)';
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
    // Исполнитель выбран — заказчику остаётся подтвердить и работать.
    if (job.status == JobStatus.dealPending) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => _confirmDeal(context, ref),
          child: const Text('Подтвердить сделку'),
        ),
      );
    }
    final deal = ref.watch(dealByJobProvider(job.id)).valueOrNull;
    if (deal != null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => context.go('/deals/${deal.id}'),
          child: const Text('Открыть сделку'),
        ),
      );
    }
    if (!_open) {
      return Text(
        'Задание закрыто',
        textAlign: TextAlign.center,
        style: TkText.caption.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _confirmCancel(context, ref),
            child: const Text('Снять задание'),
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
                ? 'Смотреть торг'
                : (job.offersCount > 0 ? 'Отклики (${job.offersCount})' : 'Откликов пока нет')),
          ),
        ),
      ],
    );
  }

  Widget _executorActions(BuildContext context, WidgetRef ref, ColorScheme scheme) {
    // Исполнителя выбрали — дальше вся работа идёт на экране сделки.
    final deal = ref.watch(dealByJobProvider(job.id)).valueOrNull;
    if (deal != null && deal.ownerId != '') {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => context.go('/deals/${deal.id}'),
          child: const Text('Открыть сделку'),
        ),
      );
    }
    if (!_open) {
      return Text(
        'Задание больше не принимает отклики',
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
              child: const Text('Перейти к торгу'),
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
                ? 'Заказчик предложил ${tkMoney(mine.clientCounterPrice, currency: job.currency)} — '
                    'примите или предложите своё'
                : 'Ваше предложение: ${tkMoney(mine.price, currency: job.currency)}',
            textAlign: TextAlign.center,
            style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _withdraw(context, ref, mine.id),
                  child: const Text('Снять'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _openOfferSheet(context, existing: mine),
                  child: const Text('Изменить'),
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
            child: Text('Откликнуться · ${tkMoney(job.budgetAmount, currency: job.currency)}'),
          ),
        ),
      ],
    );
  }

  Future<void> _openOfferSheet(BuildContext context, {Offer? existing}) async {
    final sent = await showOfferSheet(
      context,
      jobId: job.id,
      jobPrice: job.budgetAmount ?? 0,
      currency: job.currency,
      existing: existing,
    );
    if (sent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Предложение отправлено заказчику')),
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
          const SnackBar(content: Text('Предложение снято')),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Снять задание?'),
        content: const Text(
          'Оно исчезнет из ленты, а откликнувшиеся исполнители получат уведомление. '
          'Вернуть задание можно будет только созданием нового.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Оставить')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TkColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Снять'),
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
          const SnackBar(content: Text('Задание снято')),
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
            left == null ? 'Аукцион' : 'До финиша ${tkTimeLeft(left)}',
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
