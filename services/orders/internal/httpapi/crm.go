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
