package store

import (
	"context"
	"sort"
	"time"

	"traktor/orders/internal/job"
)

// Календарь занятости в памяти.

func (m *Memory) BusyByDeals(_ context.Context, ownerID string, from, to time.Time) ([]job.BusyDay, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.BusyDay{}
	for _, d := range m.deals {
		if d.OwnerID != ownerID || d.Status == job.DealCancelled {
			continue
		}
		j, ok := m.jobs[d.JobID]
		if !ok {
			continue
		}
		start, end := d.CreatedAt, d.CreatedAt
		if j.DateStart != nil {
			start = *j.DateStart
			end = *j.DateStart
		}
		if j.DateEnd != nil {
			end = *j.DateEnd
		}
		for day := start; !day.After(end); day = day.AddDate(0, 0, 1) {
			if day.Before(from) || day.After(to) {
				continue
			}
			out = append(out, job.BusyDay{
				Day:    day,
				Source: job.BusySourceDeal,
				DealID: d.ID,
				Title:  j.Title,
			})
		}
	}
	sort.Slice(out, func(i, k int) bool { return out[i].Day.Before(out[k].Day) })
	return out, nil
}

func (m *Memory) ManualBusy(_ context.Context, ownerID string, from, to time.Time) ([]job.BusyDay, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.BusyDay{}
	for key, note := range m.busyDays {
		owner, day, ok := splitBusyKey(key)
		if !ok || owner != ownerID || day.Before(from) || day.After(to) {
			continue
		}
		out = append(out, job.BusyDay{Day: day, Source: job.BusySourceManual, Note: note})
	}
	sort.Slice(out, func(i, k int) bool { return out[i].Day.Before(out[k].Day) })
	return out, nil
}

func (m *Memory) SetBusyDay(_ context.Context, ownerID string, day time.Time, note string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.busyDays == nil {
		m.busyDays = map[string]string{}
	}
	m.busyDays[busyKey(ownerID, day)] = note
	return nil
}

func (m *Memory) ClearBusyDay(_ context.Context, ownerID string, day time.Time) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.busyDays, busyKey(ownerID, day))
	return nil
}

func busyKey(ownerID string, day time.Time) string {
	return ownerID + "|" + job.DayKey(day)
}

func splitBusyKey(key string) (string, time.Time, bool) {
	for i := len(key) - 1; i >= 0; i-- {
		if key[i] == '|' {
			day, err := time.Parse("2006-01-02", key[i+1:])
			if err != nil {
				return "", time.Time{}, false
			}
			return key[:i], day, true
		}
	}
	return "", time.Time{}, false
}
