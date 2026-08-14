package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"traktor/orders/internal/job"
)

const dealColumns = `
  id, job_id, offer_id, client_id, owner_id, price, currency, status, timeline,
  acceptance_deadline, cancel_reason, cancelled_by, created_at, updated_at, closed_at`

func (p *Postgres) CreateDeal(ctx context.Context, d *job.Deal) error {
	timeline, err := json.Marshal(d.Timeline)
	if err != nil {
		return fmt.Errorf("orders: сериализация таймлайна: %w", err)
	}
	const q = `
	INSERT INTO orders.deals (
	  id, job_id, offer_id, client_id, owner_id, price, currency, status, timeline,
	  acceptance_deadline, created_at, updated_at)
	VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`

	if _, err := p.pool.Exec(ctx, q,
		d.ID, d.JobID, d.OfferID, d.ClientID, d.OwnerID, d.Price, d.Currency,
		string(d.Status), timeline, d.AcceptanceDeadline, d.CreatedAt, d.UpdatedAt); err != nil {
		// На задание — ровно одна сделка: повторное подтверждение не должно
		// создавать вторую.
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return job.ErrDealStep
		}
		return fmt.Errorf("orders: вставка сделки: %w", err)
	}
	return nil
}

func (p *Postgres) UpdateDeal(ctx context.Context, d *job.Deal) error {
	timeline, err := json.Marshal(d.Timeline)
	if err != nil {
		return fmt.Errorf("orders: сериализация таймлайна: %w", err)
	}
	const q = `
	UPDATE orders.deals SET
	  status=$2, timeline=$3, acceptance_deadline=$4, cancel_reason=$5,
	  cancelled_by=$6, updated_at=$7, closed_at=$8
	WHERE id=$1`

	tag, err := p.pool.Exec(ctx, q, d.ID, string(d.Status), timeline,
		d.AcceptanceDeadline, d.CancelReason, d.CancelledBy, d.UpdatedAt, d.ClosedAt)
	if err != nil {
		return fmt.Errorf("orders: обновление сделки: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return job.ErrDealNotFound
	}
	return nil
}

func (p *Postgres) DealByID(ctx context.Context, id string) (*job.Deal, error) {
	rows, err := p.pool.Query(ctx, `SELECT`+dealColumns+` FROM orders.deals WHERE id=$1`, id)
	if err != nil {
		return nil, fmt.Errorf("orders: выборка сделки: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrDealNotFound
	}
	return scanDeal(rows)
}

func (p *Postgres) DealByJob(ctx context.Context, jobID string) (*job.Deal, error) {
	rows, err := p.pool.Query(ctx, `SELECT`+dealColumns+` FROM orders.deals WHERE job_id=$1`, jobID)
	if err != nil {
		return nil, fmt.Errorf("orders: сделка по заданию: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrDealNotFound
	}
	return scanDeal(rows)
}

func (p *Postgres) DealsByUser(ctx context.Context, userID string, limit, offset int) ([]job.Deal, error) {
	q := `SELECT` + dealColumns + `
	      FROM orders.deals WHERE client_id=$1 OR owner_id=$1
	      ORDER BY updated_at DESC LIMIT $2 OFFSET $3`
	rows, err := p.pool.Query(ctx, q, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("orders: сделки пользователя: %w", err)
	}
	defer rows.Close()

	out := []job.Deal{}
	for rows.Next() {
		d, err := scanDeal(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *d)
	}
	return out, rows.Err()
}

func scanDeal(rows pgx.Rows) (*job.Deal, error) {
	var (
		d        job.Deal
		timeline []byte
	)
	if err := rows.Scan(
		&d.ID, &d.JobID, &d.OfferID, &d.ClientID, &d.OwnerID, &d.Price, &d.Currency,
		&d.Status, &timeline, &d.AcceptanceDeadline, &d.CancelReason, &d.CancelledBy,
		&d.CreatedAt, &d.UpdatedAt, &d.ClosedAt,
	); err != nil {
		return nil, fmt.Errorf("orders: чтение сделки: %w", err)
	}
	if len(timeline) > 0 {
		if err := json.Unmarshal(timeline, &d.Timeline); err != nil {
			return nil, fmt.Errorf("orders: разбор таймлайна: %w", err)
		}
	}
	if d.Timeline == nil {
		d.Timeline = []job.TimelineEvent{}
	}
	return &d, nil
}
