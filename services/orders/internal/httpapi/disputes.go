package httpapi

import (
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"traktor/orders/internal/job"
	"traktor/orders/internal/profiles"
)

// Споры (ТЗ §4.1, п.4): открывает участник сделки, разбирает модератор.

type disputeBody struct {
	Reason string   `json:"reason"`
	Photos []string `json:"photos"`
}

type resolveBody struct {
	Outcome    string `json:"outcome"`
	Resolution string `json:"resolution"`
}

// openDispute — POST /v1/deals/{dealId}/dispute.
func (s *Server) openDispute(w http.ResponseWriter, r *http.Request) {
	var body disputeBody
	if !decode(w, r, &body) {
		return
	}
	d, err := s.svc.OpenDispute(r.Context(), r.Header.Get(userHeader),
		chi.URLParam(r, "dealId"), body.Reason, body.Photos)
	if err != nil {
		failDispute(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, d)
}

// dispute — GET /v1/deals/{dealId}/dispute. Участник видит свой спор.
func (s *Server) dispute(w http.ResponseWriter, r *http.Request) {
	d, err := s.svc.DisputeOfDeal(r.Context(), r.Header.Get(userHeader),
		chi.URLParam(r, "dealId"))
	if err != nil {
		failDispute(w, err)
		return
	}
	writeJSON(w, http.StatusOK, d)
}

// disputeQueue — GET /v1/moderation/disputes. Очередь разбора.
func (s *Server) disputeQueue(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := s.svc.DisputeQueue(r.Context(), limit)
	if err != nil {
		failDispute(w, err)
		return
	}

	// Имена сторон: модератор разбирает конфликт людей, а не идентификаторов.
	ids := make([]string, 0, len(items)*2)
	for _, d := range items {
		ids = append(ids, d.ClientID, d.OwnerID)
	}
	people := s.svc.Profiles(r.Context(), ids)

	out := make([]map[string]any, 0, len(items))
	for _, d := range items {
		out = append(out, map[string]any{
			"id":         d.ID,
			"dealId":     d.DealID,
			"jobId":      d.JobID,
			"jobTitle":   d.JobTitle,
			"reason":     d.Reason,
			"photos":     d.Photos,
			"openedBy":   d.OpenedBy,
			"clientName": profiles.DisplayName(people[d.ClientID], "Заказчик"),
			"ownerName":  profiles.DisplayName(people[d.OwnerID], "Исполнитель"),
			// Кто именно пожаловался — важная деталь для разбора.
			"openedByClient": d.OpenedBy == d.ClientID,
			"createdAt":      d.CreatedAt,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": out})
}

// resolveDispute — POST /v1/moderation/disputes/{id}/resolve.
func (s *Server) resolveDispute(w http.ResponseWriter, r *http.Request) {
	var body resolveBody
	if !decode(w, r, &body) {
		return
	}
	d, err := s.svc.ResolveDispute(r.Context(), r.Header.Get(userHeader),
		chi.URLParam(r, "id"), job.DisputeOutcome(strings.TrimSpace(body.Outcome)),
		body.Resolution)
	if err != nil {
		failDispute(w, err)
		return
	}
	writeJSON(w, http.StatusOK, d)
}

// requireModerator — разбор споров доступен только модерации. Роли приходят
// от шлюза, который проверил их по подписи токена.
func (s *Server) requireModerator(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		for _, role := range strings.Split(r.Header.Get("X-User-Roles"), ",") {
			switch strings.TrimSpace(role) {
			case "moderator", "admin":
				next.ServeHTTP(w, r)
				return
			}
		}
		problem(w, http.StatusForbidden, "not_moderator", "раздел доступен модерации")
	})
}

func failDispute(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, job.ErrDisputeNotFound):
		problem(w, http.StatusNotFound, "dispute_not_found", "спор не найден")
	case errors.Is(err, job.ErrDisputeForbidden), errors.Is(err, job.ErrDealNotParty):
		problem(w, http.StatusForbidden, "dispute_forbidden", "это чужая сделка")
	case errors.Is(err, job.ErrDisputeExists):
		problem(w, http.StatusConflict, "dispute_exists", "спор по этой сделке уже открыт")
	case errors.Is(err, job.ErrDisputeClosed):
		problem(w, http.StatusConflict, "dispute_closed", "спор уже разобран")
	case errors.Is(err, job.ErrDisputeStage):
		problem(w, http.StatusConflict, "dispute_stage",
			"спор открывается по начатой работе — до выезда сделку просто отменяют")
	case errors.Is(err, job.ErrDisputeReason):
		problem(w, http.StatusBadRequest, "dispute_reason",
			"опишите, что пошло не так, — хотя бы пару предложений")
	case errors.Is(err, job.ErrDisputeOutcome):
		problem(w, http.StatusBadRequest, "dispute_outcome", "выберите, в чью пользу решение")
	case errors.Is(err, job.ErrDisputeResolution):
		problem(w, http.StatusBadRequest, "dispute_resolution", "решение нужно обосновать")
	default:
		fail(w, err)
	}
}
