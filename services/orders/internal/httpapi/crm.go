package httpapi

import (
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"traktor/orders/internal/job"
	"traktor/orders/internal/profiles"
)

// business — GET /v1/crm/business. Сводка исполнителя «Мой бизнес» (ТЗ §3.1).
func (s *Server) business(w http.ResponseWriter, r *http.Request) {
	period := job.Period(r.URL.Query().Get("period"))
	switch period {
	case job.PeriodWeek, job.PeriodMonth, job.PeriodQuarter, job.PeriodYear, job.PeriodAll:
	default:
		period = job.PeriodMonth
	}

	me := r.Header.Get(userHeader)
	data, err := s.svc.Business(r.Context(), me, period)
	if err != nil {
		fail(w, err)
		return
	}

	// Имена клиентов: «3 сделки с Тиграном» читается, «3 сделки с 8f2c…» — нет.
	ids := make([]string, 0, len(data.Clients))
	for _, c := range data.Clients {
		ids = append(ids, c.UserID)
	}
	people := s.svc.Profiles(r.Context(), ids)

	clients := make([]map[string]any, 0, len(data.Clients))
	for _, c := range data.Clients {
		clients = append(clients, map[string]any{
			"userId":  c.UserID,
			"name":    profiles.DisplayName(people[c.UserID], "Заказчик"),
			"deals":   c.Deals,
			"total":   c.Total,
			"last":    c.Last,
			"regular": c.Regular(),
		})
	}

	delta, comparable := data.Delta()
	writeJSON(w, http.StatusOK, map[string]any{
		"period":     data.Period,
		"income":     data.Income,
		"deals":      data.Deals,
		"average":    data.Average,
		"currency":   data.Currency,
		"prevIncome": data.PrevIncome,
		// Дельта без прошлого дохода не считается: «+∞%» ничего не объясняет.
		"delta":           delta,
		"deltaComparable": comparable,
		"funnel": map[string]any{
			"offers":      data.Funnel.Offers,
			"won":         data.Funnel.Won,
			"completed":   data.Funnel.Completed,
			"winRate":     data.Funnel.WinRate(),
			"finishRate":  data.Funnel.FinishRate(),
		},
		"clients": clients,
	})
}

// spending — GET /v1/crm/spending. Сводка заказчика «Мои расходы» (ТЗ §3.2).
func (s *Server) spending(w http.ResponseWriter, r *http.Request) {
	period := job.Period(r.URL.Query().Get("period"))
	switch period {
	case job.PeriodWeek, job.PeriodMonth, job.PeriodQuarter, job.PeriodYear, job.PeriodAll:
	default:
		period = job.PeriodMonth
	}

	data, err := s.svc.Spending(r.Context(), r.Header.Get(userHeader), period)
	if err != nil {
		fail(w, err)
		return
	}

	ids := make([]string, 0, len(data.Owners))
	for _, o := range data.Owners {
		ids = append(ids, o.UserID)
	}
	people := s.svc.Profiles(r.Context(), ids)

	owners := make([]map[string]any, 0, len(data.Owners))
	for _, o := range data.Owners {
		owners = append(owners, map[string]any{
			"userId":  o.UserID,
			"name":    profiles.DisplayName(people[o.UserID], "Исполнитель"),
			"deals":   o.Deals,
			"total":   o.Total,
			"last":    o.Last,
			"regular": o.Regular(),
		})
	}

	delta, comparable := data.Delta()
	writeJSON(w, http.StatusOK, map[string]any{
		"period":          data.Period,
		"spent":           data.Spent,
		"deals":           data.Deals,
		"average":         data.Average,
		"currency":        data.Currency,
		"prevSpent":       data.PrevSpent,
		"delta":           delta,
		"deltaComparable": comparable,
		"byCategory":      data.ByCategory,
		"owners":          owners,
		// Экономия на торге — самый наглядный ответ на вопрос «зачем мне
		// площадка» (ТЗ §3.2).
		"saved": data.Saved,
	})
}

type busyBody struct {
	// Day в формате 2006-01-02: занятость измеряется днями, не минутами.
	Day  string `json:"day"`
	Note string `json:"note"`
}

// calendar — GET /v1/crm/calendar?month=2026-08. Занятость на месяц (ТЗ §3.1).
func (s *Server) calendar(w http.ResponseWriter, r *http.Request) {
	month := time.Now().UTC()
	if raw := r.URL.Query().Get("month"); raw != "" {
		parsed, err := time.Parse("2006-01", raw)
		if err != nil {
			problem(w, http.StatusBadRequest, "bad_month", "месяц указывается как 2026-08")
			return
		}
		month = parsed
	}

	days, err := s.svc.Calendar(r.Context(), r.Header.Get(userHeader), month)
	if err != nil {
		fail(w, err)
		return
	}

	out := make([]map[string]any, 0, len(days))
	for _, d := range days {
		row := map[string]any{
			"day":    d.Day.Format("2006-01-02"),
			"source": d.Source,
		}
		if d.Note != "" {
			row["note"] = d.Note
		}
		if d.DealID != "" {
			row["dealId"] = d.DealID
			row["title"] = d.Title
		}
		out = append(out, row)
	}
	writeJSON(w, http.StatusOK, map[string]any{"month": month.Format("2006-01"), "items": out})
}

// markBusy — POST /v1/crm/calendar. Отметить день «не работаю».
func (s *Server) markBusy(w http.ResponseWriter, r *http.Request) {
	var body busyBody
	if !decode(w, r, &body) {
		return
	}
	day, err := time.Parse("2006-01-02", strings.TrimSpace(body.Day))
	if err != nil {
		problem(w, http.StatusBadRequest, "bad_day", "дата указывается как 2026-08-20")
		return
	}
	if err := s.svc.MarkBusy(r.Context(), r.Header.Get(userHeader), day, body.Note); err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"day": body.Day, "source": "manual"})
}

// unmarkBusy — DELETE /v1/crm/calendar/{day}. Снять свою отметку.
func (s *Server) unmarkBusy(w http.ResponseWriter, r *http.Request) {
	day, err := time.Parse("2006-01-02", chi.URLParam(r, "day"))
	if err != nil {
		problem(w, http.StatusBadRequest, "bad_day", "дата указывается как 2026-08-20")
		return
	}
	if err := s.svc.UnmarkBusy(r.Context(), r.Header.Get(userHeader), day); err != nil {
		fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
