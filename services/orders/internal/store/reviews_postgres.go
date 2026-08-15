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

const reviewColumns = `
  id, deal_id, job_id, author_id, target_id, author_role, stars, tags, body,
  issue, reply_text, reply_at, published_at, created_at`

func (p *Postgres) CreateReview(ctx context.Context, r *job.Review) error {
	const q = `
	INSERT INTO orders.reviews
	  (id, deal_id, job_id, author_id, target_id, author_role, stars, tags, body,
	   issue, published_at, created_at)
	VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`
	if _, err := p.pool.Exec(ctx, q, r.ID, r.DealID, r.JobID, r.AuthorID, r.TargetID,
		r.AuthorRole, r.Stars, r.Tags, r.Text, r.Issue, r.PublishedAt, r.CreatedAt); err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			// Одна оценка на человека в сделке.
			return job.ErrReviewTwice
		}
		return fmt.Errorf("orders: сохранение отзыва: %w", err)
	}
	return nil
}

func (p *Postgres) UpdateReview(ctx context.Context, r *job.Review) error {
	const q = `
	UPDATE orders.reviews
	   SET reply_text=$2, reply_at=$3, published_at=$4
	 WHERE id=$1`
	tag, err := p.pool.Exec(ctx, q, r.ID, r.ReplyText, r.ReplyAt, r.PublishedAt)
	if err != nil {
		return fmt.Errorf("orders: обновление отзыва: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return job.ErrReviewNotFound
	}
	return nil
}

func (p *Postgres) ReviewByID(ctx context.Context, id string) (*job.Review, error) {
	rows, err := p.pool.Query(ctx, `SELECT`+reviewColumns+` FROM orders.reviews WHERE id=$1`, id)
	if err != nil {
		return nil, fmt.Errorf("orders: выборка отзыва: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrReviewNotFound
	}
	return scanReview(rows)
}

// ReviewsByDeal — обе оценки по сделке: по ним решается, пора ли публиковать.
func (p *Postgres) ReviewsByDeal(ctx context.Context, dealID string) ([]job.Review, error) {
	q := `SELECT` + reviewColumns + ` FROM orders.reviews WHERE deal_id=$1 ORDER BY created_at`
	return p.queryReviews(ctx, q, dealID)
}

// ReviewsAbout — что написали о человеке. Скрытые отзывы наружу не уходят.
func (p *Postgres) ReviewsAbout(ctx context.Context, userID string, limit, offset int) ([]job.Review, error) {
	q := `SELECT` + reviewColumns + `
	        FROM orders.reviews
	       WHERE target_id=$1 AND published_at IS NOT NULL
	    ORDER BY published_at DESC
	       LIMIT $2 OFFSET $3`
	return p.queryReviews(ctx, q, userID, limit, offset)
}

// ReviewsByAuthor — мои оценки: по ним экран понимает, что уже оценено.
func (p *Postgres) ReviewsByAuthor(ctx context.Context, userID string, limit, offset int) ([]job.Review, error) {
	q := `SELECT` + reviewColumns + `
	        FROM orders.reviews
	       WHERE author_id=$1
	    ORDER BY created_at DESC
	       LIMIT $2 OFFSET $3`
	return p.queryReviews(ctx, q, userID, limit, offset)
}

// RatingOf — сводка по человеку одним запросом: считать среднее в приложении
// на каждой карточке дороже, чем спросить базу.
func (p *Postgres) RatingOf(ctx context.Context, userID string, since time.Time) (job.RatingSummary, error) {
	const q = `
	SELECT COALESCE(AVG(stars), 0), COUNT(*)
	  FROM orders.reviews
	 WHERE target_id=$1 AND published_at IS NOT NULL AND created_at >= $2`
	var avg float64
	var count int
	if err := p.pool.QueryRow(ctx, q, userID, since).Scan(&avg, &count); err != nil {
		return job.RatingSummary{}, fmt.Errorf("orders: рейтинг: %w", err)
	}
	return job.RatingSummary{
		UserID: userID,
		Rating: float64(int(avg*10+0.5)) / 10,
		Count:  count,
	}, nil
}

// DueReviews — одинокие оценки, которые ждут дольше недели: их пора открыть,
// иначе честный отзыв так и не увидит свет из-за молчания второй стороны.
func (p *Postgres) DueReviews(ctx context.Context, before time.Time) ([]job.Review, error) {
	q := `SELECT` + reviewColumns + `
	        FROM orders.reviews
	       WHERE published_at IS NULL AND created_at <= $1
	    ORDER BY created_at
	       LIMIT 200`
	return p.queryReviews(ctx, q, before)
}

func (p *Postgres) queryReviews(ctx context.Context, q string, args ...any) ([]job.Review, error) {
	rows, err := p.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("orders: выборка отзывов: %w", err)
	}
	defer rows.Close()

	out := []job.Review{}
	for rows.Next() {
		r, err := scanReview(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *r)
	}
	return out, rows.Err()
}

func scanReview(rows pgx.Rows) (*job.Review, error) {
	var r job.Review
	if err := rows.Scan(
		&r.ID, &r.DealID, &r.JobID, &r.AuthorID, &r.TargetID, &r.AuthorRole,
		&r.Stars, &r.Tags, &r.Text, &r.Issue, &r.ReplyText, &r.ReplyAt,
		&r.PublishedAt, &r.CreatedAt,
	); err != nil {
		return nil, fmt.Errorf("orders: чтение отзыва: %w", err)
	}
	return &r, nil
}
