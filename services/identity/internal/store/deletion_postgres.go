package store

import (
	"context"
	"fmt"
	"time"
)

// Удаление аккаунта с отсрочкой (ТЗ §2.3, §4.3).

func (p *Postgres) RequestDeletion(ctx context.Context, userID string, requestedAt, deleteAfter time.Time) error {
	const q = `
		UPDATE identity.users
		   SET delete_requested_at = $2, delete_after = $3
		 WHERE id = $1::uuid AND deleted_at IS NULL AND anonymized_at IS NULL`
	tag, err := p.pool.Exec(ctx, q, userID, requestedAt, deleteAfter)
	if err != nil {
		return fmt.Errorf("identity: запрос на удаление: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (p *Postgres) CancelDeletion(ctx context.Context, userID string) error {
	const q = `
		UPDATE identity.users
		   SET delete_requested_at = NULL, delete_after = NULL
		 WHERE id = $1::uuid AND anonymized_at IS NULL`
	tag, err := p.pool.Exec(ctx, q, userID)
	if err != nil {
		return fmt.Errorf("identity: отмена удаления: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (p *Postgres) DueDeletions(ctx context.Context, now time.Time, limit int) ([]User, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	const q = `
		SELECT id::text, COALESCE(name, '')
		  FROM identity.users
		 WHERE delete_after IS NOT NULL AND delete_after <= $1 AND anonymized_at IS NULL
		 LIMIT $2`
	rows, err := p.pool.Query(ctx, q, now, limit)
	if err != nil {
		return nil, fmt.Errorf("identity: очередь удаления: %w", err)
	}
	defer rows.Close()

	out := []User{}
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Name); err != nil {
			return nil, fmt.Errorf("identity: чтение очереди удаления: %w", err)
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// Anonymize обезличивает профиль. Телефон заменяется случайным значением, а не
// обнуляется: колонка хэша уникальна и участвует в поиске при входе — пустое
// значение помешало бы зарегистрироваться следующему человеку.
func (p *Postgres) Anonymize(ctx context.Context, userID string, at time.Time) error {
	const q = `
		UPDATE identity.users
		   SET name = NULL,
		       city = NULL,
		       verified = false,
		       phone_enc = pgp_sym_encrypt('удалён', $3),
		       phone_hash = 'deleted:' || id::text,
		       anonymized_at = $2,
		       deleted_at = $2,
		       delete_after = NULL
		 WHERE id = $1::uuid AND anonymized_at IS NULL`
	tag, err := p.pool.Exec(ctx, q, userID, at, p.encKey)
	if err != nil {
		return fmt.Errorf("identity: обезличивание: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	// Сессии обрываем: иначе удалённый аккаунт продолжает работать до конца
	// срока действия токенов.
	if _, err := p.pool.Exec(ctx,
		`UPDATE identity.refresh_tokens SET revoked = true WHERE user_id = $1::uuid`,
		userID); err != nil {
		return fmt.Errorf("identity: обрыв сессий: %w", err)
	}
	return nil
}
