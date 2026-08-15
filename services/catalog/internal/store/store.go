// Package store — хранилище справочника.
package store

import (
	"context"

	"traktor/catalog/internal/catalog"
)

// Store — доступ к категориям. Реализации: Postgres (боевая) и Memory (dev и
// тесты без базы).
type Store interface {
	// List возвращает плоский список категорий, отсортированный так, как их
	// нужно показывать: по уровню и sort_order. Пустой kind — обе ветви.
	List(ctx context.Context, kind catalog.Kind) ([]catalog.Category, error)
	// ByID возвращает одну категорию; ошибка ErrNotFound, если её нет.
	ByID(ctx context.Context, id string) (catalog.Category, error)

	// Техника исполнителя (ТЗ §2.5).
	CreateEquipment(ctx context.Context, e *catalog.Equipment) error
	UpdateEquipment(ctx context.Context, e *catalog.Equipment) error
	EquipmentByID(ctx context.Context, id string) (*catalog.Equipment, error)
	// EquipmentByOwner — список «Моя техника», свежие сверху.
	EquipmentByOwner(ctx context.Context, ownerID string) ([]catalog.Equipment, error)
	// PublicEquipment — техника человека для его карточки: только та, что
	// участвует в работе (проверенная или опубликованная без документов).
	PublicEquipment(ctx context.Context, ownerID string) ([]catalog.Equipment, error)
}
