package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"traktor/orders/internal/job"
)

const complaintColumns = `
  id, target_kind, target_id, author_id, reason, status, action, note,
  reviewed_by, reviewed_at, created_at`

func (p *Postgres) CreateComplaint(ctx context.Context, c *job.Complaint) error {
	const q = `
	INSERT INTO orders.complaints
	  (id, target_kind, target_id, author_id, reason, status, created_at)
	VALUES ($1,$2,$3,$4,$5,$6,$7)`
	_, err := p.pool.Exec(ctx, q, c.ID, c.TargetKind, c.TargetID, c.AuthorID,
		c.Reason, string(c.Status), c.CreatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			// Повторные жалобы того же человека только раздувают очередь.
			return job.ErrComplaintExists
		}
		return fmt.Errorf("orders: жалоба: %w", err)
	}
	return nil
}

func (p *Postgres) UpdateComplaint(ctx context.Context, c *job.Complaint) error {
	const q = `
	UPDATE orders.complaints
	   SET status=$2, action=$3, note=$4, reviewed_by=$5, reviewed_at=$6
	 WHERE id=$1`
	tag, err := p.pool.Exec(ctx, q, c.ID, string(c.Status), nullableAction(c.Action),
		c.Note, nullable(c.ReviewedBy), c.ReviewedAt)
	if err != nil {
		return fmt.Errorf("orders: разбор жалобы: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return job.ErrComplaintNotFound
	}
	return nil
}

func (p *Postgres) ComplaintByID(ctx context.Context, id string) (*job.Complaint, error) {
	rows, err := p.pool.Query(ctx, `SELECT`+complaintColumns+` FROM orders.complaints WHERE id=$1`, id)
	if err != nil {
		return nil, fmt.Errorf("orders: выборка жалобы: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrComplaintNotFound
	}
	return scanComplaint(rows)
}

// OpenComplaints — очередь модерации со счётчиком жалоб на тот же объект:
// одна жалоба может быть сведением счётов, пять — уже сигнал.
func (p *Postgres) OpenComplaints(ctx context.Context, limit int) ([]job.Complaint, error) {
	q := `SELECT` + complaintColumns + `,
	        (SELECT COUNT(*) FROM orders.complaints x
	          WHERE x.target_kind = c.target_kind AND x.target_id = c.target_id)
	       FROM orders.complaints c
	      WHERE c.status = 'open'
	   ORDER BY c.created_at
	      LIMIT $1`
	// Явно перечисляем колонки с префиксом, иначе подзапрос ломает список.
	q = `SELECT c.id, c.target_kind, c.target_id, c.author_id, c.reason, c.status,
	            c.action, c.note, c.reviewed_by, c.reviewed_at, c.created_at,
	            (SELECT COUNT(*) FROM orders.complaints x
	              WHERE x.target_kind = c.target_kind AND x.target_id = c.target_id)
	       FROM orders.complaints c
	      WHERE c.status = 'open'
	   ORDER BY c.created_at
	      LIMIT $1`
	rows, err := p.pool.Query(ctx, q, limit)
	if err != nil {
		return nil, fmt.Errorf("orders: очередь жалоб: %w", err)
	}
	defer rows.Close()

	out := []job.Complaint{}
	for rows.Next() {
		var c job.Complaint
		var status string
		var action, reviewedBy *string
		if err := rows.Scan(&c.ID, &c.TargetKind, &c.TargetID, &c.AuthorID, &c.Reason,
			&status, &action, &c.Note, &reviewedBy, &c.ReviewedAt, &c.CreatedAt,
			&c.SameTarget); err != nil {
			return nil, fmt.Errorf("orders: чтение жалобы: %w", err)
		}
		c.Status = job.ComplaintStatus(status)
		if action != nil {
			c.Action = job.ComplaintAction(*action)
		}
		if reviewedBy != nil {
			c.ReviewedBy = *reviewedBy
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func scanComplaint(rows pgx.Rows) (*job.Complaint, error) {
	var c job.Complaint
	var status string
	var action, reviewedBy *string
	if err := rows.Scan(&c.ID, &c.TargetKind, &c.TargetID, &c.AuthorID, &c.Reason,
		&status, &action, &c.Note, &reviewedBy, &c.ReviewedAt, &c.CreatedAt); err != nil {
		return nil, fmt.Errorf("orders: чтение жалобы: %w", err)
	}
	c.Status = job.ComplaintStatus(status)
	if action != nil {
		c.Action = job.ComplaintAction(*action)
	}
	if reviewedBy != nil {
		c.ReviewedBy = *reviewedBy
	}
	return &c, nil
}

func nullableAction(a job.ComplaintAction) *string {
	if a == "" {
		return nil
	}
	s := string(a)
	return &s
}

// PlatformStats — сводка по площадке (ТЗ §4.1, п.1).
func (p *Postgres) PlatformStats(ctx context.Context, from, to time.Time) (job.PlatformStats, error) {
	var s job.PlatformStats

	const q = `
		SELECT
		  (SELECT COUNT(*) FROM orders.jobs
		    WHERE created_at BETWEEN $1 AND $2 AND status <> 'draft'),
		  (SELECT COUNT(*) FROM orders.deals
		    WHERE created_at BETWEEN $1 AND $2),
		  (SELECT COUNT(*) FROM orders.deals
		    WHERE status = 'completed' AND closed_at BETWEEN $1 AND $2),
		  (SELECT COALESCE(SUM(price), 0) FROM orders.deals
		    WHERE status = 'completed' AND closed_at BETWEEN $1 AND $2),
		  (SELECT COUNT(*) FROM orders.disputes WHERE status = 'open'),
		  (SELECT COUNT(*) FROM orders.complaints WHERE status = 'open')`
	if err := p.pool.QueryRow(ctx, q, from, to).Scan(&s.Jobs, &s.Deals, &s.Completed,
		&s.GMV, &s.OpenDisputes, &s.OpenComplaints); err != nil {
		return s, fmt.Errorf("orders: сводка площадки: %w", err)
	}
	return s, nil
}
