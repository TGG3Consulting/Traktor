// Postgres-реализация Store на pgx/v5 (правило 23). Схема —
// migrations/000001_init.up.sql, принадлежит только сервису notifications
// (schema-per-service, §2.3.11): FK на чужие схемы нет, связь с пользователем —
// по user_id из проверенного шлюзом JWT.
package store

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Postgres struct{ pool *pgxpool.Pool }

func NewPostgres(pool *pgxpool.Pool) *Postgres { return &Postgres{pool: pool} }

// UpsertDevice идемпотентен по токену: повторная регистрация того же токена
// обновляет владельца и отметку активности, а не плодит строки.
func (p *Postgres) UpsertDevice(ctx context.Context, d Device) error {
	const q = `
		INSERT INTO notifications.devices
			(token, user_id, platform, locale, app_version, created_at, last_seen_at)
		VALUES ($1, $2::uuid, $3, $4, NULLIF($5,''), $6, $7)
		ON CONFLICT (token) DO UPDATE
		   SET user_id      = EXCLUDED.user_id,
		       platform     = EXCLUDED.platform,
		       locale       = EXCLUDED.locale,
		       app_version  = EXCLUDED.app_version,
		       last_seen_at = EXCLUDED.last_seen_at`
	locale := d.Locale
	if locale == "" {
		locale = "ru"
	}
	platform := d.Platform
	if platform == "" {
		platform = PlatformAndroid
	}
	_, err := p.pool.Exec(ctx, q,
		d.Token, d.UserID, string(platform), locale, d.AppVersion, d.CreatedAt, d.LastSeenAt)
	return err
}

func (p *Postgres) DeleteDevice(ctx context.Context, token string) error {
	_, err := p.pool.Exec(ctx, `DELETE FROM notifications.devices WHERE token = $1`, token)
	return err
}

func (p *Postgres) ListDevicesByUser(ctx context.Context, userID string) ([]Device, error) {
	const q = `
		SELECT token, user_id::text, platform, locale, COALESCE(app_version,''), created_at, last_seen_at
		  FROM notifications.devices
		 WHERE user_id = $1::uuid
		 ORDER BY last_seen_at DESC`
	rows, err := p.pool.Query(ctx, q, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	defer rows.Close()

	var out []Device
	for rows.Next() {
		var d Device
		var platform string
		if err := rows.Scan(&d.Token, &d.UserID, &platform, &d.Locale, &d.AppVersion,
			&d.CreatedAt, &d.LastSeenAt); err != nil {
			return nil, err
		}
		d.Platform = Platform(platform)
		out = append(out, d)
	}
	return out, rows.Err()
}

// Проверка контракта на этапе компиляции.
var _ Store = (*Postgres)(nil)
