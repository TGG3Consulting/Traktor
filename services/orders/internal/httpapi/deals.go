package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"traktor/orders/internal/job"
	"traktor/orders/internal/profiles"
)

type dealStepBody struct {
	// Шаг: on_the_way | in_progress | work_done | completed | disputed.
	Status string `json:"status"`
	Note   string `json:"note"`
}

type dealCancelBody struct {
	Reason string `json:"reason"`
}

func (s *Server) confirmDeal(w http.ResponseWriter, r *http.Request) {
	deal, err := s.svc.ConfirmDeal(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "id"))
	if err != nil {
		failDeal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, deal)
}

func (s *Server) dealByJob(w http.ResponseWriter, r *http.Request) {
	deal, err := s.svc.DealByJob(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "id"))
	if errors.Is(err, job.ErrDealNotFound) {
		// Сделки ещё нет — обычное состояние экрана задания.
		writeJSON(w, http.StatusOK, map[string]any{"deal": nil})
		return
	}
	if err != nil {
		failDeal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"deal": deal})
}

func (s *Server) deal(w http.ResponseWriter, r *http.Request) {
	deal, err := s.svc.Deal(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "dealId"))
	if err != nil {
		failDeal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, s.dealWithNames(r, deal))
}

// dealWithNames добавляет к сделке имена сторон: на этом экране люди уже
// договорились и должны видеть, с кем имеют дело.
func (s *Server) dealWithNames(r *http.Request, d *job.Deal) map[string]any {
	people := s.svc.Profiles(r.Context(), []string{d.ClientID, d.OwnerID})

	raw, _ := json.Marshal(d)
	out := map[string]any{}
	_ = json.Unmarshal(raw, &out)

	if p, ok := people[d.ClientID]; ok {
		out["clientName"] = profiles.DisplayName(p, "Заказчик")
	}
	if p, ok := people[d.OwnerID]; ok {
		out["ownerName"] = profiles.DisplayName(p, "Исполнитель")
	}
	ratings := s.svc.Ratings(r.Context(), []string{d.ClientID, d.OwnerID})
	if rt, ok := ratings[d.OwnerID]; ok {
		out["ownerRating"] = rt.Rating
		out["ownerRatingCount"] = rt.Count
	}
	if rt, ok := ratings[d.ClientID]; ok {
		out["clientRating"] = rt.Rating
		out["clientRatingCount"] = rt.Count
	}
	return out
}

func (s *Server) myDeals(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	items, err := s.svc.MyDeals(r.Context(), r.Header.Get(userHeader), limit, offset)
	if err != nil {
		failDeal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) advanceDeal(w http.ResponseWriter, r *http.Request) {
	var body dealStepBody
	if !decode(w, r, &body) {
		return
	}
	to := job.DealStatus(body.Status)
	switch to {
	case job.DealOnTheWay, job.DealInProgress, job.DealWorkDone,
		job.DealCompleted, job.DealDisputed:
	default:
		problem(w, http.StatusBadRequest, "invalid_status", "недопустимый шаг сделки")
		return
	}

	deal, err := s.svc.AdvanceDeal(r.Context(), r.Header.Get(userHeader),
		chi.URLParam(r, "dealId"), to, body.Note)
	if err != nil {
		failDeal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, deal)
}

func (s *Server) cancelDeal(w http.ResponseWriter, r *http.Request) {
	var body dealCancelBody
	if !decode(w, r, &body) {
		return
	}
	deal, err := s.svc.CancelDeal(r.Context(), r.Header.Get(userHeader),
		chi.URLParam(r, "dealId"), body.Reason)
	if err != nil {
		failDeal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, deal)
}

func failDeal(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, job.ErrDealNotFound):
		problem(w, http.StatusNotFound, "deal_not_found", "сделка не найдена")
	case errors.Is(err, job.ErrDealNotParty):
		problem(w, http.StatusForbidden, "not_party", "вы не участник этой сделки")
	case errors.Is(err, job.ErrDealWrongPerson):
		problem(w, http.StatusConflict, "wrong_person", "этот шаг делает вторая сторона")
	case errors.Is(err, job.ErrDealClosed):
		problem(w, http.StatusConflict, "deal_closed", "сделка уже закрыта")
	case errors.Is(err, job.ErrDealStep):
		problem(w, http.StatusConflict, "bad_step", "этот шаг сейчас недоступен")
	default:
		fail(w, err)
	}
}
