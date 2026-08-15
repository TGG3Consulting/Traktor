package service

import (
	"context"

	"github.com/google/uuid"

	"traktor/orders/internal/job"
)

// LeaveReview — оценка после завершённой сделки (ТЗ §2.13).
//
// Отзыв не публикуется сразу: он открывается вместе с отзывом второй стороны
// либо через неделю. Пока он скрыт, оценка второй стороны остаётся честной —
// её не на что «ответить симметрично».
func (s *Service) LeaveReview(ctx context.Context, userID, dealID string, in job.Review) (*job.Review, error) {
	d, err := s.st.DealByID(ctx, dealID)
	if err != nil {
		return nil, err
	}
	if err := job.CanReview(d, userID); err != nil {
		return nil, err
	}
	// На время разбора оценки заморожены (ТЗ §4.1): иначе отзыв превращается
	// в оружие в конфликте, а модератор разбирает уже испорченный рейтинг.
	if dispute, err := s.st.DisputeByDeal(ctx, d.ID); err == nil &&
		dispute.Status == job.DisputeOpen {
		return nil, job.ErrReviewFrozen
	}

	r := in
	r.DealID = d.ID
	r.JobID = d.JobID
	r.AuthorID = userID
	if userID == d.ClientID {
		r.AuthorRole, r.TargetID = job.RoleClient, d.OwnerID
	} else {
		r.AuthorRole, r.TargetID = job.RoleOwner, d.ClientID
	}
	if err := job.ValidateReview(&r); err != nil {
		return nil, err
	}

	now := s.now().UTC()
	r.ID = uuid.NewString()
	r.CreatedAt = now

	// Вторая сторона уже оценила — открываем обе оценки разом.
	existing, err := s.st.ReviewsByDeal(ctx, d.ID)
	if err != nil {
		return nil, err
	}
	var theirs *job.Review
	for i := range existing {
		if existing[i].AuthorID != userID {
			theirs = &existing[i]
		}
	}
	if theirs != nil {
		r.PublishedAt = &now
	}

	if err := s.st.CreateReview(ctx, &r); err != nil {
		return nil, err
	}

	if theirs != nil && !theirs.Published() {
		theirs.PublishedAt = &now
		if err := s.st.UpdateReview(ctx, theirs); err != nil {
			return nil, err
		}
		s.notifyPublished(ctx, *theirs)
		s.notifyPublished(ctx, r)
	} else {
		// Напоминание второй стороне: оценка нужна обеим, иначе обе висят
		// скрытыми целую неделю.
		s.notify.Send(ctx, r.TargetID, "Оставьте оценку",
			"Сделка завершена — оцените, как всё прошло",
			map[string]string{"route": "/deals/" + d.ID + "/review", "dealId": d.ID})
	}

	return &r, nil
}

// ReplyToReview — публичный ответ на отзыв о себе, один раз (ТЗ §2.13).
func (s *Service) ReplyToReview(ctx context.Context, userID, reviewID, text string) (*job.Review, error) {
	r, err := s.st.ReviewByID(ctx, reviewID)
	if err != nil {
		return nil, err
	}
	if err := job.CanReply(r, userID); err != nil {
		return nil, err
	}
	body, err := job.ValidateReply(text)
	if err != nil {
		return nil, err
	}

	now := s.now().UTC()
	r.ReplyText = body
	r.ReplyAt = &now
	if err := s.st.UpdateReview(ctx, r); err != nil {
		return nil, err
	}
	return r, nil
}

// ReviewsAbout — публичные отзывы о человеке для карточки профиля.
func (s *Service) ReviewsAbout(ctx context.Context, userID string, limit, offset int) ([]job.Review, job.RatingSummary, error) {
	items, err := s.st.ReviewsAbout(ctx, userID, clampLimit(limit), max0(offset))
	if err != nil {
		return nil, job.RatingSummary{}, err
	}
	summary, err := s.st.RatingOf(ctx, userID, s.now().UTC().Add(-job.RatingWindow))
	if err != nil {
		return nil, job.RatingSummary{}, err
	}
	return items, summary, nil
}

// MyReviewForDeal — моя оценка по сделке, если она уже есть: экран должен
// показывать поставленные звёзды, а не пустую форму по второму заходу.
func (s *Service) MyReviewForDeal(ctx context.Context, userID, dealID string) (*job.Review, error) {
	items, err := s.st.ReviewsByDeal(ctx, dealID)
	if err != nil {
		return nil, err
	}
	for i := range items {
		if items[i].AuthorID == userID {
			return &items[i], nil
		}
	}
	return nil, job.ErrReviewNotFound
}

// Ratings — сводки рейтингов пачкой: карточки откликов и ставок показывают
// «★4,8 · 36 оценок» рядом с каждым именем.
func (s *Service) Ratings(ctx context.Context, ids []string) map[string]job.RatingSummary {
	out := make(map[string]job.RatingSummary, len(ids))
	since := s.now().UTC().Add(-job.RatingWindow)
	for _, id := range ids {
		if id == "" {
			continue
		}
		if _, done := out[id]; done {
			continue
		}
		summary, err := s.st.RatingOf(ctx, id, since)
		if err != nil {
			continue
		}
		out[id] = summary
	}
	return out
}

// publishDueReviews открывает одинокие оценки, ждавшие неделю. Вызывается
// фоновым обработчиком времени вместе с остальными сроками.
func (s *Service) publishDueReviews(ctx context.Context) error {
	now := s.now().UTC()
	due, err := s.st.DueReviews(ctx, now.Add(-job.HoldPeriod))
	if err != nil {
		return err
	}
	for i := range due {
		r := due[i]
		if !job.ShouldPublish(&r, nil, now) {
			continue
		}
		r.PublishedAt = &now
		if err := s.st.UpdateReview(ctx, &r); err != nil {
			return err
		}
		s.notifyPublished(ctx, r)
	}
	return nil
}

func (s *Service) notifyPublished(ctx context.Context, r job.Review) {
	s.notify.Send(ctx, r.TargetID, "Новый отзыв о вас",
		starsLine(r.Stars),
		map[string]string{"route": "/reviews/" + r.ID, "reviewId": r.ID})
}

func starsLine(stars int) string {
	const filled = "★★★★★"
	if stars < 1 || stars > 5 {
		return "Оценка опубликована"
	}
	return string([]rune(filled)[:stars]) + " — отзыв опубликован"
}
