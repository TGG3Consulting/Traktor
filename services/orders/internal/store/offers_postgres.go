package store

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"traktor/orders/internal/job"
)

const offerColumns = `
  id, job_id, owner_id, kind, price, currency, comment, eta, unit_id,
  status, decline_reason, client_counter_price, client_counter_at,
  created_at, updated_at`

func (p *Postgres) CreateOffer(ctx context.Context, o *job.Offer) error {
	const q = `
	INSERT INTO orders.offers (
	  id, job_id, owner_id, kind, price, currency, comment, eta, unit_id,
	  status, created_at, updated_at)
	VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`

	_, err := p.pool.Exec(ctx, q,
		o.ID, o.JobID, o.OwnerID, string(o.Kind), o.Price, o.Currency, o.Comment, o.ETA,
		o.UnitID, string(o.Status), o.CreatedAt, o.UpdatedAt)
	if err != nil {
		// Уникальный индекс не даёт откликнуться дважды — переводим ошибку
		// базы в понятную доменную, иначе клиент увидит «внутренняя ошибка».
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return job.ErrOfferExists
		}
		return fmt.Errorf("orders: вставка отклика: %w", err)
	}
	return p.recountOffers(ctx, o.JobID)
}

func (p *Postgres) UpdateOffer(ctx context.Context, o *job.Offer) error {
	const q = `
	UPDATE orders.offers SET
	  kind=$2, price=$3, comment=$4, eta=$5, unit_id=$6, status=$7,
	  decline_reason=$8, client_counter_price=$9, client_counter_at=$10, updated_at=$11
	WHERE id=$1`

	tag, err := p.pool.Exec(ctx, q,
		o.ID, string(o.Kind), o.Price, o.Comment, o.ETA, o.UnitID, string(o.Status),
		o.DeclineReason, o.ClientCounterPrice, o.ClientCounterAt, o.UpdatedAt)
	if err != nil {
		return fmt.Errorf("orders: обновление отклика: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return job.ErrOfferNotFound
	}
	return p.recountOffers(ctx, o.JobID)
}

func (p *Postgres) OfferByID(ctx context.Context, id string) (*job.Offer, error) {
	rows, err := p.pool.Query(ctx, `SELECT`+offerColumns+` FROM orders.offers WHERE id=$1`, id)
	if err != nil {
		return nil, fmt.Errorf("orders: выборка отклика: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrOfferNotFound
	}
	return scanOffer(rows)
}

func (p *Postgres) OffersByJob(ctx context.Context, jobID string) ([]job.Offer, error) {
	// Порядок: активные и принятые сверху, дальше по времени. Отклонённые
	// остаются в списке — заказчик должен видеть, кому уже отказал.
	q := `SELECT` + offerColumns + `
	      FROM orders.offers WHERE job_id=$1
	      ORDER BY (status IN ('active','counter_offered','accepted')) DESC, created_at DESC`
	rows, err := p.pool.Query(ctx, q, jobID)
	if err != nil {
		return nil, fmt.Errorf("orders: отклики задания: %w", err)
	}
	defer rows.Close()
	return collectOffers(rows)
}

func (p *Postgres) OffersByOwner(ctx context.Context, ownerID string, limit, offset int) ([]job.Offer, error) {
	q := `SELECT` + offerColumns + `
	      FROM orders.offers WHERE owner_id=$1
	      ORDER BY created_at DESC LIMIT $2 OFFSET $3`
	rows, err := p.pool.Query(ctx, q, ownerID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("orders: отклики исполнителя: %w", err)
	}
	defer rows.Close()
	return collectOffers(rows)
}

func (p *Postgres) MyOfferForJob(ctx context.Context, jobID, ownerID string) (*job.Offer, error) {
	q := `SELECT` + offerColumns + `
	      FROM orders.offers WHERE job_id=$1 AND owner_id=$2
	      ORDER BY created_at DESC LIMIT 1`
	rows, err := p.pool.Query(ctx, q, jobID, ownerID)
	if err != nil {
		return nil, fmt.Errorf("orders: мой отклик: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrOfferNotFound
	}
	return scanOffer(rows)
}

// recountOffers держит счётчик в карточке задания честным: он считается по
// самим откликам, а не увеличивается на единицу при каждой операции — иначе
// после отзыва или отказа цифра расходится с реальностью.
func (p *Postgres) recountOffers(ctx context.Context, jobID string) error {
	const q = `
	UPDATE orders.jobs SET offers_count = (
	  SELECT count(*) FROM orders.offers
	  WHERE job_id = $1 AND status IN ('active','counter_offered','accepted')
	) WHERE id = $1`
	if _, err := p.pool.Exec(ctx, q, jobID); err != nil {
		return fmt.Errorf("orders: пересчёт откликов: %w", err)
	}
	return nil
}

func collectOffers(rows pgx.Rows) ([]job.Offer, error) {
	out := []job.Offer{}
	for rows.Next() {
		o, err := scanOffer(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *o)
	}
	return out, rows.Err()
}

func scanOffer(rows pgx.Rows) (*job.Offer, error) {
	var o job.Offer
	if err := rows.Scan(
		&o.ID, &o.JobID, &o.OwnerID, &o.Kind, &o.Price, &o.Currency, &o.Comment, &o.ETA,
		&o.UnitID, &o.Status, &o.DeclineReason, &o.ClientCounterPrice, &o.ClientCounterAt,
		&o.CreatedAt, &o.UpdatedAt,
	); err != nil {
		return nil, fmt.Errorf("orders: чтение отклика: %w", err)
	}
	return &o, nil
}
