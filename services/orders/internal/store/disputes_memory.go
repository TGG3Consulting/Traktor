package store

import (
	"context"
	"sort"

	"traktor/orders/internal/job"
)

// Споры в памяти: та же семантика, что в Postgres — один открытый спор
// на сделку.

func (m *Memory) CreateDispute(_ context.Context, d *job.Dispute) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, ex := range m.disputes {
		if ex.DealID == d.DealID && ex.Status == job.DisputeOpen {
			return job.ErrDisputeExists
		}
	}
	if m.disputes == nil {
		m.disputes = map[string]job.Dispute{}
	}
	m.disputes[d.ID] = *d
	return nil
}

func (m *Memory) UpdateDispute(_ context.Context, d *job.Dispute) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.disputes[d.ID]; !ok {
		return job.ErrDisputeNotFound
	}
	m.disputes[d.ID] = *d
	return nil
}

func (m *Memory) DisputeByID(_ context.Context, id string) (*job.Dispute, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	d, ok := m.disputes[id]
	if !ok {
		return nil, job.ErrDisputeNotFound
	}
	return &d, nil
}

func (m *Memory) DisputeByDeal(_ context.Context, dealID string) (*job.Dispute, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var found *job.Dispute
	for _, d := range m.disputes {
		if d.DealID != dealID {
			continue
		}
		copy := d
		if found == nil || copy.CreatedAt.After(found.CreatedAt) {
			found = &copy
		}
	}
	if found == nil {
		return nil, job.ErrDisputeNotFound
	}
	return found, nil
}

func (m *Memory) OpenDisputes(_ context.Context, limit int) ([]job.Dispute, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.Dispute{}
	for _, d := range m.disputes {
		if d.Status != job.DisputeOpen {
			continue
		}
		copy := d
		if j, ok := m.jobs[d.JobID]; ok {
			copy.JobTitle = j.Title
		}
		out = append(out, copy)
	}
	sort.Slice(out, func(i, k int) bool { return out[i].CreatedAt.Before(out[k].CreatedAt) })
	if limit > 0 && limit < len(out) {
		out = out[:limit]
	}
	return out, nil
}
