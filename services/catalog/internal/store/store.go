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

	// ── правка справочника у модерации (ТЗ §4.1, п.5) ────────────────────────
	// ListAll — то же, что List, но вместе со скрытыми: модератор должен
	// видеть и то, что убрал, иначе вернуть категорию невозможно.
	ListAll(ctx context.Context, kind catalog.Kind) ([]catalog.Category, error)
	// AnyByID — категория независимо от того, скрыта она или нет.
	AnyByID(ctx context.Context, id string) (catalog.Category, error)
	CreateCategory(ctx context.Context, c catalog.Category) error
	UpdateCategory(ctx context.Context, c catalog.Category) error
	// SetCategoryActive — скрыть или вернуть. Удаления нет: на категорию
	// ссылаются уже созданные задания и техника.
	SetCategoryActive(ctx context.Context, id string, active bool) error
	// HasChildren — есть ли вложенные категории (в том числе скрытые).
	HasChildren(ctx context.Context, id string) (bool, error)
	// SlugTaken — занят ли ключ кем-то, кроме указанной категории.
	SlugTaken(ctx context.Context, slug, exceptID string) (bool, error)

	// Техника исполнителя (ТЗ §2.5).
	CreateEquipment(ctx context.Context, e *catalog.Equipment) error
	UpdateEquipment(ctx context.Context, e *catalog.Equipment) error
	EquipmentByID(ctx context.Context, id string) (*catalog.Equipment, error)
	// EquipmentByOwner — список «Моя техника», свежие сверху.
	EquipmentByOwner(ctx context.Context, ownerID string) ([]catalog.Equipment, error)
	// PublicEquipment — техника человека для его карточки: только та, что
	// участвует в работе (проверенная или опубликованная без документов).
	PublicEquipment(ctx context.Context, ownerID string) ([]catalog.Equipment, error)
	// PendingEquipment — очередь проверки, старые сверху: обещали сутки.
	PendingEquipment(ctx context.Context, limit int) ([]catalog.Equipment, error)
}
