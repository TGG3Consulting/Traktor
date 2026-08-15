package store

import (
	"context"
	"sort"
	"sync"

	"traktor/catalog/internal/catalog"
)

// Техника в памяти: для dev-запуска без базы и для тестов.
type equipmentMem struct {
	mu    sync.RWMutex
	items map[string]catalog.Equipment
}

func (m *Memory) equip() *equipmentMem {
	m.once.Do(func() { m.eq = &equipmentMem{items: map[string]catalog.Equipment{}} })
	return m.eq
}

func (m *Memory) CreateEquipment(_ context.Context, e *catalog.Equipment) error {
	s := m.equip()
	s.mu.Lock()
	defer s.mu.Unlock()
	s.items[e.ID] = *e
	return nil
}

func (m *Memory) UpdateEquipment(_ context.Context, e *catalog.Equipment) error {
	s := m.equip()
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.items[e.ID]; !ok {
		return catalog.ErrEquipmentNotFound
	}
	s.items[e.ID] = *e
	return nil
}

func (m *Memory) PublicEquipment(_ context.Context, ownerID string) ([]catalog.Equipment, error) {
	s := m.equip()
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := []catalog.Equipment{}
	for _, e := range s.items {
		if e.OwnerID == ownerID && e.Active() {
			out = append(out, e)
		}
	}
	sort.Slice(out, func(i, k int) bool { return out[i].CreatedAt.After(out[k].CreatedAt) })
	return out, nil
}

func (m *Memory) EquipmentByID(_ context.Context, id string) (*catalog.Equipment, error) {
	s := m.equip()
	s.mu.RLock()
	defer s.mu.RUnlock()
	e, ok := s.items[id]
	if !ok {
		return nil, catalog.ErrEquipmentNotFound
	}
	return &e, nil
}

func (m *Memory) EquipmentByOwner(_ context.Context, ownerID string) ([]catalog.Equipment, error) {
	s := m.equip()
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := []catalog.Equipment{}
	for _, e := range s.items {
		if e.OwnerID == ownerID && e.Status != catalog.StatusArchived {
			out = append(out, e)
		}
	}
	sort.Slice(out, func(i, k int) bool { return out[i].CreatedAt.After(out[k].CreatedAt) })
	return out, nil
}
