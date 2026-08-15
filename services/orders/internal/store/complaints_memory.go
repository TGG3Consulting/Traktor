package store

import (
	"context"
	"sort"
	"time"

	"traktor/orders/internal/job"
)

// Жалобы в памяти: та же семантика, что в Postgres — один открытый повод
// от человека на объект.

func (m *Memory) CreateComplaint(_ context.Context, c *job.Complaint) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, ex := range m.complaints {
		if ex.AuthorID == c.AuthorID && ex.TargetKind == c.TargetKind &&
			ex.TargetID == c.TargetID && ex.Status == job.ComplaintOpen {
			return job.ErrComplaintExists
		}
	}
	if m.complaints == nil {
		m.complaints = map[string]job.Complaint{}
	}
	m.complaints[c.ID] = *c
	return nil
}

func (m *Memory) UpdateComplaint(_ context.Context, c *job.Complaint) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.complaints[c.ID]; !ok {
		return job.ErrComplaintNotFound
	}
	m.complaints[c.ID] = *c
	return nil
}

func (m *Memory) ComplaintByID(_ context.Context, id string) (*job.Complaint, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	c, ok := m.complaints[id]
	if !ok {
		return nil, job.ErrComplaintNotFound
	}
	return &c, nil
}

func (m *Memory) OpenComplaints(_ context.Context, limit int) ([]job.Complaint, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Сколько всего жалоб на объект: одна может быть сведением счётов, пять —
	// уже сигнал.
	same := map[string]int{}
	for _, c := range m.complaints {
		same[c.TargetKind+":"+c.TargetID]++
	}

	out := []job.Complaint{}
	for _, c := range m.complaints {
		if c.Status != job.ComplaintOpen {
			continue
		}
		row := c
		row.SameTarget = same[c.TargetKind+":"+c.TargetID]
		if c.TargetKind == job.TargetJob {
			if j, ok := m.jobs[c.TargetID]; ok {
				row.TargetTitle = j.Title
			}
		}
		out = append(out, row)
	}
	sort.Slice(out, func(i, k int) bool { return out[i].CreatedAt.Before(out[k].CreatedAt) })
	if limit > 0 && limit < len(out) {
		out = out[:limit]
	}
	return out, nil
}

func (m *Memory) PlatformStats(_ context.Context, from, to time.Time) (job.PlatformStats, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	s := job.PlatformStats{From: from, To: to}
	within := func(t time.Time) bool { return !t.Before(from) && !t.After(to) }

	for _, j := range m.jobs {
		if j.Status != job.StatusDraft && within(j.CreatedAt) {
			s.Jobs++
		}
	}
	for _, d := range m.deals {
		if within(d.CreatedAt) {
			s.Deals++
		}
		if d.Status == job.DealCompleted && d.ClosedAt != nil && within(*d.ClosedAt) {
			s.Completed++
			s.GMV += d.Price
		}
	}
	for _, d := range m.disputes {
		if d.Status == job.DisputeOpen {
			s.OpenDisputes++
		}
	}
	for _, c := range m.complaints {
		if c.Status == job.ComplaintOpen {
			s.OpenComplaints++
		}
	}
	return s, nil
}
