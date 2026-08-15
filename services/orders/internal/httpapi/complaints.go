package httpapi

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"traktor/orders/internal/job"
	"traktor/orders/internal/profiles"
)

// Жалобы и сводка площадки (ТЗ §4.1, п.1 и 6).

type complaintBody struct {
	TargetKind string `json:"targetKind"`
	TargetID   string `json:"targetId"`
	Reason     string `json:"reason"`
}

type complaintReviewBody struct {
	Action string `json:"action"`
	Note   string `json:"note"`
}

// complain — POST /v1/complaints.
func (s *Server) complain(w http.ResponseWriter, r *http.Request) {
	var body complaintBody
	if !decode(w, r, &body) {
		return
	}
	c, err := s.svc.Complain(r.Context(), r.Header.Get(userHeader),
		strings.TrimSpace(body.TargetKind), strings.TrimSpace(body.TargetID), body.Reason)
	if err != nil {
		failComplaint(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, c)
}

// complaintQueue — GET /v1/moderation/complaints.
func (s *Server) complaintQueue(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := s.svc.ComplaintQueue(r.Context(), limit)
	if err != nil {
		failComplaint(w, err)
		return
	}

	ids := make([]string, 0, len(items)*2)
	for _, c := range items {
		ids = append(ids, c.AuthorID)
		if c.TargetKind == job.TargetUser {
			ids = append(ids, c.TargetID)
		}
	}
	people := s.svc.Profiles(r.Context(), ids)

	out := make([]map[string]any, 0, len(items))
	for _, c := range items {
		row := map[string]any{
			"id":         c.ID,
			"targetKind": c.TargetKind,
			"targetId":   c.TargetID,
			"reason":     c.Reason,
			"authorName": profiles.DisplayName(people[c.AuthorID], "Пользователь"),
			// Сколько раз пожаловались на этот же объект: одна жалоба может
			// быть сведением счётов, пять — уже сигнал.
			"sameTarget": c.SameTarget,
			"createdAt":  c.CreatedAt,
		}
		switch c.TargetKind {
		case job.TargetJob:
			row["targetTitle"] = c.TargetTitle
			row["route"] = "/jobs/" + c.TargetID
		case job.TargetUser:
			row["targetTitle"] = profiles.DisplayName(people[c.TargetID], "Пользователь")
			row["route"] = "/users/" + c.TargetID
		}
		out = append(out, row)
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": out})
}

// reviewComplaint — POST /v1/moderation/complaints/{id}/review.
func (s *Server) reviewComplaint(w http.ResponseWriter, r *http.Request) {
	var body complaintReviewBody
	if !decode(w, r, &body) {
		return
	}
	c, err := s.svc.ReviewComplaint(r.Context(), r.Header.Get(userHeader),
		chi.URLParam(r, "id"), job.ComplaintAction(strings.TrimSpace(body.Action)), body.Note)
	if err != nil {
		failComplaint(w, err)
		return
	}
	writeJSON(w, http.StatusOK, c)
}

// dashboard — GET /v1/moderation/dashboard?days=30. Сводка площадки.
func (s *Server) dashboard(w http.ResponseWriter, r *http.Request) {
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	if days <= 0 || days > 365 {
		days = 30
	}
	to := time.Now().UTC()
	from := to.AddDate(0, 0, -days)

	stats, err := s.svc.PlatformStats(r.Context(), from, to)
	if err != nil {
		fail(w, err)
		return
	}
	// Предыдущий такой же отрезок: абсолютная цифра ничего не говорит, пока
	// не видно, растёт она или падает.
	prevTo := from.Add(-time.Nanosecond)
	prevFrom := prevTo.AddDate(0, 0, -days)
	prev, _ := s.svc.PlatformStats(r.Context(), prevFrom, prevTo)

	writeJSON(w, http.StatusOK, map[string]any{
		"days":           days,
		"from":           from,
		"to":             to,
		"users":          stats.Users,
		"jobs":           stats.Jobs,
		"deals":          stats.Deals,
		"completed":      stats.Completed,
		"gmv":            stats.GMV,
		"avgCheck":       stats.AvgCheck(),
		"conversion":     stats.Conversion(),
		"openDisputes":   stats.OpenDisputes,
		"openComplaints": stats.OpenComplaints,
		"prev": map[string]any{
			"users":      prev.Users,
			"jobs":       prev.Jobs,
			"deals":      prev.Deals,
			"gmv":        prev.GMV,
			"conversion": prev.Conversion(),
		},
	})
}

func failComplaint(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, job.ErrComplaintNotFound):
		problem(w, http.StatusNotFound, "complaint_not_found", "жалоба не найдена")
	case errors.Is(err, job.ErrComplaintExists):
		problem(w, http.StatusConflict, "complaint_exists",
			"вы уже жаловались — модерация смотрит")
	case errors.Is(err, job.ErrComplaintClosed):
		problem(w, http.StatusConflict, "complaint_closed", "жалоба уже разобрана")
	case errors.Is(err, job.ErrComplaintReason):
		problem(w, http.StatusBadRequest, "complaint_reason",
			"опишите, в чём проблема, — иначе модерации нечего смотреть")
	case errors.Is(err, job.ErrComplaintTarget):
		problem(w, http.StatusBadRequest, "complaint_target",
			"жаловаться можно на задание или на человека")
	case errors.Is(err, job.ErrComplaintSelf):
		problem(w, http.StatusBadRequest, "complaint_self", "это ваш собственный контент")
	case errors.Is(err, job.ErrComplaintAction):
		problem(w, http.StatusBadRequest, "complaint_action", "выберите решение по жалобе")
	default:
		fail(w, err)
	}
}
