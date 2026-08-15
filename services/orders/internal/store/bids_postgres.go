package store

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"traktor/orders/internal/job"
)

const bidColumns = `
  id, job_id, owner_id, unit_id, price, currency, comment, status, score,
  created_at, updated_at`

func (p *Postgres) CreateBid(ctx context.Context, b *job.Bid) error {
	const q = `
	INSERT INTO orders.bids (id, job_id, owner_id, unit_id, price, currency, comment,
	  status, created_at, updated_at)
	VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`

	if _, err := p.pool.Exec(ctx, q, b.ID, b.JobID, b.OwnerID, b.UnitID, b.Price,
		b.Currency, b.Comment, string(b.Status), b.CreatedAt, b.UpdatedAt); err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			// Уникальный индекс на активную ставку: у исполнителя в торге одна
			// действующая цена, новая заменяет старую (это делает сервис).
			return job.ErrBidNotActive
		}
		return fmt.Errorf("orders: вставка ставки: %w", err)
	}
	return nil
}

func (p *Postgres) UpdateBid(ctx context.Context, b *job.Bid) error {
	const q = `
	UPDATE orders.bids SET price=$2, comment=$3, unit_id=$4, status=$5, score=$6, updated_at=$7
	WHERE id=$1`
	tag, err := p.pool.Exec(ctx, q, b.ID, b.Price, b.Comment, b.UnitID,
		string(b.Status), b.Score, b.UpdatedAt)
	if err != nil {
		return fmt.Errorf("orders: обновление ставки: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return job.ErrBidNotFound
	}
	return nil
}

func (p *Postgres) BidByID(ctx context.Context, id string) (*job.Bid, error) {
	rows, err := p.pool.Query(ctx, `SELECT`+bidColumns+` FROM orders.bids WHERE id=$1`, id)
	if err != nil {
		return nil, fmt.Errorf("orders: выборка ставки: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrBidNotFound
	}
	return scanBid(rows)
}

// BidsByJob — лента торга: сначала действующие по возрастанию цены (лучшая
// сверху), потом снятые и перебитые.
func (p *Postgres) BidsByJob(ctx context.Context, jobID string) ([]job.Bid, error) {
	q := `SELECT` + bidColumns + `
	      FROM orders.bids WHERE job_id=$1
	      ORDER BY (status = 'active') DESC, price ASC, created_at ASC`
	rows, err := p.pool.Query(ctx, q, jobID)
	if err != nil {
		return nil, fmt.Errorf("orders: ставки задания: %w", err)
	}
	defer rows.Close()
	return collectBids(rows)
}

func (p *Postgres) BidsByOwner(ctx context.Context, ownerID string, limit, offset int) ([]job.Bid, error) {
	q := `SELECT` + bidColumns + `
	      FROM orders.bids WHERE owner_id=$1
	      ORDER BY created_at DESC LIMIT $2 OFFSET $3`
	rows, err := p.pool.Query(ctx, q, ownerID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("orders: ставки исполнителя: %w", err)
	}
	defer rows.Close()
	return collectBids(rows)
}

// BestBid — текущая лучшая (самая низкая) действующая ставка.
func (p *Postgres) BestBid(ctx context.Context, jobID string) (*job.Bid, error) {
	q := `SELECT` + bidColumns + `
	      FROM orders.bids WHERE job_id=$1 AND status='active'
	      ORDER BY price ASC, created_at ASC LIMIT 1`
	rows, err := p.pool.Query(ctx, q, jobID)
	if err != nil {
		return nil, fmt.Errorf("orders: лучшая ставка: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrBidNotFound
	}
	return scanBid(rows)
}

// MyBidForJob — действующая ставка исполнителя по заданию.
func (p *Postgres) MyBidForJob(ctx context.Context, jobID, ownerID string) (*job.Bid, error) {
	q := `SELECT` + bidColumns + `
	      FROM orders.bids WHERE job_id=$1 AND owner_id=$2
	      ORDER BY created_at DESC LIMIT 1`
	rows, err := p.pool.Query(ctx, q, jobID, ownerID)
	if err != nil {
		return nil, fmt.Errorf("orders: моя ставка: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrBidNotFound
	}
	return scanBid(rows)
}

func collectBids(rows pgx.Rows) ([]job.Bid, error) {
	out := []job.Bid{}
	for rows.Next() {
		b, err := scanBid(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *b)
	}
	return out, rows.Err()
}

func scanBid(rows pgx.Rows) (*job.Bid, error) {
	var b job.Bid
	if err := rows.Scan(&b.ID, &b.JobID, &b.OwnerID, &b.UnitID, &b.Price, &b.Currency,
		&b.Comment, &b.Status, &b.Score, &b.CreatedAt, &b.UpdatedAt); err != nil {
		return nil, fmt.Errorf("orders: чтение ставки: %w", err)
	}
	return &b, nil
}
