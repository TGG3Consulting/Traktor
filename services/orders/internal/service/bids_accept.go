package service

import (
	"context"

	"traktor/orders/internal/job"
	"traktor/orders/internal/notify"
)

// AcceptBid — заказчик выбирает победителя аукциона в окне решения (ТЗ §2.9).
//
// Он не обязан брать лучшего по скорингу: рекомендация — подсказка, а решение
// остаётся за человеком. Задание уходит в «ожидает подтверждения», остальные
// ставки закрываются.
func (s *Service) AcceptBid(ctx context.Context, clientID, bidID string) (*job.Bid, error) {
	b, err := s.st.BidByID(ctx, bidID)
	if err != nil {
		return nil, err
	}
	j, err := s.st.ByID(ctx, b.JobID)
	if err != nil {
		return nil, err
	}
	if j.ClientID != clientID {
		return nil, job.ErrForbidden
	}
	if j.Status != job.StatusDeciding {
		return nil, job.ErrBadTransition
	}
	if b.Status != job.BidActive {
		return nil, job.ErrBidNotActive
	}

	now := s.now().UTC()
	b.Status = job.BidWon
	b.UpdatedAt = now
	if err := s.st.UpdateBid(ctx, b); err != nil {
		return nil, err
	}

	all, err := s.st.BidsByJob(ctx, j.ID)
	if err != nil {
		return nil, err
	}
	for i := range all {
		other := all[i]
		if other.ID == b.ID || other.Status != job.BidActive {
			continue
		}
		other.Status = job.BidLost
		other.UpdatedAt = now
		if err := s.st.UpdateBid(ctx, &other); err != nil {
			return nil, err
		}
		s.notify.Send(ctx, other.OwnerID, "Аукцион завершён",
			j.Title+" — заказчик выбрал другого исполнителя",
			map[string]string{"route": "/jobs/" + j.ID, "jobId": j.ID})
	}

	// Дальше путь тот же, что у фикс-цены: подтверждение сделки.
	j.Status = job.StatusDealPending
	j.WinnerBidID = &b.ID
	j.UpdatedAt = now
	if err := s.st.Update(ctx, j); err != nil {
		return nil, err
	}

	s.notify.Send(ctx, b.OwnerID, "Вас выбрали",
		j.Title+" · "+notify.MoneyRU(b.Price, b.Currency),
		map[string]string{"route": "/jobs/" + j.ID, "jobId": j.ID})

	return b, nil
}

// DeclineAllBids — заказчик отказывается от всех ставок (ТЗ §2.9), без штрафа.
// Задание закрывается, участники получают вежливое уведомление.
func (s *Service) DeclineAllBids(ctx context.Context, clientID, jobID string) (*job.Job, error) {
	j, err := s.own(ctx, clientID, jobID)
	if err != nil {
		return nil, err
	}
	if j.Status != job.StatusDeciding {
		return nil, job.ErrBadTransition
	}

	now := s.now().UTC()
	bids, err := s.st.BidsByJob(ctx, jobID)
	if err != nil {
		return nil, err
	}
	for i := range bids {
		b := bids[i]
		if b.Status != job.BidActive {
			continue
		}
		b.Status = job.BidLost
		b.UpdatedAt = now
		if err := s.st.UpdateBid(ctx, &b); err != nil {
			return nil, err
		}
		s.notify.Send(ctx, b.OwnerID, "Заказчик отказался от всех ставок",
			j.Title+" — задание закрыто",
			map[string]string{"route": "/jobs/" + j.ID, "jobId": j.ID})
	}

	j.Status = job.StatusDeclinedAll
	j.UpdatedAt = now
	if err := s.st.Update(ctx, j); err != nil {
		return nil, err
	}
	return j, nil
}

// ExpireDecision — заказчик промолчал всё окно решения. Задание закрывается
// само: исполнители не должны ждать ответа бесконечно (ТЗ §2.9).
func (s *Service) ExpireDecision(ctx context.Context, jobID string) (*job.Job, error) {
	j, err := s.st.ByID(ctx, jobID)
	if err != nil {
		return nil, err
	}
	if j.Status != job.StatusDeciding {
		return j, nil
	}
	if j.DecisionDeadline != nil && s.now().UTC().Before(*j.DecisionDeadline) {
		// Время ещё есть — ничего не делаем.
		return j, nil
	}

	now := s.now().UTC()
	bids, _ := s.st.BidsByJob(ctx, jobID)
	for i := range bids {
		b := bids[i]
		if b.Status != job.BidActive {
			continue
		}
		b.Status = job.BidExpired
		b.UpdatedAt = now
		_ = s.st.UpdateBid(ctx, &b)
		s.notify.Send(ctx, b.OwnerID, "Заказчик не принял решение",
			j.Title+" — задание закрыто, посмотрите похожие",
			map[string]string{"route": "/jobs", "jobId": j.ID})
	}

	j.Status = job.StatusExpired
	j.UpdatedAt = now
	if err := s.st.Update(ctx, j); err != nil {
		return nil, err
	}
	return j, nil
}
