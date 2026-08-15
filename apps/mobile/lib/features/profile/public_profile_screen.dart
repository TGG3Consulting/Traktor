import 'package:api_client/api_client.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:traktor_mobile/l10n/app_localizations.dart';

import '../../core/app_settings.dart';
import '../../core/share_link.dart';
import '../auth/auth_controller.dart';
import '../complaints/complaint_sheet.dart';
import '../jobs/jobs_providers.dart';
import '../reviews/review_providers.dart';

/// Карточка человека (ТЗ §2.3): имя, рейтинг, техника и отзывы о нём.
///
/// Открывается без входа — ссылкой на исполнителя делятся в мессенджере, и она
/// должна показывать что-то осмысленное любому, кто по ней перешёл.
final publicProfileProvider =
    FutureProvider.family<PublicProfile, String>((ref, userId) async {
  final token = ref.watch(accessTokenProvider);
  return ref.read(jobsApiProvider).publicProfile(userId, token: token);
});

final publicEquipmentProvider =
    FutureProvider.family<List<Equipment>, String>((ref, userId) async {
  final token = ref.watch(accessTokenProvider);
  return ref.read(jobsApiProvider).publicEquipment(userId, token: token);
});

class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final profile = ref.watch(publicProfileProvider(userId));
    final reviews = ref.watch(userReviewsProvider(userId));
    final machines = ref.watch(publicEquipmentProvider(userId));
    final lang = (ref.watch(appSettingsProvider).locale ?? const Locale('ru')).languageCode;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.profileTitle),
        leading: IconButton(
          tooltip: l.back,
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          icon: TkIcon(TkIcons.arrowLeft, size: 20, color: scheme.onSurface),
        ),
        actions: [
          TkShare.button(context, TkShare.user(userId)),
          // Пожаловаться на человека (ТЗ §4.1, п.6). На себя — незачем,
          // гостю сначала нужно войти.
          if (ref.watch(sessionProvider)?.user.id case final me?
              when me.isNotEmpty && me != userId)
            IconButton(
              tooltip: l.complain,
              onPressed: () async {
                final sent = await showComplaintSheet(
                  context,
                  targetKind: 'user',
                  targetId: userId,
                  targetTitle: profile.valueOrNull?.name ?? '',
                );
                if (sent == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.complaintSent)),
                  );
                }
              },
              icon: TkIcon(TkIcons.flag, size: 20, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
      body: profile.when(
        loading: () => const TkSkeletonList(count: 2),
        error: (e, _) => TkErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(publicProfileProvider(userId)),
        ),
        data: (p) => ListView(
          padding: TkSpace.screenMobile,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.surfaceContainerHighest,
                  child: Text(
                    p.displayName.characters.first.toUpperCase(),
                    style: TkText.h2,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(p.displayName, style: TkText.h2)),
                          if (p.verified) ...[
                            const SizedBox(width: 6),
                            const TkIcon(TkIcons.checkCircle,
                                size: 16, color: TkColors.success),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      TkRatingLine(
                        rating: reviews.valueOrNull?.rating ?? 0,
                        count: reviews.valueOrNull?.count ?? 0,
                      ),
                      if (p.city.isNotEmpty || p.createdAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (p.city.isNotEmpty) p.city,
                            if (p.createdAt != null)
                              l.onPlatformSince(tkShortDate(p.createdAt)),
                          ].join(' · '),
                          style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Техника: заказчик смотрит на неё первым делом — по ней он решает,
            // справится ли человек с работой.
            machines.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (list) {
                if (list.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.equipmentSection, style: TkText.h3),
                    const SizedBox(height: 8),
                    for (final e in list) ...[
                      TkCard(
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: TkRadius.cardR,
                              ),
                              child: e.photos.isEmpty
                                  ? TkIcon(TkIcons.wrench,
                                      size: 22, color: scheme.onSurfaceVariant)
                                  : ClipRRect(
                                      borderRadius: TkRadius.cardR,
                                      child: Image.network(e.photos.first,
                                          width: 56, height: 56, fit: BoxFit.cover),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.title, style: TkText.body.copyWith(
                                      fontWeight: FontWeight.w600)),
                                  Text(
                                    [
                                      if (e.categoryTitle(lang).isNotEmpty)
                                        e.categoryTitle(lang),
                                      if (e.year != null) l.yearShort(e.year!),
                                    ].join(' · '),
                                    style: TkText.caption
                                        .copyWith(color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            if (e.isVerified)
                              const TkIcon(TkIcons.checkCircle,
                                  size: 16, color: TkColors.success),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),

            Text(l.reviewsSection, style: TkText.h3),
            const SizedBox(height: 8),
            reviews.when(
              loading: () => const TkSkeletonList(count: 2),
              error: (e, _) => TkErrorState(
                message: '$e',
                onRetry: () => ref.invalidate(userReviewsProvider(userId)),
              ),
              data: (page) {
                if (page.items.isEmpty) {
                  return Text(
                    l.noReviewsYet,
                    style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
                  );
                }
                return Column(
                  children: [
                    for (final r in page.items) ...[
                      _ReviewCard(review: r),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TkStars(value: review.stars, size: 16),
              const Spacer(),
              Text(
                tkShortDate(review.publishedAt ?? review.createdAt),
                style: TkText.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            review.authorName.isEmpty ? l.someUser : review.authorName,
            style: TkText.caption.copyWith(fontWeight: FontWeight.w600),
          ),
          if (review.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final t in review.tags) TkChip(label: t, selected: true)],
            ),
          ],
          if (review.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.text, style: TkText.body),
          ],
          // Ответ на отзыв — часть той же истории: читать его отдельно
          // бессмысленно, поэтому он идёт следом с отступом.
          if (review.replyText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: TkRadius.cardR,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.replyLabel,
                      style: TkText.caption.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(review.replyText, style: TkText.caption),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
