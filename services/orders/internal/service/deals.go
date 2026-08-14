package service

import (
	"context"
	"strings"

	"github.com/google/uuid"

	"traktor/orders/internal/job"
	"traktor/orders/internal/notify"
)

// ConfirmDeal — заказчик подтверждает выбор, и появляется сделка (ТЗ §2.11).
//
// Отдельный шаг после выбора исполнителя нужен потому, что между «выбрал» и
// «работаем» человек ещё может передумать, списаться, уточнить детали. Сделка —
// это момент, с которого цена зафиксирована и стороны видят телефоны друг друга.
func (s *Service) ConfirmDeal(ctx context.Context, clientID, jobID string) (*job.Deal, error) {
	j, err := s.own(ctx, clientID, jobID)
	if err != nil {
		return nil, err
	}
	if existing, err := s.st.DealByJob(ctx, jobID); err == nil {
		// Повторное подтверждение — не ошибка: клиент мог потерять ответ.
		return existing, nil
	}
	if j.Status != job.StatusDealPending {
		return nil, job.ErrBadTransition
	}

	offers, err := s.st.OffersByJob(ctx, jobID)
	if err != nil {
		return nil, err
	}
	var accepted *job.Offer
	for i := range offers {
		if offers[i].Status == job.OfferAccepted {
			accepted = &offers[i]
			break
		}
	}
	if accepted == nil {
		return nil, job.ErrDealStep
	}

	now := s.now().UTC()
	deal := &job.Deal{
		ID:       uuid.NewString(),
		JobID:    jobID,
		OfferID:  &accepted.ID,
		ClientID: j.ClientID,
		OwnerID:  accepted.OwnerID,
		Price:    accepted.Price,
		Currency: accepted.Currency,
		Status:   job.DealConfirmed,
		Timeline: []job.TimelineEvent{{
			Status: job.DealConfirmed,
			At:     now,
			ByID:   clientID,
		}},
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := s.st.CreateDeal(ctx, deal); err != nil {
		return nil, err
	}

	j.Status = job.StatusConfirmed
	j.UpdatedAt = now
	if err := s.st.Update(ctx, j); err != nil {
		return nil, err
	}

	s.notify.Send(ctx, deal.OwnerID, "Сделка подтверждена",
		j.Title+" · "+notify.MoneyRU(deal.Price, deal.Currency),
		map[string]string{"route": "/deals/" + deal.ID, "dealId": deal.ID})

	return deal, nil
}

// AdvanceDeal двигает сделку на следующий шаг: выехал, начал, завершил,
// принято. Кто вправе сделать шаг — решает модель (ТЗ §2.11), а не клиент.
func (s *Service) AdvanceDeal(ctx context.Context, userID, dealID string,
	to job.DealStatus, note string) (*job.Deal, error) {
	d, err := s.st.DealByID(ctx, dealID)
	if err != nil {
		return nil, err
	}
	if err := job.CanAdvance(d, to, userID); err != nil {
		return nil, err
	}

	now := s.now().UTC()
	d.Status = to
	d.Timeline = append(d.Timeline, job.TimelineEvent{
		Status: to, At: now, ByID: userID, Note: strings.TrimSpace(note),
	})
	d.UpdatedAt = now

	switch to {
	case job.DealWorkDone:
		// С этого момента у заказчика 48 часов на приёмку; молчание означает
		// согласие — иначе исполнитель ждал бы оплаты бесконечно.
		deadline := now.Add(job.AcceptanceWindow)
		d.AcceptanceDeadline = &deadline
	case job.DealCompleted, job.DealCancelled:
		d.ClosedAt = &now
	}

	if err := s.st.UpdateDeal(ctx, d); err != nil {
		return nil, err
	}

	// Статус задания идёт следом: человек видит его в списке и в ленте.
	if j, err := s.st.ByID(ctx, d.JobID); err == nil {
		j.Status = job.JobStatusForDeal(to)
		j.UpdatedAt = now
		_ = s.st.Update(ctx, j)
	}

	s.notifyDealStep(ctx, d, userID, to)
	return d, nil
}

// CancelDeal — отмена после подтверждения, с причиной (ТЗ §2.11).
func (s *Service) CancelDeal(ctx context.Context, userID, dealID, reason string) (*job.Deal, error) {
	d, err := s.st.DealByID(ctx, dealID)
	if err != nil {
		return nil, err
	}
	if err := job.CanAdvance(d, job.DealCancelled, userID); err != nil {
		return nil, err
	}
	if strings.TrimSpace(reason) == "" {
		return nil, &job.ValidationError{
			Fields: map[string]string{"reason": "укажите причину — её увидит вторая сторона"},
		}
	}

	now := s.now().UTC()
	d.Status = job.DealCancelled
	d.CancelReason = strings.TrimSpace(reason)
	d.CancelledBy = &userID
	d.ClosedAt = &now
	d.UpdatedAt = now
	d.Timeline = append(d.Timeline, job.TimelineEvent{
		Status: job.DealCancelled, At: now, ByID: userID, Note: d.CancelReason,
	})
	if err := s.st.UpdateDeal(ctx, d); err != nil {
		return nil, err
	}

	if j, err := s.st.ByID(ctx, d.JobID); err == nil {
		j.Status = job.StatusCancelled
		j.UpdatedAt = now
		_ = s.st.Update(ctx, j)
	}

	s.notify.Send(ctx, s.otherParty(d, userID), "Сделка отменена", d.CancelReason,
		map[string]string{"route": "/deals/" + d.ID, "dealId": d.ID})
	return d, nil
}

// Deal отдаёт сделку участнику. Посторонним — отказ: в сделке есть телефоны.
func (s *Service) Deal(ctx context.Context, userID, dealID string) (*job.Deal, error) {
	d, err := s.st.DealByID(ctx, dealID)
	if err != nil {
		return nil, err
	}
	if d.ClientID != userID && d.OwnerID != userID {
		return nil, job.ErrDealNotParty
	}
	return d, nil
}

// DealByJob — сделка по заданию (экран задания открывает её одной ссылкой).
func (s *Service) DealByJob(ctx context.Context, userID, jobID string) (*job.Deal, error) {
	d, err := s.st.DealByJob(ctx, jobID)
	if err != nil {
		return nil, err
	}
	if d.ClientID != userID && d.OwnerID != userID {
		return nil, job.ErrDealNotParty
	}
	return d, nil
}

// MyDeals — сделки пользователя в обеих ролях.
func (s *Service) MyDeals(ctx context.Context, userID string, limit, offset int) ([]job.Deal, error) {
	return s.st.DealsByUser(ctx, userID, clampLimit(limit), max0(offset))
}

func (s *Service) otherParty(d *job.Deal, userID string) string {
	if d.ClientID == userID {
		return d.OwnerID
	}
	return d.ClientID
}

// notifyDealStep сообщает второй стороне о шаге. Тексты пишем от лица события,
// а не статуса: «Исполнитель выехал» понятнее, чем «статус on_the_way».
func (s *Service) notifyDealStep(ctx context.Context, d *job.Deal, byID string, to job.DealStatus) {
	target := s.otherParty(d, byID)
	title, body := "", ""

	switch to {
	case job.DealOnTheWay:
		title, body = "Исполнитель выехал", "Скоро будет на месте"
	case job.DealInProgress:
		title, body = "Работа началась", "Исполнитель приступил к работе"
	case job.DealWorkDone:
		title = "Работа завершена"
		body = "Проверьте результат — на приёмку 48 часов, потом она пройдёт автоматически"
	case job.DealCompleted:
		title, body = "Заказчик принял работу", "Сделка завершена"
	case job.DealDisputed:
		title, body = "Открыт спор", "Разберёмся вместе — опишите, что пошло не так"
	default:
		return
	}
	s.notify.Send(ctx, target, title, body,
		map[string]string{"route": "/deals/" + d.ID, "dealId": d.ID})
}
