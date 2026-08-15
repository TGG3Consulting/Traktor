package store

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"

	"traktor/catalog/internal/catalog"
)

const equipmentColumns = `
  id, owner_id, category_id, brand, model, year, specs,
  price_hour, price_shift, price_day, min_hours, delivery,
  crew_size, crew_price, photos, docs, status, reject_reason,
  draft_step, wins, created_at, updated_at`

func (p *Postgres) CreateEquipment(ctx context.Context, e *catalog.Equipment) error {
	specs, err := json.Marshal(e.Specs)
	if err != nil {
		return fmt.Errorf("catalog: характеристики техники: %w", err)
	}
	const q = `
	INSERT INTO catalog.equipment
	  (id, owner_id, category_id, brand, model, year, specs,
	   price_hour, price_shift, price_day, min_hours, delivery,
	   crew_size, crew_price, photos, docs, status, draft_step, created_at, updated_at)
	VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20)`
	_, err = p.pool.Exec(ctx, q, e.ID, e.OwnerID, nullable(e.CategoryID), e.Brand, e.Model, e.Year,
		string(specs), e.PriceHour, e.PriceShift, e.PriceDay, e.MinHours, e.Delivery,
		e.CrewSize, e.CrewPrice, e.Photos, e.Docs, string(e.Status), e.DraftStep,
		e.CreatedAt, e.UpdatedAt)
	if err != nil {
		return fmt.Errorf("catalog: создание техники: %w", err)
	}
	return nil
}

func (p *Postgres) UpdateEquipment(ctx context.Context, e *catalog.Equipment) error {
	specs, err := json.Marshal(e.Specs)
	if err != nil {
		return fmt.Errorf("catalog: характеристики техники: %w", err)
	}
	const q = `
	UPDATE catalog.equipment SET
	  category_id=$2, brand=$3, model=$4, year=$5, specs=$6::jsonb,
	  price_hour=$7, price_shift=$8, price_day=$9, min_hours=$10, delivery=$11,
	  crew_size=$12, crew_price=$13, photos=$14, docs=$15, status=$16,
	  reject_reason=$17, draft_step=$18, updated_at=$19
	WHERE id=$1`
	tag, err := p.pool.Exec(ctx, q, e.ID, nullable(e.CategoryID), e.Brand, e.Model, e.Year, string(specs),
		e.PriceHour, e.PriceShift, e.PriceDay, e.MinHours, e.Delivery,
		e.CrewSize, e.CrewPrice, e.Photos, e.Docs, string(e.Status), e.RejectReason,
		e.DraftStep, e.UpdatedAt)
	if err != nil {
		return fmt.Errorf("catalog: обновление техники: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return catalog.ErrEquipmentNotFound
	}
	return nil
}

func (p *Postgres) EquipmentByID(ctx context.Context, id string) (*catalog.Equipment, error) {
	rows, err := p.pool.Query(ctx, `SELECT`+equipmentColumns+` FROM catalog.equipment WHERE id=$1`, id)
	if err != nil {
		return nil, fmt.Errorf("catalog: выборка техники: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, catalog.ErrEquipmentNotFound
	}
	return scanEquipment(rows)
}

// EquipmentByOwner — список «Моя техника». Снятые машины не показываем:
// человек их уже убрал, а история хранится в базе.
func (p *Postgres) EquipmentByOwner(ctx context.Context, ownerID string) ([]catalog.Equipment, error) {
	q := `SELECT` + equipmentColumns + `
	        FROM catalog.equipment
	       WHERE owner_id=$1 AND status <> 'archived'
	    ORDER BY created_at DESC`
	rows, err := p.pool.Query(ctx, q, ownerID)
	if err != nil {
		return nil, fmt.Errorf("catalog: техника владельца: %w", err)
	}
	defer rows.Close()

	out := []catalog.Equipment{}
	for rows.Next() {
		e, err := scanEquipment(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *e)
	}
	return out, rows.Err()
}

// nullable — пустая категория уходит в базу как NULL: пустая строка не
// приводится к uuid и роняла бы создание черновика.
func nullable(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func scanEquipment(rows pgx.Rows) (*catalog.Equipment, error) {
	var e catalog.Equipment
	var status string
	var specs []byte
	var category *string
	if err := rows.Scan(
		&e.ID, &e.OwnerID, &category, &e.Brand, &e.Model, &e.Year, &specs,
		&e.PriceHour, &e.PriceShift, &e.PriceDay, &e.MinHours, &e.Delivery,
		&e.CrewSize, &e.CrewPrice, &e.Photos, &e.Docs, &status, &e.RejectReason,
		&e.DraftStep, &e.Wins, &e.CreatedAt, &e.UpdatedAt,
	); err != nil {
		return nil, fmt.Errorf("catalog: чтение техники: %w", err)
	}
	e.Status = catalog.Status(status)
	if category != nil {
		e.CategoryID = *category
	}
	if len(specs) > 0 {
		_ = json.Unmarshal(specs, &e.Specs)
	}
	return &e, nil
}
