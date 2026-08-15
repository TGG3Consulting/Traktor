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

// Spending — сводка «Мои расходы» заказчика (ТЗ §3.2).
func (s *Service) Spending(ctx context.Context, clientID string, period job.Period) (*job.Spending, error) {
	r := job.RangeOf(period, s.now().UTC())

	spent, deals, err := s.st.SpendingOf(ctx, clientID, r.From, r.To)
	if err != nil {
		return nil, err
	}
	prev, _, err := s.st.SpendingOf(ctx, clientID, r.PrevFrom, r.PrevTo)
	if err != nil {
		return nil, err
	}
	byCategory, err := s.st.SpendingByCategory(ctx, clientID, r.From, r.To)
	if err != nil {
		return nil, err
	}
	owners, err := s.st.OwnersOf(ctx, clientID, r.From, r.To, 20)
	if err != nil {
		return nil, err
	}
	saved, err := s.st.SavedOnAuctions(ctx, clientID, r.From, r.To)
	if err != nil {
		return nil, err
	}

	return &job.Spending{
		Period:     period,
		Spent:      spent,
		Deals:      deals,
		Average:    job.AverageCheck(spent, deals),
		Currency:   "AMD",
		PrevSpent:  prev,
		ByCategory: byCategory,
		Owners:     owners,
		Saved:      saved,
	}, nil
}
