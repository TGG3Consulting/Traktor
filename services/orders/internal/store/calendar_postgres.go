package store

import (
	"context"
	"fmt"
	"time"

	"traktor/orders/internal/job"
)

// Календарь занятости (ТЗ §3.1).

// BusyByDeals — дни, занятые подтверждёнными сделками. Берём даты задания:
// именно на них исполнитель выезжает. Если дат нет (режим «как можно скорее»),
// считаем занятым день подтверждения сделки — это ближе всего к правде.
func (p *Postgres) BusyByDeals(ctx context.Context, ownerID string, from, to time.Time) ([]job.BusyDay, error) {
	const q = `
		SELECT d.id::text, j.title,
		       COALESCE(j.date_start, d.created_at)::date AS start_day,
		       COALESCE(j.date_end, j.date_start, d.created_at)::date AS end_day
		  FROM orders.deals d
		  JOIN orders.jobs j ON j.id = d.job_id
		 WHERE d.owner_id = $1
		   AND d.status NOT IN ('cancelled')
		   AND COALESCE(j.date_end, j.date_start, d.created_at)::date >= $2::date
		   AND COALESCE(j.date_start, d.created_at)::date <= $3::date`
	rows, err := p.pool.Query(ctx, q, ownerID, from, to)
	if err != nil {
		return nil, fmt.Errorf("orders: занятые дни: %w", err)
	}
	defer rows.Close()

	out := []job.BusyDay{}
	for rows.Next() {
		var dealID, title string
		var start, end time.Time
		if err := rows.Scan(&dealID, &title, &start, &end); err != nil {
			return nil, fmt.Errorf("orders: чтение занятого дня: %w", err)
		}
		// Работа может идти несколько дней — закрашиваем весь отрезок.
		for day := start; !day.After(end); day = day.AddDate(0, 0, 1) {
			if day.Before(from) || day.After(to) {
				continue
			}
			out = append(out, job.BusyDay{
				Day:    day,
				Source: job.BusySourceDeal,
				DealID: dealID,
				Title:  title,
			})
		}
	}
	return out, rows.Err()
}

func (p *Postgres) ManualBusy(ctx context.Context, ownerID string, from, to time.Time) ([]job.BusyDay, error) {
	const q = `
		SELECT day, note FROM orders.busy_days
		 WHERE owner_id = $1 AND day >= $2::date AND day <= $3::date
		 ORDER BY day`
	rows, err := p.pool.Query(ctx, q, ownerID, from, to)
	if err != nil {
		return nil, fmt.Errorf("orders: свои отметки в календаре: %w", err)
	}
	defer rows.Close()

	out := []job.BusyDay{}
	for rows.Next() {
		var d job.BusyDay
		if err := rows.Scan(&d.Day, &d.Note); err != nil {
			return nil, fmt.Errorf("orders: чтение отметки: %w", err)
		}
		d.Source = job.BusySourceManual
		out = append(out, d)
	}
	return out, rows.Err()
}

func (p *Postgres) SetBusyDay(ctx context.Context, ownerID string, day time.Time, note string) error {
	const q = `
		INSERT INTO orders.busy_days (owner_id, day, note)
		VALUES ($1, $2::date, $3)
		ON CONFLICT (owner_id, day) DO UPDATE SET note = EXCLUDED.note`
	if _, err := p.pool.Exec(ctx, q, ownerID, day, note); err != nil {
		return fmt.Errorf("orders: отметка дня: %w", err)
	}
	return nil
}

func (p *Postgres) ClearBusyDay(ctx context.Context, ownerID string, day time.Time) error {
	const q = `DELETE FROM orders.busy_days WHERE owner_id = $1 AND day = $2::date`
	if _, err := p.pool.Exec(ctx, q, ownerID, day); err != nil {
		return fmt.Errorf("orders: снятие отметки: %w", err)
	}
	return nil
}
