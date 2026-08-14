package service

import (
	"context"
	"fmt"
	"strings"

	"github.com/google/uuid"

	"traktor/orders/internal/job"
	"traktor/orders/internal/notify"
)

// OfferInput — предложение исполнителя (ТЗ §2.10).
type OfferInput struct {
	Kind    job.OfferKind
	Price   int64
	Comment string
	ETA     string
	UnitID  *string
}

// MakeOffer — исполнитель откликается на задание с фиксированной ценой.
//
// Повторный отклик того же исполнителя не создаёт вторую карточку в списке
// заказчика: активное предложение обновляется. Так «передумал и предложил
// другую цену» работает предсказуемо, без ручного отзыва.
func (s *Service) MakeOffer(ctx context.Context, ownerID, jobID string, in OfferInput) (*job.Offer, error) {
	j, err := s.st.ByID(ctx, jobID)
	if err != nil {
		return nil, err
	}
	if j.ClientID == ownerID {
		return nil, job.ErrOwnJob
	}
	if err := job.CanAcceptOffers(j); err != nil {
		return nil, err
	}

	price := in.Price
	if in.Kind == job.OfferAccept && j.BudgetAmount != nil {
		// «Принимаю цену» — берём цену задания с сервера, а не из запроса:
		// клиент мог показывать устаревшую.
		price = *j.BudgetAmount
	}

	now := s.now().UTC()
	offer := &job.Offer{
		JobID:     jobID,
		OwnerID:   ownerID,
		Kind:      in.Kind,
		Price:     price,
		Currency:  j.Currency,
		Comment:   strings.TrimSpace(in.Comment),
		ETA:       strings.TrimSpace(in.ETA),
		UnitID:    in.UnitID,
		Status:    job.OfferActive,
		UpdatedAt: now,
	}
	var jobPrice int64
	if j.BudgetAmount != nil {
		jobPrice = *j.BudgetAmount
	}
	if err := job.ValidateOffer(offer, jobPrice); err != nil {
		return nil, err
	}

	if existing, err := s.st.MyOfferForJob(ctx, jobID, ownerID); err == nil {
		switch existing.Status {
		case job.OfferAccepted:
			// Уже выбран — менять условия нельзя, это меняло бы сделку задним числом.
			return existing, nil
		case job.OfferActive, job.OfferCounterOffered:
			existing.Kind = offer.Kind
			existing.Price = offer.Price
			existing.Comment = offer.Comment
			existing.ETA = offer.ETA
			existing.UnitID = offer.UnitID
			existing.Status = job.OfferActive
			// Новое предложение исполнителя закрывает прошлый раунд торга.
			existing.ClientCounterPrice = nil
			existing.ClientCounterAt = nil
			existing.UpdatedAt = now
			if err := s.st.UpdateOffer(ctx, existing); err != nil {
				return nil, err
			}
			return existing, nil
		}
	}

	offer.ID = uuid.NewString()
	offer.CreatedAt = now
	if err := s.st.CreateOffer(ctx, offer); err != nil {
		return nil, err
	}

	// Заказчик узнаёт об отклике сразу: скорость ответа — главное, чего ждут
	// от площадки обе стороны (ТЗ §2.14).
	s.notify.Send(ctx, j.ClientID, notify.TitleNewOffer,
		fmt.Sprintf("%s · %s", j.Title, notify.MoneyRU(offer.Price, offer.Currency)),
		map[string]string{"route": "/jobs/" + j.ID + "/offers", "jobId": j.ID})

	return offer, nil
}

// WithdrawOffer — исполнитель снимает своё предложение.
func (s *Service) WithdrawOffer(ctx context.Context, ownerID, offerID string) (*job.Offer, error) {
	o, err := s.st.OfferByID(ctx, offerID)
	if err != nil {
		return nil, err
	}
	if o.OwnerID != ownerID {
		return nil, job.ErrForbidden
	}
	if o.Status == job.OfferAccepted {
		// После выбора это уже обязательство, а не предложение: отказ идёт
		// через отмену сделки с последствиями (ТЗ §2.11).
		return nil, job.ErrOfferNotActive
	}
	o.Status = job.OfferWithdrawn
	o.UpdatedAt = s.now().UTC()
	if err := s.st.UpdateOffer(ctx, o); err != nil {
		return nil, err
	}
	return o, nil
}

// DeclineOffer — заказчик отклоняет предложение (причина необязательна).
func (s *Service) DeclineOffer(ctx context.Context, clientID, offerID, reason string) (*job.Offer, error) {
	o, _, err := s.offerOfMyJob(ctx, clientID, offerID)
	if err != nil {
		return nil, err
	}
	if o.Status == job.OfferAccepted {
		return nil, job.ErrOfferNotActive
	}
	o.Status = job.OfferDeclined
	o.DeclineReason = strings.TrimSpace(reason)
	o.UpdatedAt = s.now().UTC()
	if err := s.st.UpdateOffer(ctx, o); err != nil {
		return nil, err
	}

	text := "Заказчик выбрал другой вариант"
	if o.DeclineReason != "" {
		text = o.DeclineReason
	}
	s.notify.Send(ctx, o.OwnerID, notify.TitleDeclined, text,
		map[string]string{"route": "/jobs/" + o.JobID, "jobId": o.JobID})

	return o, nil
}

// CounterOffer — встречная цена заказчика. Раунд ровно один (ТЗ §2.10):
// дальше либо исполнитель соглашается новым предложением, либо стороны
// расходятся. Это сознательное ограничение, чтобы переписка не превращалась
// в бесконечный торг.
func (s *Service) CounterOffer(ctx context.Context, clientID, offerID string, price int64) (*job.Offer, error) {
	o, _, err := s.offerOfMyJob(ctx, clientID, offerID)
	if err != nil {
		return nil, err
	}
	// Порядок проверок важен: после первой встречной цены отклик уже не
	// «активен», и без этой ветки заказчик получил бы невнятное «предложение
	// неактивно» вместо понятного «встречное уже отправлено».
	if o.ClientCounterPrice != nil {
		return nil, job.ErrCounterUsed
	}
	if o.Status != job.OfferActive {
		return nil, job.ErrOfferNotActive
	}
	if price <= 0 {
		return nil, &job.ValidationError{Fields: map[string]string{"price": "укажите цену"}}
	}

	now := s.now().UTC()
	o.ClientCounterPrice = &price
	o.ClientCounterAt = &now
	o.Status = job.OfferCounterOffered
	o.UpdatedAt = now
	if err := s.st.UpdateOffer(ctx, o); err != nil {
		return nil, err
	}

	s.notify.Send(ctx, o.OwnerID, notify.TitleCounter,
		notify.MoneyRU(price, o.Currency)+" — примите или предложите свою",
		map[string]string{"route": "/jobs/" + o.JobID, "jobId": o.JobID})

	return o, nil
}

// AcceptOffer — заказчик выбирает исполнителя. Задание переходит в
// deal_pending, остальные активные предложения отклоняются автоматически:
// иначе исполнители продолжали бы ждать ответа по уже закрытому заданию.
func (s *Service) AcceptOffer(ctx context.Context, clientID, offerID string) (*job.Offer, error) {
	o, j, err := s.offerOfMyJob(ctx, clientID, offerID)
	if err != nil {
		return nil, err
	}
	if o.Status != job.OfferActive && o.Status != job.OfferCounterOffered {
		return nil, job.ErrOfferNotActive
	}
	if !job.CanTransition(j.Status, job.StatusDealPending) {
		return nil, job.ErrBadTransition
	}

	now := s.now().UTC()
	// Если исполнитель согласился на встречную цену, работает именно она.
	if o.Status == job.OfferCounterOffered && o.ClientCounterPrice != nil {
		o.Price = *o.ClientCounterPrice
	}
	o.Status = job.OfferAccepted
	o.UpdatedAt = now
	if err := s.st.UpdateOffer(ctx, o); err != nil {
		return nil, err
	}

	others, err := s.st.OffersByJob(ctx, j.ID)
	if err != nil {
		return nil, err
	}
	for i := range others {
		other := others[i]
		if other.ID == o.ID || other.Status == job.OfferDeclined || other.Status == job.OfferWithdrawn {
			continue
		}
		other.Status = job.OfferDeclined
		other.DeclineReason = "выбран другой исполнитель"
		other.UpdatedAt = now
		if err := s.st.UpdateOffer(ctx, &other); err != nil {
			return nil, err
		}
	}

	j.Status = job.StatusDealPending
	j.UpdatedAt = now
	if err := s.st.Update(ctx, j); err != nil {
		return nil, err
	}

	s.notify.Send(ctx, o.OwnerID, notify.TitleAccepted,
		fmt.Sprintf("%s · %s", j.Title, notify.MoneyRU(o.Price, o.Currency)),
		map[string]string{"route": "/jobs/" + j.ID, "jobId": j.ID})
	for i := range others {
		if others[i].ID == o.ID || others[i].OwnerID == "" {
			continue
		}
		s.notify.Send(ctx, others[i].OwnerID, notify.TitleJobClosed,
			j.Title+" — заказчик выбрал другого исполнителя",
			map[string]string{"route": "/jobs/" + j.ID, "jobId": j.ID})
	}

	return o, nil
}

// JobOffers — список предложений по заданию. Видит только владелец задания:
// конкуренты не должны знать чужие цены (ТЗ §2.9 — анонимность торга).
func (s *Service) JobOffers(ctx context.Context, clientID, jobID string) ([]job.Offer, error) {
	j, err := s.st.ByID(ctx, jobID)
	if err != nil {
		return nil, err
	}
	if j.ClientID != clientID {
		return nil, job.ErrForbidden
	}
	return s.st.OffersByJob(ctx, jobID)
}

// MyOffers — предложения исполнителя («Мои ставки» в панели).
func (s *Service) MyOffers(ctx context.Context, ownerID string, limit, offset int) ([]job.Offer, error) {
	return s.st.OffersByOwner(ctx, ownerID, clampLimit(limit), max0(offset))
}

// MyOfferForJob — своё предложение по конкретному заданию.
func (s *Service) MyOfferForJob(ctx context.Context, ownerID, jobID string) (*job.Offer, error) {
	return s.st.MyOfferForJob(ctx, jobID, ownerID)
}

func (s *Service) offerOfMyJob(ctx context.Context, clientID, offerID string) (*job.Offer, *job.Job, error) {
	o, err := s.st.OfferByID(ctx, offerID)
	if err != nil {
		return nil, nil, err
	}
	j, err := s.st.ByID(ctx, o.JobID)
	if err != nil {
		return nil, nil, err
	}
	if j.ClientID != clientID {
		return nil, nil, job.ErrForbidden
	}
	return o, j, nil
}
