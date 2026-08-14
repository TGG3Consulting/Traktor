package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"traktor/catalog/internal/catalog"
)

// ErrNotFound — категории с таким идентификатором нет.
var ErrNotFound = errors.New("catalog: категория не найдена")

// Postgres — хранилище справочника на pgx.
type Postgres struct{ pool *pgxpool.Pool }

func NewPostgres(pool *pgxpool.Pool) *Postgres { return &Postgres{pool: pool} }

const selectColumns = `
  id, parent_id, kind, slug, name_hy, name_ru, name_en, icon, spec_template, sort_order`

func (p *Postgres) List(ctx context.Context, kind catalog.Kind) ([]catalog.Category, error) {
	// Порядок: сначала корни, потом их потомки — так дерево собирается за один
	// проход, а клиент получает предсказуемую последовательность.
	q := `SELECT` + selectColumns + `
	      FROM catalog.categories
	      WHERE active AND ($1 = '' OR kind = $1)
	      ORDER BY (parent_id IS NOT NULL), sort_order, name_ru`

	rows, err := p.pool.Query(ctx, q, string(kind))
	if err != nil {
		return nil, fmt.Errorf("catalog: выборка категорий: %w", err)
	}
	defer rows.Close()

	var out []catalog.Category
	for rows.Next() {
		c, err := scan(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (p *Postgres) ByID(ctx context.Context, id string) (catalog.Category, error) {
	q := `SELECT` + selectColumns + ` FROM catalog.categories WHERE id = $1 AND active`
	rows, err := p.pool.Query(ctx, q, id)
	if err != nil {
		return catalog.Category{}, fmt.Errorf("catalog: выборка категории: %w", err)
	}
	defer rows.Close()

	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return catalog.Category{}, err
		}
		return catalog.Category{}, ErrNotFound
	}
	return scan(rows)
}

func scan(rows pgx.Rows) (catalog.Category, error) {
	var (
		c     catalog.Category
		specs []byte
	)
	if err := rows.Scan(&c.ID, &c.ParentID, &c.Kind, &c.Slug,
		&c.Name.Hy, &c.Name.Ru, &c.Name.En, &c.Icon, &specs, &c.SortOrder); err != nil {
		return catalog.Category{}, fmt.Errorf("catalog: чтение строки: %w", err)
	}
	if len(specs) > 0 {
		if err := json.Unmarshal(specs, &c.SpecTemplate); err != nil {
			return catalog.Category{}, fmt.Errorf("catalog: разбор spec_template %s: %w", c.Slug, err)
		}
	}
	if c.SpecTemplate == nil {
		c.SpecTemplate = []catalog.SpecField{}
	}
	return c, nil
}
