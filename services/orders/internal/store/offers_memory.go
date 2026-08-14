package store

import (
	"context"
	"sort"

	"traktor/orders/internal/job"
)

// Отклики в памяти — та же семантика, что и в Postgres: один активный отклик
// на исполнителя и пересчёт счётчика по фактическим записям.

func (m *Memory) CreateOffer(_ context.Context, o *job.Offer) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, ex := range m.offers {
		if ex.JobID == o.JobID && ex.OwnerID == o.OwnerID && isCountable(ex.Status) {
			return job.ErrOfferExists
		}
	}
	if m.offers == nil {
		m.offers = map[string]job.Offer{}
	}
	m.offers[o.ID] = *o
	m.recount(o.JobID)
	return nil
}

func (m *Memory) UpdateOffer(_ context.Context, o *job.Offer) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.offers[o.ID]; !ok {
		return job.ErrOfferNotFound
	}
	m.offers[o.ID] = *o
	m.recount(o.JobID)
	return nil
}

func (m *Memory) OfferByID(_ context.Context, id string) (*job.Offer, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	o, ok := m.offers[id]
	if !ok {
		return nil, job.ErrOfferNotFound
	}
	return &o, nil
}

func (m *Memory) OffersByJob(_ context.Context, jobID string) ([]job.Offer, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.Offer{}
	for _, o := range m.offers {
		if o.JobID == jobID {
			out = append(out, o)
		}
	}
	sort.SliceStable(out, func(i, k int) bool {
		ai, ak := isCountable(out[i].Status), isCountable(out[k].Status)
		if ai != ak {
			return ai
		}
		return out[i].CreatedAt.After(out[k].CreatedAt)
	})
	return out, nil
}

func (m *Memory) OffersByOwner(_ context.Context, ownerID string, limit, offset int) ([]job.Offer, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.Offer{}
	for _, o := range m.offers {
		if o.OwnerID == ownerID {
			out = append(out, o)
		}
	}
	sort.Slice(out, func(i, k int) bool { return out[i].CreatedAt.After(out[k].CreatedAt) })
	if offset >= len(out) {
		return []job.Offer{}, nil
	}
	out = out[offset:]
	if limit > 0 && limit < len(out) {
		out = out[:limit]
	}
	return out, nil
}

func (m *Memory) MyOfferForJob(_ context.Context, jobID, ownerID string) (*job.Offer, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var found *job.Offer
	for _, o := range m.offers {
		if o.JobID == jobID && o.OwnerID == ownerID {
			if found == nil || o.CreatedAt.After(found.CreatedAt) {
				copy := o
				found = &copy
			}
		}
	}
	if found == nil {
		return nil, job.ErrOfferNotFound
	}
	return found, nil
}

// recount вызывается под уже взятой блокировкой.
func (m *Memory) recount(jobID string) {
	j, ok := m.jobs[jobID]
	if !ok {
		return
	}
	n := 0
	for _, o := range m.offers {
		if o.JobID == jobID && isCountable(o.Status) {
			n++
		}
	}
	j.OffersCount = n
	m.jobs[jobID] = j
}

func isCountable(s job.OfferStatus) bool {
	return s == job.OfferActive || s == job.OfferCounterOffered || s == job.OfferAccepted
}
