package service

import (
	"context"
	"sort"
	"strings"
	"time"

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

// Calendar — календарь занятости исполнителя на месяц (ТЗ §3.1).
//
// В одном списке и дни со сделками, и собственные отметки «не работаю»:
// человеку важно видеть занятость целиком, а не в двух разных местах.
func (s *Service) Calendar(ctx context.Context, ownerID string, month time.Time) ([]job.BusyDay, error) {
	from, to := job.MonthRange(month)

	deals, err := s.st.BusyByDeals(ctx, ownerID, from, to)
	if err != nil {
		return nil, err
	}
	manual, err := s.st.ManualBusy(ctx, ownerID, from, to)
	if err != nil {
		return nil, err
	}

	// День со сделкой сильнее собственной отметки: сделку уже подтвердили,
	// и «не работаю» её не отменяет.
	busy := make(map[string]job.BusyDay, len(deals)+len(manual))
	for _, d := range manual {
		busy[job.DayKey(d.Day)] = d
	}
	for _, d := range deals {
		busy[job.DayKey(d.Day)] = d
	}

	out := make([]job.BusyDay, 0, len(busy))
	for _, d := range busy {
		out = append(out, d)
	}
	sort.Slice(out, func(i, k int) bool { return out[i].Day.Before(out[k].Day) })
	return out, nil
}

// MarkBusy — отметить день «не работаю».
func (s *Service) MarkBusy(ctx context.Context, ownerID string, day time.Time, note string) error {
	if ownerID == "" {
		return job.ErrForbidden
	}
	return s.st.SetBusyDay(ctx, ownerID, day, strings.TrimSpace(note))
}

// UnmarkBusy — снять свою отметку. Дни со сделками так не снимаются: их
// занятость определяется работой, а не желанием.
func (s *Service) UnmarkBusy(ctx context.Context, ownerID string, day time.Time) error {
	if ownerID == "" {
		return job.ErrForbidden
	}
	return s.st.ClearBusyDay(ctx, ownerID, day)
}

// BusyOn — занят ли исполнитель в этот день. По этому вопросу экран ставки
// предупреждает: «на эту дату у вас уже есть работа» (ТЗ §3.1).
func (s *Service) BusyOn(ctx context.Context, ownerID string, day time.Time) (bool, error) {
	from := time.Date(day.Year(), day.Month(), day.Day(), 0, 0, 0, 0, time.UTC)
	to := from.AddDate(0, 0, 1).Add(-time.Nanosecond)

	deals, err := s.st.BusyByDeals(ctx, ownerID, from, to)
	if err != nil {
		return false, err
	}
	if len(deals) > 0 {
		return true, nil
	}
	manual, err := s.st.ManualBusy(ctx, ownerID, from, to)
	if err != nil {
		return false, err
	}
	return len(manual) > 0, nil
}

// DealsForExport — сделки за период для выгрузки (ТЗ §3.1 п.7, §3.2 п.6).
//
// Берём все состояния, а не только завершённые: в отчёте для бухгалтерии
// важно видеть и отменённые — иначе непонятно, куда делась работа.
func (s *Service) DealsForExport(ctx context.Context, userID string, period job.Period, asOwner bool) ([]job.Deal, error) {
	r := job.RangeOf(period, s.now().UTC())

	// Постранично: за «всё время» у активного исполнителя сделок может быть
	// много, и тянуть их одним запросом без предела — плохая идея.
	const page = 200
	out := []job.Deal{}
	for offset := 0; offset < 5000; offset += page {
		batch, err := s.st.DealsByUser(ctx, userID, page, offset)
		if err != nil {
			return nil, err
		}
		if len(batch) == 0 {
			break
		}
		for _, d := range batch {
			if asOwner && d.OwnerID != userID {
				continue
			}
			if !asOwner && d.ClientID != userID {
				continue
			}
			day := d.CreatedAt
			if d.ClosedAt != nil {
				day = *d.ClosedAt
			}
			if day.Before(r.From) || day.After(r.To) {
				continue
			}
			if j, err := s.st.ByID(ctx, d.JobID); err == nil {
				d.JobTitle = j.Title
			}
			out = append(out, d)
		}
		if len(batch) < page {
			break
		}
	}

	sort.Slice(out, func(i, k int) bool { return out[i].CreatedAt.After(out[k].CreatedAt) })
	return out, nil
}
