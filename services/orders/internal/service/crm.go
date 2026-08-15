package service

import (
	"context"

	"traktor/orders/internal/job"
)

// Business — сводка «Мой бизнес» исполнителя (ТЗ §3.1).
//
// Всё считается из завершённых сделок: человек ничего не заполняет руками,
// поэтому цифры всегда честные и всегда есть.
func (s *Service) Business(ctx context.Context, ownerID string, period job.Period) (*job.Business, error) {
	r := job.RangeOf(period, s.now().UTC())

	income, deals, err := s.st.IncomeOf(ctx, ownerID, r.From, r.To)
	if err != nil {
		return nil, err
	}
	// Предыдущий отрезок нужен только ради дельты: без сравнения цифра дохода
	// ничего не говорит о том, стало лучше или хуже.
	prev, _, err := s.st.IncomeOf(ctx, ownerID, r.PrevFrom, r.PrevTo)
	if err != nil {
		return nil, err
	}
	funnel, err := s.st.FunnelOf(ctx, ownerID, r.From, r.To)
	if err != nil {
		return nil, err
	}
	clients, err := s.st.ClientsOf(ctx, ownerID, r.From, r.To, 20)
	if err != nil {
		return nil, err
	}

	return &job.Business{
		Period:     period,
		Income:     income,
		Deals:      deals,
		Average:    job.AverageCheck(income, deals),
		Currency:   "AMD",
		PrevIncome: prev,
		Funnel:     funnel,
		Clients:    clients,
	}, nil
}
