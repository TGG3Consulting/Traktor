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
}
