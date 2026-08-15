package store

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5/pgconn"
)

// Заявки на бейдж «Проверен» (ТЗ §2.3).

const verifyCols = `
	v.id::text, v.user_id::text, v.documents, v.doc_kind, v.status, v.reason,
	COALESCE(v.reviewed_by::text, ''), v.reviewed_at, v.created_at`

func (p *Postgres) CreateVerification(ctx context.Context, v *Verification) error {
	const q = `
		INSERT INTO identity.verifications
		  (id, user_id, documents, doc_kind, status, created_at)
		VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6)`
	_, err := p.pool.Exec(ctx, q, v.ID, v.UserID, v.Documents, v.DocKind, v.Status, v.CreatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			// Вторая заявка того же человека только удлиняет очередь.
			return ErrVerifyPending
		}
		return fmt.Errorf("identity: заявка на проверку: %w", err)
	}
	return nil
}

// ErrVerifyPending — заявка уже в работе.
var ErrVerifyPending = errors.New("identity: заявка уже на проверке")

func (p *Postgres) UpdateVerification(ctx context.Context, v *Verification) error {
	const q = `
		UPDATE identity.verifications
		   SET status = $2, reason = $3, reviewed_by = NULLIF($4,'')::uuid, reviewed_at = $5
		 WHERE id = $1::uuid`
	tag, err := p.pool.Exec(ctx, q, v.ID, v.Status, v.Reason, v.ReviewedBy, v.ReviewedAt)
	if err != nil {
		return fmt.Errorf("identity: решение по заявке: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (p *Postgres) VerificationByID(ctx context.Context, id string) (*Verification, error) {
	q := `SELECT ` + verifyCols + ` FROM identity.verifications v WHERE v.id = $1::uuid`
	return p.scanVerification(ctx, q, id)
}

func (p *Postgres) MyVerification(ctx context.Context, userID string) (*Verification, error) {
	q := `SELECT ` + verifyCols + `
	        FROM identity.verifications v
	       WHERE v.user_id = $1::uuid
	    ORDER BY v.created_at DESC
	       LIMIT 1`
	return p.scanVerification(ctx, q, userID)
}

func (p *Postgres) scanVerification(ctx context.Context, q, arg string) (*Verification, error) {
	rows, err := p.pool.Query(ctx, q, arg)
	if err != nil {
		return nil, fmt.Errorf("identity: выборка заявки: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, ErrNotFound
	}
	var v Verification
	if err := rows.Scan(&v.ID, &v.UserID, &v.Documents, &v.DocKind, &v.Status,
		&v.Reason, &v.ReviewedBy, &v.ReviewedAt, &v.CreatedAt); err != nil {
		return nil, fmt.Errorf("identity: чтение заявки: %w", err)
	}
	return &v, nil
}

// PendingVerifications — очередь модерации. Имя и телефон подмешиваются здесь:
// модератор сверяет документ с профилем, а не с идентификатором.
func (p *Postgres) PendingVerifications(ctx context.Context, limit int) ([]Verification, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	q := `SELECT ` + verifyCols + `,
	             COALESCE(u.name, ''), pgp_sym_decrypt(u.phone_enc, $1)::text
	        FROM identity.verifications v
	        JOIN identity.users u ON u.id = v.user_id
	       WHERE v.status = 'pending'
	    ORDER BY v.created_at
	       LIMIT $2`
	rows, err := p.pool.Query(ctx, q, p.encKey, limit)
	if err != nil {
		return nil, fmt.Errorf("identity: очередь проверок: %w", err)
	}
	defer rows.Close()

	out := []Verification{}
	for rows.Next() {
		var v Verification
		if err := rows.Scan(&v.ID, &v.UserID, &v.Documents, &v.DocKind, &v.Status,
			&v.Reason, &v.ReviewedBy, &v.ReviewedAt, &v.CreatedAt,
			&v.UserName, &v.UserPhone); err != nil {
			return nil, fmt.Errorf("identity: чтение заявки: %w", err)
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

func (p *Postgres) SetVerified(ctx context.Context, userID string, verified bool) error {
	const q = `UPDATE identity.users SET verified = $2 WHERE id = $1::uuid AND deleted_at IS NULL`
	tag, err := p.pool.Exec(ctx, q, userID, verified)
	if err != nil {
		return fmt.Errorf("identity: бейдж проверки: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
