package store

import (
	"context"
	"sort"
	"time"
)

// Лента уведомлений в памяти: та же семантика, что в Postgres.

func (m *Memory) SaveNotification(_ context.Context, n Notification) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.feed == nil {
		m.feed = map[string]Notification{}
	}
	m.feed[n.ID] = n
	return nil
}

func (m *Memory) ListNotifications(_ context.Context, userID string, limit, offset int) ([]Notification, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	out := []Notification{}
	for _, n := range m.feed {
		if n.UserID == userID {
			out = append(out, n)
		}
	}
	sort.Slice(out, func(i, k int) bool { return out[i].CreatedAt.After(out[k].CreatedAt) })

	if offset >= len(out) {
		return []Notification{}, nil
	}
	out = out[offset:]
	if limit > 0 && limit < len(out) {
		out = out[:limit]
	}
	return out, nil
}

func (m *Memory) UnreadCount(_ context.Context, userID string) (int, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	count := 0
	for _, n := range m.feed {
		if n.UserID == userID && n.ReadAt == nil {
			count++
		}
	}
	return count, nil
}

func (m *Memory) MarkNotificationsRead(_ context.Context, userID string, ids []string, at time.Time) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	want := map[string]bool{}
	for _, id := range ids {
		want[id] = true
	}
	for id, n := range m.feed {
		if n.UserID != userID || n.ReadAt != nil {
			continue
		}
		if len(want) > 0 && !want[id] {
			continue
		}
		stamp := at
		n.ReadAt = &stamp
		m.feed[id] = n
	}
	return nil
}

func (m *Memory) DeleteOldNotifications(_ context.Context, before time.Time) (int, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	removed := 0
	for id, n := range m.feed {
		if n.CreatedAt.Before(before) {
			delete(m.feed, id)
			removed++
		}
	}
	return removed, nil
}
