package store

import (
	"context"
	"sort"
	"sync"
)

// Memory — потокобезопасная in-memory реализация Store для dev/тестов.
type Memory struct {
	mu      sync.Mutex
	devices map[string]Device       // по Token
	feed    map[string]Notification // центр уведомлений, по ID
}

func NewMemory() *Memory {
	return &Memory{devices: map[string]Device{}, feed: map[string]Notification{}}
}

func (m *Memory) UpsertDevice(_ context.Context, d Device) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	// Сохраняем CreatedAt при повторной регистрации того же токена.
	if prev, ok := m.devices[d.Token]; ok {
		d.CreatedAt = prev.CreatedAt
	}
	m.devices[d.Token] = d
	return nil
}

func (m *Memory) DeleteDevice(_ context.Context, token string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.devices, token)
	return nil
}

func (m *Memory) ListDevicesByUser(_ context.Context, userID string) ([]Device, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var out []Device
	for _, d := range m.devices {
		if d.UserID == userID {
			out = append(out, d)
		}
	}
	// Стабильный порядок (детерминизм тестов): по токену.
	sort.Slice(out, func(i, j int) bool { return out[i].Token < out[j].Token })
	return out, nil
}
