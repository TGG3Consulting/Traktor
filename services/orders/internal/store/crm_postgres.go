package store

import (
	"context"
	"fmt"
	"time"

	"traktor/orders/internal/job"
)

// Выборки для CRM (ТЗ §3.1). Считаем в базе, а не в приложении: тянуть все
// сделки за год на телефон ради одной суммы бессмысленно.

// IncomeOf — сумма завершённых сделок исполнителя за отрезок.
func (p *Postgres) IncomeOf(ctx context.Context, ownerID string, from, to time.Time) (int64, int, error) {
	const q = `
		SELECT COALESCE(SUM(price), 0), COUNT(*)
		  FROM orders.deals
		 WHERE owner_id = $1 AND status = 'completed'
		   AND closed_at >= $2 AND closed_at <= $3`
	var sum int64
	var count int
	if err := p.pool.QueryRow(ctx, q, ownerID, from, to).Scan(&sum, &count); err != nil {
		return 0, 0, fmt.Errorf("orders: доход исполнителя: %w", err)
	}
	return sum, count, nil
}

// FunnelOf — отклики, победы и завершённые работы за отрезок.
func (p *Postgres) FunnelOf(ctx context.Context, ownerID string, from, to time.Time) (job.Funnel, error) {
	var f job.Funnel

	// Отклики и ставки считаем вместе: для исполнителя это одно действие —
	// «я предложил себя на задание».
	const offersQ = `
		SELECT (SELECT COUNT(*) FROM orders.offers
		         WHERE owner_id = $1 AND created_at >= $2 AND created_at <= $3)
		     + (SELECT COUNT(*) FROM orders.bids
		         WHERE owner_id = $1 AND created_at >= $2 AND created_at <= $3)`
	if err := p.pool.QueryRow(ctx, offersQ, ownerID, from, to).Scan(&f.Offers); err != nil {
		return f, fmt.Errorf("orders: воронка (отклики): %w", err)
	}

	const dealsQ = `
		SELECT COUNT(*),
		       COUNT(*) FILTER (WHERE status = 'completed')
		  FROM orders.deals
		 WHERE owner_id = $1 AND created_at >= $2 AND created_at <= $3`
	if err := p.pool.QueryRow(ctx, dealsQ, ownerID, from, to).Scan(&f.Won, &f.Completed); err != nil {
		return f, fmt.Errorf("orders: воронка (сделки): %w", err)
	}
	return f, nil
}

// ClientsOf — клиентская база: с кем работал, сколько раз и на какую сумму.
func (p *Postgres) ClientsOf(ctx context.Context, ownerID string, from, to time.Time, limit int) ([]job.Client, error) {
	const q = `
		SELECT client_id::text, COUNT(*), COALESCE(SUM(price), 0), MAX(COALESCE(closed_at, created_at))
		  FROM orders.deals
		 WHERE owner_id = $1 AND status = 'completed'
		   AND closed_at >= $2 AND closed_at <= $3
		 GROUP BY client_id
		 ORDER BY SUM(price) DESC
		 LIMIT $4`
	rows, err := p.pool.Query(ctx, q, ownerID, from, to, limit)
	if err != nil {
		return nil, fmt.Errorf("orders: клиентская база: %w", err)
	}
	defer rows.Close()

	out := []job.Client{}
	for rows.Next() {
		var c job.Client
		if err := rows.Scan(&c.UserID, &c.Deals, &c.Total, &c.Last); err != nil {
			return nil, fmt.Errorf("orders: чтение клиента: %w", err)
		}
		out = append(out, c)
	}
	return out, rows.Err()
}
