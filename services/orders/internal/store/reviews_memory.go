package store

import (
	"context"
	"sort"
	"time"

	"traktor/orders/internal/job"
)

// Отзывы в памяти: та же семантика, что в Postgres — одна оценка на человека
// в сделке, наружу уходят только опубликованные.

func (m *Memory) CreateReview(_ context.Context, r *job.Review) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, ex := range m.reviews {
		if ex.DealID == r.DealID && ex.AuthorID == r.AuthorID {
			return job.ErrReviewTwice
		}
	}
	if m.reviews == nil {
		m.reviews = map[string]job.Review{}
	}
	m.reviews[r.ID] = *r
	return nil
}

func (m *Memory) UpdateReview(_ context.Context, r *job.Review) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.reviews[r.ID]; !ok {
		return job.ErrReviewNotFound
	}
	m.reviews[r.ID] = *r
	return nil
}

func (m *Memory) ReviewByID(_ context.Context, id string) (*job.Review, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	r, ok := m.reviews[id]
	if !ok {
		return nil, job.ErrReviewNotFound
	}
	return &r, nil
}

func (m *Memory) ReviewsByDeal(_ context.Context, dealID string) ([]job.Review, error) {
	return m.pickReviews(func(r job.Review) bool { return r.DealID == dealID }, 0, 0, byCreated), nil
}

func (m *Memory) ReviewsAbout(_ context.Context, userID string, limit, offset int) ([]job.Review, error) {
	return m.pickReviews(func(r job.Review) bool {
		return r.TargetID == userID && r.Published()
	}, limit, offset, byCreatedDesc), nil
}

func (m *Memory) ReviewsByAuthor(_ context.Context, userID string, limit, offset int) ([]job.Review, error) {
	return m.pickReviews(func(r job.Review) bool {
		return r.AuthorID == userID
	}, limit, offset, byCreatedDesc), nil
}

func (m *Memory) RatingOf(_ context.Context, userID string, since time.Time) (job.RatingSummary, error) {
	all := m.pickReviews(func(r job.Review) bool {
		return r.TargetID == userID && r.Published() && !r.CreatedAt.Before(since)
	}, 0, 0, byCreated)

	s := job.Rating(all, since.Add(job.RatingWindow))
	s.UserID = userID
	return s, nil
}

func (m *Memory) DueReviews(_ context.Context, before time.Time) ([]job.Review, error) {
	return m.pickReviews(func(r job.Review) bool {
		return !r.Published() && !r.CreatedAt.After(before)
	}, 0, 0, byCreated), nil
}

type reviewOrder func(a, b job.Review) bool

func byCreated(a, b job.Review) bool     { return a.CreatedAt.Before(b.CreatedAt) }
func byCreatedDesc(a, b job.Review) bool { return a.CreatedAt.After(b.CreatedAt) }

func (m *Memory) pickReviews(match func(job.Review) bool, limit, offset int, less reviewOrder) []job.Review {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.Review{}
	for _, r := range m.reviews {
		if match(r) {
			out = append(out, r)
		}
	}
	sort.Slice(out, func(i, k int) bool { return less(out[i], out[k]) })

	if offset >= len(out) {
		return []job.Review{}
	}
	out = out[offset:]
	if limit > 0 && limit < len(out) {
		out = out[:limit]
	}
	return out
}
