package store

import (
	"context"
	"sort"
	"time"

	"traktor/orders/internal/job"
)

// Те же выборки CRM в памяти — для тестов и запуска без базы.

func (m *Memory) IncomeOf(_ context.Context, ownerID string, from, to time.Time) (int64, int, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var sum int64
	count := 0
	for _, d := range m.deals {
		if d.OwnerID != ownerID || d.Status != job.DealCompleted || d.ClosedAt == nil {
			continue
		}
		if d.ClosedAt.Before(from) || d.ClosedAt.After(to) {
			continue
		}
		sum += d.Price
		count++
	}
	return sum, count, nil
}

func (m *Memory) FunnelOf(_ context.Context, ownerID string, from, to time.Time) (job.Funnel, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var f job.Funnel
	inRange := func(t time.Time) bool { return !t.Before(from) && !t.After(to) }

	for _, o := range m.offers {
		if o.OwnerID == ownerID && inRange(o.CreatedAt) {
			f.Offers++
		}
	}
	for _, b := range m.bids {
		if b.OwnerID == ownerID && inRange(b.CreatedAt) {
			f.Offers++
		}
	}
	for _, d := range m.deals {
		if d.OwnerID != ownerID || !inRange(d.CreatedAt) {
			continue
		}
		f.Won++
		if d.Status == job.DealCompleted {
			f.Completed++
		}
	}
	return f, nil
}

func (m *Memory) ClientsOf(_ context.Context, ownerID string, from, to time.Time, limit int) ([]job.Client, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	byClient := map[string]*job.Client{}
	for _, d := range m.deals {
		if d.OwnerID != ownerID || d.Status != job.DealCompleted || d.ClosedAt == nil {
			continue
		}
		if d.ClosedAt.Before(from) || d.ClosedAt.After(to) {
			continue
		}
		c, ok := byClient[d.ClientID]
		if !ok {
			c = &job.Client{UserID: d.ClientID}
			byClient[d.ClientID] = c
		}
		c.Deals++
		c.Total += d.Price
		if d.ClosedAt.After(c.Last) {
			c.Last = *d.ClosedAt
		}
	}

	out := make([]job.Client, 0, len(byClient))
	for _, c := range byClient {
		out = append(out, *c)
	}
	sort.Slice(out, func(i, k int) bool { return out[i].Total > out[k].Total })
	if limit > 0 && limit < len(out) {
		out = out[:limit]
	}
	return out, nil
}

func (m *Memory) SpendingOf(_ context.Context, clientID string, from, to time.Time) (int64, int, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var sum int64
	count := 0
	for _, d := range m.deals {
		if d.ClientID != clientID || d.Status != job.DealCompleted || d.ClosedAt == nil {
			continue
		}
		if d.ClosedAt.Before(from) || d.ClosedAt.After(to) {
			continue
		}
		sum += d.Price
		count++
	}
	return sum, count, nil
}

func (m *Memory) SpendingByCategory(_ context.Context, clientID string, from, to time.Time) ([]job.CategorySpend, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	byCat := map[string]*job.CategorySpend{}
	for _, d := range m.deals {
		if d.ClientID != clientID || d.Status != job.DealCompleted || d.ClosedAt == nil {
			continue
		}
		if d.ClosedAt.Before(from) || d.ClosedAt.After(to) {
			continue
		}
		category := ""
		if j, ok := m.jobs[d.JobID]; ok && j.CategoryID != nil {
			category = *j.CategoryID
		}
		c, ok := byCat[category]
		if !ok {
			c = &job.CategorySpend{CategoryID: category}
			byCat[category] = c
		}
		c.Total += d.Price
		c.Deals++
	}

	out := make([]job.CategorySpend, 0, len(byCat))
	for _, c := range byCat {
		out = append(out, *c)
	}
	sort.Slice(out, func(i, k int) bool { return out[i].Total > out[k].Total })
	return out, nil
}

func (m *Memory) OwnersOf(_ context.Context, clientID string, from, to time.Time, limit int) ([]job.Client, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	byOwner := map[string]*job.Client{}
	for _, d := range m.deals {
		if d.ClientID != clientID || d.Status != job.DealCompleted || d.ClosedAt == nil {
			continue
		}
		if d.ClosedAt.Before(from) || d.ClosedAt.After(to) {
			continue
		}
		c, ok := byOwner[d.OwnerID]
		if !ok {
			c = &job.Client{UserID: d.OwnerID}
			byOwner[d.OwnerID] = c
		}
		c.Deals++
		c.Total += d.Price
		if d.ClosedAt.After(c.Last) {
			c.Last = *d.ClosedAt
		}
	}

	out := make([]job.Client, 0, len(byOwner))
	for _, c := range byOwner {
		out = append(out, *c)
	}
	sort.Slice(out, func(i, k int) bool { return out[i].Total > out[k].Total })
	if limit > 0 && limit < len(out) {
		out = out[:limit]
	}
	return out, nil
}

func (m *Memory) SavedOnAuctions(_ context.Context, clientID string, from, to time.Time) (int64, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var saved int64
	for _, d := range m.deals {
		if d.ClientID != clientID || d.Status != job.DealCompleted || d.ClosedAt == nil {
			continue
		}
		if d.ClosedAt.Before(from) || d.ClosedAt.After(to) {
			continue
		}
		j, ok := m.jobs[d.JobID]
		if !ok || j.Mode != job.ModeAuction || j.BudgetAmount == nil {
			continue
		}
		if diff := *j.BudgetAmount - d.Price; diff > 0 {
			saved += diff
		}
	}
	return saved, nil
}
