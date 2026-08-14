package store

import (
	"context"
	"sync"
)

// Memory — потокобезопасная in-memory реализация Store для dev/тестов.
type Memory struct {
	mu      sync.Mutex
	otps    map[string]OTP
	users   map[string]User // по phone
	refresh map[string]Refresh
}

func NewMemory() *Memory {
	return &Memory{
		otps:    map[string]OTP{},
		users:   map[string]User{},
		refresh: map[string]Refresh{},
	}
}

func (m *Memory) UpsertOTP(_ context.Context, o OTP) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.otps[o.Phone] = o
	return nil
}

func (m *Memory) GetOTP(_ context.Context, phone string) (*OTP, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	o, ok := m.otps[phone]
	if !ok {
		return nil, ErrNotFound
	}
	return &o, nil
}

func (m *Memory) DeleteOTP(_ context.Context, phone string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.otps, phone)
	return nil
}

func (m *Memory) GetUserByPhone(_ context.Context, phone string) (*User, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	u, ok := m.users[phone]
	if !ok {
		return nil, ErrNotFound
	}
	return &u, nil
}

func (m *Memory) CreateUser(_ context.Context, u User) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.users[u.Phone] = u
	return nil
}

func (m *Memory) UpdateUser(_ context.Context, u User) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.users[u.Phone] = u
	return nil
}

func (m *Memory) SaveRefresh(_ context.Context, r Refresh) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.refresh[r.TokenHash] = r
	return nil
}

func (m *Memory) GetRefresh(_ context.Context, tokenHash string) (*Refresh, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.refresh[tokenHash]
	if !ok {
		return nil, ErrNotFound
	}
	return &r, nil
}

func (m *Memory) MarkRefreshUsed(_ context.Context, tokenHash string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.refresh[tokenHash]
	if !ok {
		return ErrNotFound
	}
	r.Used = true
	m.refresh[tokenHash] = r
	return nil
}

func (m *Memory) RevokeFamily(_ context.Context, familyID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	for k, r := range m.refresh {
		if r.FamilyID == familyID {
			r.Revoked = true
			m.refresh[k] = r
		}
	}
	return nil
}
