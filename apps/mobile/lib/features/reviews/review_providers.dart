import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';

/// Что показать на экране оценки сделки (ТЗ §2.13).
final reviewFormProvider = FutureProvider.family<ReviewForm, String>((ref, dealId) async {
  ref.watch(accessTokenProvider);
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).reviewForm(t, dealId));
});

/// Отзывы о человеке и его рейтинг — карточка профиля.
final userReviewsProvider = FutureProvider.family<ReviewsPage, String>((ref, userId) async {
  ref.watch(accessTokenProvider);
  return ref
      .read(sessionRefresherProvider)
      .run((t) => ref.read(jobsApiProvider).userReviews(t, userId));
});

class ReviewActions {
  ReviewActions(this._ref);

  final Ref _ref;

  String _key(String action, String id) =>
      '$action-$id-${DateTime.now().microsecondsSinceEpoch}';

  Future<ReviewResult> leave(
    String dealId, {
    required int stars,
    List<String> tags = const [],
    String text = '',
    String issue = '',
  }) async {
    final result = await _ref.read(sessionRefresherProvider).run(
          (t) => _ref.read(jobsApiProvider).leaveReview(
                t,
                dealId,
                stars: stars,
                tags: tags,
                text: text,
                issue: issue,
                idempotencyKey: _key('review', dealId),
              ),
        );
    _ref.invalidate(reviewFormProvider(dealId));
    return result;
  }

  Future<Review> reply(String reviewId, String text, {String? aboutUserId}) async {
    final review = await _ref.read(sessionRefresherProvider).run(
          (t) => _ref.read(jobsApiProvider).replyToReview(t, reviewId, text,
              idempotencyKey: _key('reply', reviewId)),
        );
    if (aboutUserId != null) _ref.invalidate(userReviewsProvider(aboutUserId));
    return review;
  }
}

final reviewActionsProvider = Provider<ReviewActions>(ReviewActions.new);
