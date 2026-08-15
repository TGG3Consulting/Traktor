package store

import (
	"context"
	"time"
)

// Настройки уведомлений в памяти.

func (m *Memory) PrefsOf(_ context.Context, userID string) (Prefs, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if p, ok := m.prefs[userID]; ok {
		return p, nil
	}
	return DefaultPrefs(userID), nil
}

func (m *Memory) SavePrefs(_ context.Context, p Prefs, _ time.Time) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.prefs == nil {
		m.prefs = map[string]Prefs{}
	}
	m.prefs[p.UserID] = p
	return nil
}
