package store

import (
	"context"
	"sort"

	"traktor/orders/internal/job"
)

// Сделки в памяти: та же семантика, что в Postgres — одна сделка на задание.

func (m *Memory) CreateDeal(_ context.Context, d *job.Deal) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, ex := range m.deals {
		if ex.JobID == d.JobID {
			return job.ErrDealStep
		}
	}
	if m.deals == nil {
		m.deals = map[string]job.Deal{}
	}
	m.deals[d.ID] = *d
	return nil
}

func (m *Memory) UpdateDeal(_ context.Context, d *job.Deal) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.deals[d.ID]; !ok {
		return job.ErrDealNotFound
	}
	m.deals[d.ID] = *d
	return nil
}

func (m *Memory) DealByID(_ context.Context, id string) (*job.Deal, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	d, ok := m.deals[id]
	if !ok {
		return nil, job.ErrDealNotFound
	}
	return &d, nil
}

func (m *Memory) DealByJob(_ context.Context, jobID string) (*job.Deal, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	for _, d := range m.deals {
		if d.JobID == jobID {
			copy := d
			return &copy, nil
		}
	}
	return nil, job.ErrDealNotFound
}

func (m *Memory) DealsByUser(_ context.Context, userID string, limit, offset int) ([]job.Deal, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.Deal{}
	for _, d := range m.deals {
		if d.ClientID == userID || d.OwnerID == userID {
			out = append(out, d)
		}
	}
	sort.Slice(out, func(i, k int) bool { return out[i].UpdatedAt.After(out[k].UpdatedAt) })
	if offset >= len(out) {
		return []job.Deal{}, nil
	}
	out = out[offset:]
	if limit > 0 && limit < len(out) {
		out = out[:limit]
	}
	return out, nil
}
