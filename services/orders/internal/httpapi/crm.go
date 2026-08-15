package httpapi

import (
	"net/http"

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
