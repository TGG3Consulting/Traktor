package store

import (
	"context"
	"sort"

	"traktor/orders/internal/job"
)

// Ставки в памяти: та же семантика, что в Postgres.

func (m *Memory) CreateBid(_ context.Context, b *job.Bid) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, ex := range m.bids {
		if ex.JobID == b.JobID && ex.OwnerID == b.OwnerID && ex.Status == job.BidActive {
			return job.ErrBidNotActive
		}
	}
	if m.bids == nil {
		m.bids = map[string]job.Bid{}
	}
	m.bids[b.ID] = *b
	return nil
}

func (m *Memory) UpdateBid(_ context.Context, b *job.Bid) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.bids[b.ID]; !ok {
		return job.ErrBidNotFound
	}
	m.bids[b.ID] = *b
	return nil
}

func (m *Memory) BidByID(_ context.Context, id string) (*job.Bid, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	b, ok := m.bids[id]
	if !ok {
		return nil, job.ErrBidNotFound
	}
	return &b, nil
}

func (m *Memory) BidsByJob(_ context.Context, jobID string) ([]job.Bid, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.Bid{}
	for _, b := range m.bids {
		if b.JobID == jobID {
			out = append(out, b)
		}
	}
	sort.SliceStable(out, func(i, k int) bool {
		ai, ak := out[i].Status == job.BidActive, out[k].Status == job.BidActive
		if ai != ak {
			return ai
		}
		if out[i].Price != out[k].Price {
			return out[i].Price < out[k].Price
		}
		return out[i].CreatedAt.Before(out[k].CreatedAt)
	})
	return out, nil
}

func (m *Memory) BidsByOwner(_ context.Context, ownerID string, limit, offset int) ([]job.Bid, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.Bid{}
	for _, b := range m.bids {
		if b.OwnerID == ownerID {
			out = append(out, b)
		}
	}
	sort.Slice(out, func(i, k int) bool { return out[i].CreatedAt.After(out[k].CreatedAt) })
	if offset >= len(out) {
		return []job.Bid{}, nil
	}
	out = out[offset:]
	if limit > 0 && limit < len(out) {
		out = out[:limit]
	}
	return out, nil
}

func (m *Memory) BestBid(_ context.Context, jobID string) (*job.Bid, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var best *job.Bid
	for _, b := range m.bids {
		if b.JobID != jobID || b.Status != job.BidActive {
			continue
		}
		if best == nil || b.Price < best.Price ||
			(b.Price == best.Price && b.CreatedAt.Before(best.CreatedAt)) {
			copy := b
			best = &copy
		}
	}
	if best == nil {
		return nil, job.ErrBidNotFound
	}
	return best, nil
}

func (m *Memory) MyBidForJob(_ context.Context, jobID, ownerID string) (*job.Bid, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var found *job.Bid
	for _, b := range m.bids {
		if b.JobID == jobID && b.OwnerID == ownerID {
			if found == nil || b.CreatedAt.After(found.CreatedAt) {
				copy := b
				found = &copy
			}
		}
	}
	if found == nil {
		return nil, job.ErrBidNotFound
	}
	return found, nil
}
