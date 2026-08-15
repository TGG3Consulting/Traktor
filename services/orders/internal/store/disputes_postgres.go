package store

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"traktor/orders/internal/job"
)

const disputeColumns = `
  id, deal_id, job_id, opened_by, client_id, owner_id, reason, photos,
  status, outcome, resolution, resolved_by, resolved_at, created_at`

func (p *Postgres) CreateDispute(ctx context.Context, d *job.Dispute) error {
	const q = `
	INSERT INTO orders.disputes
	  (id, deal_id, job_id, opened_by, client_id, owner_id, reason, photos, status, created_at)
	VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`
	_, err := p.pool.Exec(ctx, q, d.ID, d.DealID, d.JobID, d.OpenedBy, d.ClientID,
		d.OwnerID, d.Reason, d.Photos, string(d.Status), d.CreatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			// На сделку — один открытый спор: второй только запутает разбор.
			return job.ErrDisputeExists
		}
		return fmt.Errorf("orders: открытие спора: %w", err)
	}
	return nil
}

func (p *Postgres) UpdateDispute(ctx context.Context, d *job.Dispute) error {
	const q = `
	UPDATE orders.disputes
	   SET status=$2, outcome=$3, resolution=$4, resolved_by=$5, resolved_at=$6
	 WHERE id=$1`
	tag, err := p.pool.Exec(ctx, q, d.ID, string(d.Status), nullableOutcome(d.Outcome),
		d.Resolution, nullable(d.ResolvedBy), d.ResolvedAt)
	if err != nil {
		return fmt.Errorf("orders: решение спора: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return job.ErrDisputeNotFound
	}
	return nil
}

func (p *Postgres) DisputeByID(ctx context.Context, id string) (*job.Dispute, error) {
	rows, err := p.pool.Query(ctx, `SELECT`+disputeColumns+` FROM orders.disputes WHERE id=$1`, id)
	if err != nil {
		return nil, fmt.Errorf("orders: выборка спора: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrDisputeNotFound
	}
	return scanDispute(rows)
}

// DisputeByDeal — открытый спор по сделке: по нему экран сделки показывает
// плашку «идёт разбор».
func (p *Postgres) DisputeByDeal(ctx context.Context, dealID string) (*job.Dispute, error) {
	q := `SELECT` + disputeColumns + ` FROM orders.disputes
	       WHERE deal_id=$1 ORDER BY created_at DESC LIMIT 1`
	rows, err := p.pool.Query(ctx, q, dealID)
	if err != nil {
		return nil, fmt.Errorf("orders: спор по сделке: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrDisputeNotFound
	}
	return scanDispute(rows)
}

// OpenDisputes — очередь модерации: старые сверху.
func (p *Postgres) OpenDisputes(ctx context.Context, limit int) ([]job.Dispute, error) {
	q := `SELECT` + disputeColumns + `, COALESCE(j.title, '')
	        FROM orders.disputes d
	        JOIN orders.jobs j ON j.id = d.job_id
	       WHERE d.status = 'open'
	    ORDER BY d.created_at
	       LIMIT $1`
	// Колонки спора идут с префиксом d. — перечисляем явно, иначе join ломает
	// список полей.
	q = `SELECT d.id, d.deal_id, d.job_id, d.opened_by, d.client_id, d.owner_id,
	            d.reason, d.photos, d.status, d.outcome, d.resolution,
	            d.resolved_by, d.resolved_at, d.created_at, COALESCE(j.title, '')
	       FROM orders.disputes d
	       JOIN orders.jobs j ON j.id = d.job_id
	      WHERE d.status = 'open'
	   ORDER BY d.created_at
	      LIMIT $1`
	rows, err := p.pool.Query(ctx, q, limit)
	if err != nil {
		return nil, fmt.Errorf("orders: очередь споров: %w", err)
	}
	defer rows.Close()

	out := []job.Dispute{}
	for rows.Next() {
		d, title, err := scanDisputeWithTitle(rows)
		if err != nil {
			return nil, err
		}
		d.JobTitle = title
		out = append(out, *d)
	}
	return out, rows.Err()
}

func scanDispute(rows pgx.Rows) (*job.Dispute, error) {
	var d job.Dispute
	var status string
	var outcome, resolvedBy *string
	if err := rows.Scan(&d.ID, &d.DealID, &d.JobID, &d.OpenedBy, &d.ClientID, &d.OwnerID,
		&d.Reason, &d.Photos, &status, &outcome, &d.Resolution, &resolvedBy,
		&d.ResolvedAt, &d.CreatedAt); err != nil {
		return nil, fmt.Errorf("orders: чтение спора: %w", err)
	}
	d.Status = job.DisputeStatus(status)
	if outcome != nil {
		d.Outcome = job.DisputeOutcome(*outcome)
	}
	if resolvedBy != nil {
		d.ResolvedBy = *resolvedBy
	}
	return &d, nil
}

func scanDisputeWithTitle(rows pgx.Rows) (*job.Dispute, string, error) {
	var d job.Dispute
	var status, title string
	var outcome, resolvedBy *string
	if err := rows.Scan(&d.ID, &d.DealID, &d.JobID, &d.OpenedBy, &d.ClientID, &d.OwnerID,
		&d.Reason, &d.Photos, &status, &outcome, &d.Resolution, &resolvedBy,
		&d.ResolvedAt, &d.CreatedAt, &title); err != nil {
		return nil, "", fmt.Errorf("orders: чтение спора: %w", err)
	}
	d.Status = job.DisputeStatus(status)
	if outcome != nil {
		d.Outcome = job.DisputeOutcome(*outcome)
	}
	if resolvedBy != nil {
		d.ResolvedBy = *resolvedBy
	}
	return &d, title, nil
}

func nullable(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func nullableOutcome(o job.DisputeOutcome) *string {
	if o == "" {
		return nil
	}
	s := string(o)
	return &s
}
