import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

import 'create/wizard_controller.dart';
import 'jobs_providers.dart';

/// Главная заказчика — «Мои задания» (ТЗ §1.9, прототип `client_home`).
///
/// Черновики стоят в общем списке: по прототипу заказчик видит «Черновик ·
/// шаг 3 из 5 · продолжить» рядом с активными заданиями и возвращается в визард
/// одним касанием.
class ClientJobsTab extends ConsumerWidget {
  const ClientJobsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(myJobsProvider);
    final l = AppLocalizations.of(context);

    return jobs.when(
      loading: () => const TkSkeletonList(),
      error: (e, _) => TkErrorState(
        message: '$e',
        onRetry: () => ref.invalidate(myJobsProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return TkEmptyState(
            icon: TkIcons.clipboardText,
            title: l.myJobsEmptyTitle,
            description: l.myJobsEmptyDesc,
            actionLabel: l.createJob,
            onAction: () {
              ref.read(wizardControllerProvider.notifier).startNew();
              context.go('/jobs/create/1');
            },
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(myJobsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _MyJobCard(job: list[i]),
          ),
        );
      },
    );
  }
}

class _MyJobCard extends ConsumerWidget {
  const _MyJobCard({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final status = _status(job.status);

    return TkCard(
      onTap: () {
        if (job.isDraft) {
          ref.read(wizardControllerProvider.notifier).resume(job);
          context.go('/jobs/create/${job.draftStep}');
        } else {
          context.go('/jobs/${job.id}');
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  job.title.isEmpty ? l.untitled : job.title,
                  style: TkText.h3,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              TkStatusBadge(status: status, label: _statusLabel(job.status, l)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _subtitle(job, l),
            style: TkText.caption.copyWith(
              color: job.isDraft ? TkColors.primary : scheme.onSurfaceVariant,
              fontWeight: job.isDraft ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(Job j, AppLocalizations l) {
    if (j.isDraft) return l.draftStep(j.draftStep);
    final price = tkMoney(j.budgetAmount, currency: j.currency);
    final counters = l.countersShort(j.offersCount, j.viewsCount);
    if (j.isAuction && j.auction?.endsAt != null) {
      final left = j.auction!.endsAt!.difference(DateTime.now());
      return '$price · ${l.auctionEndsIn(tkTimeLeft(left))} · $counters';
    }
    return '$price · $counters';
  }

  /// Статус задания → цвет из единой карты (ТЗ §1.10).
  TkStatus _status(String s) => switch (s) {
        JobStatus.draft => TkStatus.draft,
        JobStatus.published || JobStatus.collectingOffers => TkStatus.published,
        JobStatus.bidding => TkStatus.bidding,
        JobStatus.deciding || JobStatus.dealPending => TkStatus.deciding,
        JobStatus.confirmed => TkStatus.confirmed,
        JobStatus.inProgress => TkStatus.inProgress,
        JobStatus.workDone => TkStatus.acceptance,
        JobStatus.completed => TkStatus.completed,
        JobStatus.disputed => TkStatus.dispute,
        _ => TkStatus.cancelled,
      };

  String _statusLabel(String s, AppLocalizations l) => switch (s) {
        JobStatus.draft => l.statusDraft,
        JobStatus.published => l.statusPublished,
        JobStatus.collectingOffers => l.statusCollecting,
        JobStatus.bidding => l.statusBidding,
        JobStatus.dealPending => l.statusDeciding,
        JobStatus.deciding => l.statusDecidingClient,
        JobStatus.confirmed => l.statusConfirmed,
        JobStatus.inProgress => l.statusInProgress,
        JobStatus.workDone => l.statusAcceptance,
        JobStatus.completed => l.statusCompleted,
        JobStatus.disputed => l.statusDispute,
        JobStatus.cancelled => l.statusCancelled,
        JobStatus.declinedAll => l.statusDeclinedAll,
        JobStatus.expiredNoBids => l.statusNoBids,
        _ => l.statusExpired,
      };
}
