package service

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"

	"traktor/orders/internal/job"
	"traktor/orders/internal/notify"
)

// BidInput — ставка исполнителя.
type BidInput struct {
	Price   int64
	Comment string
	UnitID  *string
}

// PlaceBid — поставить (или снизить) ставку в обратном аукционе (ТЗ §2.9).
//
// Ставка — обязательство выполнить работу за эту цену, поэтому здесь три
// защиты: цена должна быть ниже текущей лучшей, не ниже трети стартовой
// (антидемпинг) и торг должен идти. Ставка в последние минуты продлевает
// аукцион — иначе его можно было бы выиграть последней секундой.
func (s *Service) PlaceBid(ctx context.Context, ownerID, jobID string, in BidInput) (*job.Bid, error) {
	j, err := s.st.ByID(ctx, jobID)
	if err != nil {
		return nil, err
	}
	if j.ClientID == ownerID {
		return nil, job.ErrOwnJob
	}
	now := s.now().UTC()
	if err := job.CanBid(j, now); err != nil {
		return nil, err
	}

	var best int64
	if b, err := s.st.BestBid(ctx, jobID); err == nil {
		best = b.Price
		if b.OwnerID == ownerID {
			// Свою же ставку перебивать не нужно: сравниваем со второй ценой,
			// иначе исполнитель не сможет просто поправить свою цену вниз.
			best = 0
			all, _ := s.st.BidsByJob(ctx, jobID)
			for _, other := range all {
				if other.Status == job.BidActive && other.OwnerID != ownerID {
					if best == 0 || other.Price < best {
						best = other.Price
					}
				}
			}
		}
	}
	var start int64
	if j.BudgetAmount != nil {
		start = *j.BudgetAmount
	}
	if err := job.ValidateBid(in.Price, best, start); err != nil {
		return nil, err
	}

	// Прежняя ставка этого исполнителя уходит в историю: в ленте торга у
	// каждого одна действующая цена.
	if prev, err := s.st.MyBidForJob(ctx, jobID, ownerID); err == nil && prev.Status == job.BidActive {
		prev.Status = job.BidWithdrawn
		prev.UpdatedAt = now
		if err := s.st.UpdateBid(ctx, prev); err != nil {
			return nil, err
		}
	}

	bid := &job.Bid{
		ID:        uuid.NewString(),
		JobID:     jobID,
		OwnerID:   ownerID,
		UnitID:    in.UnitID,
		Price:     in.Price,
		Currency:  j.Currency,
		Comment:   strings.TrimSpace(in.Comment),
		Status:    job.BidActive,
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := s.st.CreateBid(ctx, bid); err != nil {
		return nil, err
	}

	// Тот, кого перебили, узнаёт об этом сразу — иначе он проиграет молча.
	if best > 0 {
		s.notifyOutbid(ctx, j, bid)
	}

	// Антиснайпинг: продлеваем торг и говорим об этом всем участникам.
	if job.ShouldExtend(j, now) {
		ends := j.Auction.EndsAt.Add(job.ExtendBy)
		j.Auction.EndsAt = &ends
		j.UpdatedAt = now
		if err := s.st.Update(ctx, j); err != nil {
			return nil, err
		}
	}

	s.notify.Send(ctx, j.ClientID, "Новая ставка",
		j.Title+" · "+notify.MoneyRU(bid.Price, bid.Currency),
		map[string]string{"route": "/jobs/" + j.ID, "jobId": j.ID})

	return bid, nil
}

// WithdrawBid — снять ставку. За два часа до финиша уже нельзя (ТЗ §2.9):
// иначе можно было бы «придержать» цену и уйти в последний момент.
func (s *Service) WithdrawBid(ctx context.Context, ownerID, bidID string) (*job.Bid, error) {
	b, err := s.st.BidByID(ctx, bidID)
	if err != nil {
		return nil, err
	}
	if b.OwnerID != ownerID {
		return nil, job.ErrForbidden
	}
	if b.Status != job.BidActive {
		return nil, job.ErrBidNotActive
	}
	j, err := s.st.ByID(ctx, b.JobID)
	if err != nil {
		return nil, err
	}
	now := s.now().UTC()
	if err := job.CanWithdrawBid(j, now); err != nil {
		return nil, err
	}

	b.Status = job.BidWithdrawn
	b.UpdatedAt = now
	if err := s.st.UpdateBid(ctx, b); err != nil {
		return nil, err
	}
	return b, nil
}

// JobBids — лента торга. Имена участников не раскрываются до финиша
// (ТЗ §2.9): цены видны всем, кто именно поставил — нет.
func (s *Service) JobBids(ctx context.Context, jobID string) ([]job.Bid, error) {
	bids, err := s.st.BidsByJob(ctx, jobID)
	if err != nil {
		return nil, err
	}
	rank := 0
	for i := range bids {
		if bids[i].Status == job.BidActive {
			rank++
			bids[i].Rank = rank
		}
	}
	return bids, nil
}

// MyBids — ставки исполнителя.
func (s *Service) MyBids(ctx context.Context, ownerID string, limit, offset int) ([]job.Bid, error) {
	return s.st.BidsByOwner(ctx, ownerID, clampLimit(limit), max0(offset))
}

// MyBidForJob — своя действующая ставка по заданию.
func (s *Service) MyBidForJob(ctx context.Context, ownerID, jobID string) (*job.Bid, error) {
	return s.st.MyBidForJob(ctx, jobID, ownerID)
}

// FinishAuction подводит итог торга: считает скоринг, помечает победителя и
// открывает заказчику окно решения (ТЗ §2.9).
//
// Вызывается фоновым обработчиком по времени финиша; здесь же — вручную из
// тестов и админки. Повторный вызов безопасен.
func (s *Service) FinishAuction(ctx context.Context, jobID string) (*job.Job, error) {
	j, err := s.st.ByID(ctx, jobID)
	if err != nil {
		return nil, err
	}
	if j.Mode != job.ModeAuction {
		return nil, job.ErrNotAuction
	}
	if j.Status != job.StatusBidding {
		// Уже подвели итог — не считаем заново.
		return j, nil
	}

	bids, err := s.st.BidsByJob(ctx, jobID)
	if err != nil {
		return nil, err
	}
	items := make([]job.BidScore, 0, len(bids))
	for _, b := range bids {
		if b.Status != job.BidActive {
			continue
		}
		// Рейтинг и расстояние появятся вместе с профилями и техникой; пока
		// скоринг опирается на цену — это честнее, чем выдумывать числа.
		items = append(items, job.BidScore{Bid: b, Rating: 0, DistanceM: -1})
	}

	now := s.now().UTC()
	if len(items) == 0 {
		j.Status = job.StatusExpiredNoBids
		j.UpdatedAt = now
		if err := s.st.Update(ctx, j); err != nil {
			return nil, err
		}
		s.notify.Send(ctx, j.ClientID, "Аукцион завершён без ставок",
			j.Title+" — можно перезапустить с другой ценой или сроком",
			map[string]string{"route": "/jobs/" + j.ID, "jobId": j.ID})
		return j, nil
	}

	scored := job.Score(items, reserveOf(j))
	if len(scored) == 0 {
		// Ставки были, но все ниже резерва: для заказчика это тот же тупик.
		j.Status = job.StatusExpiredNoBids
		j.UpdatedAt = now
		if err := s.st.Update(ctx, j); err != nil {
			return nil, err
		}
		s.notify.Send(ctx, j.ClientID, "Подходящих ставок нет",
			"Все ставки оказались ниже вашей минимальной цены",
			map[string]string{"route": "/jobs/" + j.ID, "jobId": j.ID})
		return j, nil
	}

	// Сохраняем посчитанные оценки: по ним заказчик видит порядок и рекомендацию.
	for _, it := range scored {
		b := it.Bid
		b.UpdatedAt = now
		if err := s.st.UpdateBid(ctx, &b); err != nil {
			return nil, err
		}
	}

	winner := scored[0].Bid
	deadline := now.Add(time.Duration(decisionWindow(j)) * time.Hour)
	j.Status = job.StatusDeciding
	j.WinnerBidID = &winner.ID
	j.DecisionDeadline = &deadline
	j.UpdatedAt = now
	if err := s.st.Update(ctx, j); err != nil {
		return nil, err
	}

	s.notify.Send(ctx, j.ClientID, "Аукцион завершён",
		"Лучшая ставка "+notify.MoneyRU(winner.Price, winner.Currency)+" — выберите исполнителя",
		map[string]string{"route": "/jobs/" + j.ID + "/bids", "jobId": j.ID})
	for _, it := range scored {
		title := "Аукцион завершён"
		body := "Заказчик выбирает исполнителя"
		if it.Bid.ID == winner.ID {
			title = "Ваша ставка лучшая"
			body = "Ждём решения заказчика"
		}
		s.notify.Send(ctx, it.Bid.OwnerID, title, body,
			map[string]string{"route": "/jobs/" + j.ID, "jobId": j.ID})
	}
	return j, nil
}

func reserveOf(j *job.Job) *int64 {
	if j.Auction == nil {
		return nil
	}
	return j.Auction.ReserveAmount
}

func decisionWindow(j *job.Job) int {
	if j.Auction == nil || j.Auction.DecisionWindowH <= 0 {
		return 12
	}
	return j.Auction.DecisionWindowH
}

// notifyOutbid сообщает тому, чья ставка перестала быть лучшей.
func (s *Service) notifyOutbid(ctx context.Context, j *job.Job, newBid *job.Bid) {
	bids, err := s.st.BidsByJob(ctx, j.ID)
	if err != nil {
		return
	}
	for _, b := range bids {
		if b.Status != job.BidActive || b.OwnerID == newBid.OwnerID || b.Price <= newBid.Price {
			continue
		}
		s.notify.Send(ctx, b.OwnerID, "Вашу ставку перебили",
			j.Title+" · сейчас "+notify.MoneyRU(newBid.Price, newBid.Currency),
			map[string]string{"route": "/jobs/" + j.ID, "jobId": j.ID})
	}
}
