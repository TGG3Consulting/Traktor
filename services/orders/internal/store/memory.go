package store

import (
	"context"
	"math"
	"sort"
	"strings"
	"sync"
	"time"

	"traktor/orders/internal/job"
)

// Memory — хранилище в памяти: запуск без базы (dev) и быстрые тесты
// сервисного слоя. Данные не переживают перезапуск — так и задумано.
type Memory struct {
	mu     sync.RWMutex
	jobs   map[string]job.Job
	offers map[string]job.Offer       // отклики по идентификатору
	deals  map[string]job.Deal        // сделки по идентификатору
	bids   map[string]job.Bid         // ставки аукциона
	views  map[string]map[string]bool // jobID → кто смотрел
	idemp  map[string]string          // ключ идемпотентности → jobID
}

func NewMemory() *Memory {
	return &Memory{
		jobs:   map[string]job.Job{},
		offers: map[string]job.Offer{},
		deals:  map[string]job.Deal{},
		bids:   map[string]job.Bid{},
		views:  map[string]map[string]bool{},
		idemp:  map[string]string{},
	}
}

func (m *Memory) Create(_ context.Context, j *job.Job) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.jobs[j.ID] = *j
	return nil
}

func (m *Memory) Update(_ context.Context, j *job.Job) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.jobs[j.ID]; !ok {
		return job.ErrNotFound
	}
	m.jobs[j.ID] = *j
	return nil
}

func (m *Memory) ByID(_ context.Context, id string) (*job.Job, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	j, ok := m.jobs[id]
	if !ok {
		return nil, job.ErrNotFound
	}
	return &j, nil
}

func (m *Memory) ListByClient(_ context.Context, clientID string, limit, offset int) ([]job.Job, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.Job{}
	for _, j := range m.jobs {
		if j.ClientID == clientID {
			out = append(out, j)
		}
	}
	sort.Slice(out, func(i, k int) bool { return out[i].UpdatedAt.After(out[k].UpdatedAt) })
	return page(out, limit, offset), nil
}

func (m *Memory) Feed(_ context.Context, f Filter) ([]job.Job, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.Job{}
	for _, j := range m.jobs {
		if !job.IsOpen(j.Status) {
			continue
		}
		if f.Mode != "" && j.Mode != f.Mode {
			continue
		}
		if len(f.CategoryIDs) > 0 && !matchCategory(j.CategoryID, f.CategoryIDs) {
			continue
		}
		if q := strings.ToLower(strings.TrimSpace(f.Query)); q != "" {
			if !strings.Contains(strings.ToLower(j.Title), q) &&
				!strings.Contains(strings.ToLower(j.Description), q) {
				continue
			}
		}
		if f.Lat != nil && f.Lng != nil && j.Geo != nil {
			d := distanceM(*f.Lat, *f.Lng, j.Geo.Lat, j.Geo.Lng)
			if f.RadiusM != nil && d > *f.RadiusM {
				continue
			}
			dist := d
			j.DistanceM = &dist
		} else if f.RadiusM != nil {
			// Радиус задан, а координат нет — задание в такой ленте не место.
			continue
		}
		out = append(out, j)
	}

	sort.SliceStable(out, func(i, k int) bool {
		switch f.Sort {
		case SortNear:
			if out[i].DistanceM == nil || out[k].DistanceM == nil {
				return out[k].DistanceM == nil && out[i].DistanceM != nil
			}
			return *out[i].DistanceM < *out[k].DistanceM
		case SortPrice:
			return amount(out[i]) > amount(out[k])
		case SortEnding:
			ei, ek := endsAt(out[i]), endsAt(out[k])
			if ei == nil || ek == nil {
				return ek == nil && ei != nil
			}
			return ei.Before(*ek)
		default:
			return out[i].CreatedAt.After(out[k].CreatedAt)
		}
	})
	return page(out, f.Limit, f.Offset), nil
}

func (m *Memory) AddView(_ context.Context, jobID, viewerID string) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	j, ok := m.jobs[jobID]
	if !ok {
		return false, job.ErrNotFound
	}
	if m.views[jobID] == nil {
		m.views[jobID] = map[string]bool{}
	}
	if m.views[jobID][viewerID] {
		return false, nil
	}
	m.views[jobID][viewerID] = true
	j.ViewsCount++
	m.jobs[jobID] = j
	return true, nil
}

func (m *Memory) FindIdempotent(_ context.Context, key, userID, endpoint string) (string, bool, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	id, ok := m.idemp[idempKey(key, userID, endpoint)]
	return id, ok, nil
}

func (m *Memory) SaveIdempotent(_ context.Context, key, userID, endpoint, jobID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.idemp[idempKey(key, userID, endpoint)] = jobID
	return nil
}

func idempKey(key, userID, endpoint string) string { return key + "|" + userID + "|" + endpoint }

func matchCategory(id *string, list []string) bool {
	if id == nil {
		return false
	}
	for _, c := range list {
		if c == *id {
			return true
		}
	}
	return false
}

func amount(j job.Job) int64 {
	if j.BudgetAmount == nil {
		return 0
	}
	return *j.BudgetAmount
}

func endsAt(j job.Job) *time.Time {
	if j.Auction == nil {
		return nil
	}
	return j.Auction.EndsAt
}

func page(items []job.Job, limit, offset int) []job.Job {
	if offset >= len(items) {
		return []job.Job{}
	}
	items = items[offset:]
	if limit > 0 && limit < len(items) {
		items = items[:limit]
	}
	return items
}

// distanceM — расстояние по сфере (формула гаверсинуса) в метрах. В боевом
// хранилище то же самое считает PostGIS; здесь нужна лишь та же семантика для
// тестов и dev-режима.
func distanceM(lat1, lng1, lat2, lng2 float64) float64 {
	const earthR = 6371000.0
	rad := math.Pi / 180
	dLat := (lat2 - lat1) * rad
	dLng := (lng2 - lng1) * rad
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*rad)*math.Cos(lat2*rad)*math.Sin(dLng/2)*math.Sin(dLng/2)
	return 2 * earthR * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}

// DueJobs — то же, что в Postgres: что пора закрыть по времени.
func (m *Memory) DueJobs(_ context.Context, now time.Time) ([]job.Job, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.Job{}
	for _, j := range m.jobs {
		switch j.Status {
		case job.StatusBidding:
			if j.Auction != nil && j.Auction.EndsAt != nil && !j.Auction.EndsAt.After(now) {
				out = append(out, j)
			}
		case job.StatusDeciding:
			if j.DecisionDeadline != nil && !j.DecisionDeadline.After(now) {
				out = append(out, j)
			}
		case job.StatusWorkDone:
			for _, d := range m.deals {
				if d.JobID == j.ID && d.Status == job.DealWorkDone &&
					d.AcceptanceDeadline != nil && !d.AcceptanceDeadline.After(now) {
					out = append(out, j)
					break
				}
			}
		}
	}
	sort.Slice(out, func(i, k int) bool { return out[i].UpdatedAt.Before(out[k].UpdatedAt) })
	return out, nil
}
