package store

import (
	"context"
	"sort"
	"sync"

	"traktor/catalog/internal/catalog"
)

// Memory — справочник в памяти для запуска без базы (dev, тесты). Содержит
// сокращённый набор: полный список живёт в миграции-сиде.
type Memory struct {
	items []catalog.Category

	// Техника исполнителя (ТЗ §2.5) — заводится лениво: справочник нужен
	// всегда, а техника только там, где её создают.
	once sync.Once
	eq   *equipmentMem
}

func NewMemory() *Memory {
	work := func(id, slug, ru, hy, en, icon string, order int) catalog.Category {
		return catalog.Category{
			ID: id, Kind: catalog.KindWork, Slug: slug, Icon: icon, SortOrder: order,
			Name:         catalog.Name{Hy: hy, Ru: ru, En: en},
			SpecTemplate: []catalog.SpecField{},
		}
	}
	return &Memory{items: []catalog.Category{
		work("c02b2502-1789-5217-be9f-d5fc04fe1cae", "work-earth", "Копка / земляные",
			"Փորում / հողային աշխատանքներ", "Digging / earthworks", "pickaxe", 10),
		work("53c1323a-bcf6-5f4e-bed4-08e1884f61ac", "work-transport", "Перевозка",
			"Փոխադրում", "Transport", "truck", 20),
		work("2bba63e8-221c-5cf9-a1f1-1df837b8ae8d", "work-crane", "Кран / подъём",
			"Ամբարձիչ / բարձրացում", "Crane / lifting", "crane", 30),
		work("ac1a993d-8d9d-5496-8c26-3d2e80163260", "work-other", "Другое",
			"Այլ", "Other", "wrench", 900),
	}}
}

func (m *Memory) List(_ context.Context, kind catalog.Kind) ([]catalog.Category, error) {
	out := make([]catalog.Category, 0, len(m.items))
	for _, c := range m.items {
		if kind == "" || c.Kind == kind {
			out = append(out, c)
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].SortOrder < out[j].SortOrder })
	return out, nil
}

func (m *Memory) ByID(_ context.Context, id string) (catalog.Category, error) {
	for _, c := range m.items {
		if c.ID == id {
			return c, nil
		}
	}
	return catalog.Category{}, ErrNotFound
}
