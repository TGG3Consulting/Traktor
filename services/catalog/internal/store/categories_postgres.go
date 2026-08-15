package store

import (
	"context"
	"encoding/json"
	"fmt"

	"traktor/catalog/internal/catalog"
)

// Правка справочника у модерации (ТЗ §4.1, п.5).
//
// Удаления нет: на категорию ссылаются уже созданные задания и техника, а
// сломать историю ради опечатки в названии — плохая сделка. Есть скрытие.

func (p *Postgres) ListAll(ctx context.Context, kind catalog.Kind) ([]catalog.Category, error) {
	q := `SELECT` + selectColumns + `, active
	        FROM catalog.categories
	       WHERE ($1 = '' OR kind = $1)
	    ORDER BY (parent_id IS NOT NULL), sort_order, name_ru`
	rows, err := p.pool.Query(ctx, q, string(kind))
	if err != nil {
		return nil, fmt.Errorf("catalog: выборка категорий: %w", err)
	}
	defer rows.Close()

	out := []catalog.Category{}
	for rows.Next() {
		c, err := scanWithActive(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (p *Postgres) AnyByID(ctx context.Context, id string) (catalog.Category, error) {
	q := `SELECT` + selectColumns + `, active FROM catalog.categories WHERE id = $1`
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
	return scanWithActive(rows)
}

func (p *Postgres) CreateCategory(ctx context.Context, c catalog.Category) error {
	specs, err := json.Marshal(c.SpecTemplate)
	if err != nil {
		return fmt.Errorf("catalog: шаблон характеристик: %w", err)
	}
	const q = `
		INSERT INTO catalog.categories
		  (id, parent_id, kind, slug, name_hy, name_ru, name_en, icon, spec_template,
		   sort_order, active)
		VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8, $9::jsonb, $10, true)`
	_, err = p.pool.Exec(ctx, q, c.ID, c.ParentID, string(c.Kind), c.Slug,
		c.Name.Hy, c.Name.Ru, c.Name.En, c.Icon, specs, c.SortOrder)
	if err != nil {
		return fmt.Errorf("catalog: создание категории: %w", err)
	}
	return nil
}

func (p *Postgres) UpdateCategory(ctx context.Context, c catalog.Category) error {
	specs, err := json.Marshal(c.SpecTemplate)
	if err != nil {
		return fmt.Errorf("catalog: шаблон характеристик: %w", err)
	}
	const q = `
		UPDATE catalog.categories
		   SET parent_id = $2::uuid, name_hy = $3, name_ru = $4, name_en = $5,
		       icon = $6, spec_template = $7::jsonb, sort_order = $8, updated_at = now()
		 WHERE id = $1::uuid`
	tag, err := p.pool.Exec(ctx, q, c.ID, c.ParentID, c.Name.Hy, c.Name.Ru, c.Name.En,
		c.Icon, specs, c.SortOrder)
	if err != nil {
		return fmt.Errorf("catalog: правка категории: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (p *Postgres) SetCategoryActive(ctx context.Context, id string, active bool) error {
	const q = `UPDATE catalog.categories SET active = $2, updated_at = now() WHERE id = $1::uuid`
	tag, err := p.pool.Exec(ctx, q, id, active)
	if err != nil {
		return fmt.Errorf("catalog: видимость категории: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (p *Postgres) HasChildren(ctx context.Context, id string) (bool, error) {
	var n int
	err := p.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM catalog.categories WHERE parent_id = $1::uuid`, id).Scan(&n)
	if err != nil {
		return false, fmt.Errorf("catalog: вложенные категории: %w", err)
	}
	return n > 0, nil
}

func (p *Postgres) SlugTaken(ctx context.Context, slug, exceptID string) (bool, error) {
	var n int
	err := p.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM catalog.categories WHERE slug = $1 AND ($2 = '' OR id <> $2::uuid)`,
		slug, exceptID).Scan(&n)
	if err != nil {
		return false, fmt.Errorf("catalog: проверка ключа: %w", err)
	}
	return n > 0, nil
}
