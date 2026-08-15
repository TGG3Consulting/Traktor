package service

import (
	"context"

	"github.com/google/uuid"

	"traktor/orders/internal/job"
)

// Споры (ТЗ §4.1, п.4).
//
// Конфликт без арбитра — потерянный клиент с обеих сторон. Разбор ведётся
// внутри площадки: модератор видит сделку целиком и выносит решение с
// обоснованием, которое получают оба.

// OpenDispute — открыть спор по сделке.
func (s *Service) OpenDispute(ctx context.Context, userID, dealID, reason string, photos []string) (*job.Dispute, error) {
	d, err := s.st.DealByID(ctx, dealID)
	if err != nil {
		return nil, err
	}
	if err := job.CanOpenDispute(d, userID); err != nil {
		return nil, err
	}
	text, err := job.ValidateReason(reason)
	if err != nil {
		return nil, err
	}

	now := s.now().UTC()
	dispute := &job.Dispute{
		ID:        uuid.NewString(),
		DealID:    d.ID,
		JobID:     d.JobID,
		OpenedBy:  userID,
		ClientID:  d.ClientID,
		OwnerID:   d.OwnerID,
		Reason:    text,
		Photos:    photos,
		Status:    job.DisputeOpen,
		CreatedAt: now,
	}
	if dispute.Photos == nil {
		dispute.Photos = []string{}
	}
	if err := s.st.CreateDispute(ctx, dispute); err != nil {
		return nil, err
	}

	// Сделка переходит в спор: она не закрывается автоматически и не уходит
	// в автоприёмку, пока идёт разбор.
	if d.Status != job.DealDisputed && d.Status != job.DealCompleted {
		d.Status = job.DealDisputed
		d.UpdatedAt = now
		d.Timeline = append(d.Timeline, job.TimelineEvent{
			Status: job.DealDisputed, At: now, ByID: userID, Note: text,
		})
		if err := s.st.UpdateDeal(ctx, d); err != nil {
			return nil, err
		}
		if j, err := s.st.ByID(ctx, d.JobID); err == nil {
			j.Status = job.JobStatusForDeal(job.DealDisputed)
			j.UpdatedAt = now
			_ = s.st.Update(ctx, j)
		}
	}

	// Вторая сторона узнаёт о споре сразу: молчание здесь читается как
	// «за спиной пожаловались».
	other := d.OwnerID
	if userID == d.OwnerID {
		other = d.ClientID
	}
	s.notify.Send(ctx, other, "Открыт спор по сделке", preview(text),
		map[string]string{"kind": "deal", "route": "/deals/" + d.ID, "dealId": d.ID})

	return dispute, nil
}

// DisputeOfDeal — спор по сделке для её участников.
func (s *Service) DisputeOfDeal(ctx context.Context, userID, dealID string) (*job.Dispute, error) {
	d, err := s.st.DisputeByDeal(ctx, dealID)
	if err != nil {
		return nil, err
	}
	if d.ClientID != userID && d.OwnerID != userID {
		return nil, job.ErrDisputeForbidden
	}
	return d, nil
}

// DisputeQueue — очередь модерации.
func (s *Service) DisputeQueue(ctx context.Context, limit int) ([]job.Dispute, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	return s.st.OpenDisputes(ctx, limit)
}

// ResolveDispute — решение модератора. Исход и обоснование обязательны:
// решение без объяснения обе стороны считают несправедливым.
func (s *Service) ResolveDispute(ctx context.Context, moderatorID, disputeID string,
	outcome job.DisputeOutcome, resolution string) (*job.Dispute, error) {
	d, err := s.st.DisputeByID(ctx, disputeID)
	if err != nil {
		return nil, err
	}
	if d.Status != job.DisputeOpen {
		return nil, job.ErrDisputeClosed
	}
	if !job.ValidOutcome(outcome) {
		return nil, job.ErrDisputeOutcome
	}
	text, err := job.ValidateResolution(resolution)
	if err != nil {
		return nil, err
	}

	now := s.now().UTC()
	d.Status = job.DisputeResolved
	d.Outcome = outcome
	d.Resolution = text
	d.ResolvedBy = moderatorID
	d.ResolvedAt = &now
	if err := s.st.UpdateDispute(ctx, d); err != nil {
		return nil, err
	}

	// Сделка выходит из спора: в пользу заказчика — отменяется, иначе
	// считается завершённой. Компромисс закрываем как завершённую работу:
	// стороны договорились, деньги за неё уже уплачены.
	if deal, err := s.st.DealByID(ctx, d.DealID); err == nil && deal.Status == job.DealDisputed {
		if outcome == job.OutcomeClient {
			deal.Status = job.DealCancelled
			deal.CancelReason = "решение по спору: " + text
		} else {
			deal.Status = job.DealCompleted
		}
		deal.UpdatedAt = now
		deal.ClosedAt = &now
		deal.Timeline = append(deal.Timeline, job.TimelineEvent{
			Status: deal.Status, At: now, ByID: moderatorID,
			Note: "спор разобран: " + job.OutcomeRU(outcome),
		})
		if err := s.st.UpdateDeal(ctx, deal); err != nil {
			return nil, err
		}
		if j, err := s.st.ByID(ctx, deal.JobID); err == nil {
			j.Status = job.JobStatusForDeal(deal.Status)
			j.UpdatedAt = now
			_ = s.st.Update(ctx, j)
		}
	}

	// Решение уходит обеим сторонам с обоснованием.
	for _, user := range []string{d.ClientID, d.OwnerID} {
		s.notify.Send(ctx, user, "Спор разобран: "+job.OutcomeRU(outcome), preview(text),
			map[string]string{"kind": "deal", "route": "/deals/" + d.DealID, "dealId": d.DealID})
	}
	return d, nil
}
