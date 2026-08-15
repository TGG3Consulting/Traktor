package httpapi

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"traktor/orders/internal/job"
	"traktor/orders/internal/profiles"
	"traktor/orders/internal/service"
)

type offerBody struct {
	Kind    string  `json:"kind"`
	Price   int64   `json:"price"`
	Comment string  `json:"comment"`
	ETA     string  `json:"eta"`
	UnitID  *string `json:"unitId"`
}

type declineBody struct {
	Reason string `json:"reason"`
}

type counterBody struct {
	Price int64 `json:"price"`
}

func (s *Server) makeOffer(w http.ResponseWriter, r *http.Request) {
	var body offerBody
	if !decode(w, r, &body) {
		return
	}
	kind := job.OfferKind(body.Kind)
	if kind != job.OfferAccept && kind != job.OfferCounter {
		problem(w, http.StatusBadRequest, "invalid_kind", "kind может быть accept или counter")
		return
	}

	offer, err := s.svc.MakeOffer(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "id"),
		service.OfferInput{
			Kind:    kind,
			Price:   body.Price,
			Comment: body.Comment,
			ETA:     body.ETA,
			UnitID:  body.UnitID,
		})
	if err != nil {
		failOffer(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, offer)
}

func (s *Server) myOfferForJob(w http.ResponseWriter, r *http.Request) {
	offer, err := s.svc.MyOfferForJob(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "id"))
	if errors.Is(err, job.ErrOfferNotFound) {
		// Отклика ещё нет — это нормальное состояние экрана, а не ошибка.
		writeJSON(w, http.StatusOK, map[string]any{"offer": nil})
		return
	}
	if err != nil {
		failOffer(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"offer": offer})
}

func (s *Server) myOffers(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	items, err := s.svc.MyOffers(r.Context(), r.Header.Get(userHeader), limit, offset)
	if err != nil {
		failOffer(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) jobOffers(w http.ResponseWriter, r *http.Request) {
	items, err := s.svc.JobOffers(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "id"))
	if err != nil {
		failOffer(w, err)
		return
	}

	// Имя исполнителя живёт в identity: подмешиваем его здесь, одним запросом
	// на весь список — заказчику нужно видеть, кому он отвечает.
	ids := make([]string, 0, len(items))
	for _, o := range items {
		ids = append(ids, o.OwnerID)
	}
	people := s.svc.Profiles(r.Context(), ids)

	out := make([]map[string]any, 0, len(items))
	for _, o := range items {
		row := offerRow(o)
		if p, ok := people[o.OwnerID]; ok {
			row["ownerName"] = profiles.DisplayName(p, "Исполнитель")
			row["ownerCity"] = p.City
			row["ownerRating"] = p.Rating
			row["ownerRatingCount"] = p.RatingCount
			row["ownerVerified"] = p.Verified
		}
		out = append(out, row)
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": out})
}

// offerRow — предложение в виде, пригодном для дополнения карточкой человека.
func offerRow(o job.Offer) map[string]any {
	row := map[string]any{
		"id":            o.ID,
		"jobId":         o.JobID,
		"ownerId":       o.OwnerID,
		"kind":          o.Kind,
		"price":         o.Price,
		"currency":      o.Currency,
		"comment":       o.Comment,
		"eta":           o.ETA,
		"status":        o.Status,
		"declineReason": o.DeclineReason,
		"createdAt":     o.CreatedAt,
		"updatedAt":     o.UpdatedAt,
	}
	if o.ClientCounterPrice != nil {
		row["clientCounterPrice"] = *o.ClientCounterPrice
	}
	if o.ClientCounterAt != nil {
		row["clientCounterAt"] = *o.ClientCounterAt
	}
	return row
}

func (s *Server) withdrawOffer(w http.ResponseWriter, r *http.Request) {
	offer, err := s.svc.WithdrawOffer(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "offerId"))
	if err != nil {
		failOffer(w, err)
		return
	}
	writeJSON(w, http.StatusOK, offer)
}

func (s *Server) acceptOffer(w http.ResponseWriter, r *http.Request) {
	offer, err := s.svc.AcceptOffer(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "offerId"))
	if err != nil {
		failOffer(w, err)
		return
	}
	writeJSON(w, http.StatusOK, offer)
}

func (s *Server) declineOffer(w http.ResponseWriter, r *http.Request) {
	var body declineBody
	if r.ContentLength > 0 && !decode(w, r, &body) {
		return
	}
	offer, err := s.svc.DeclineOffer(r.Context(), r.Header.Get(userHeader),
		chi.URLParam(r, "offerId"), body.Reason)
	if err != nil {
		failOffer(w, err)
		return
	}
	writeJSON(w, http.StatusOK, offer)
}

func (s *Server) counterOffer(w http.ResponseWriter, r *http.Request) {
	var body counterBody
	if !decode(w, r, &body) {
		return
	}
	offer, err := s.svc.CounterOffer(r.Context(), r.Header.Get(userHeader),
		chi.URLParam(r, "offerId"), body.Price)
	if err != nil {
		failOffer(w, err)
		return
	}
	writeJSON(w, http.StatusOK, offer)
}

// failOffer переводит ошибки откликов в коды ответа. Формулировки — те, что
// можно показать человеку без перевода.
func failOffer(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, job.ErrOfferNotFound):
		problem(w, http.StatusNotFound, "offer_not_found", "предложение не найдено")
	case errors.Is(err, job.ErrOwnJob):
		problem(w, http.StatusForbidden, "own_job", "это ваше задание — откликнуться на него нельзя")
	case errors.Is(err, job.ErrJobNotOpen):
		problem(w, http.StatusConflict, "job_not_open", "задание больше не принимает отклики")
	case errors.Is(err, job.ErrAuctionMode):
		problem(w, http.StatusConflict, "auction_mode", "здесь идёт аукцион — нужна ставка, а не отклик")
	case errors.Is(err, job.ErrOfferExists):
		problem(w, http.StatusConflict, "offer_exists", "вы уже откликнулись на это задание")
	case errors.Is(err, job.ErrOfferNotActive):
		problem(w, http.StatusConflict, "offer_not_active", "предложение уже неактивно")
	case errors.Is(err, job.ErrCounterUsed):
		problem(w, http.StatusConflict, "counter_used", "встречное предложение уже отправлено")
	default:
		fail(w, err)
	}
}
