package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// Настройки уведомлений в Postgres (ТЗ §2.14).

func (p *Postgres) PrefsOf(ctx context.Context, userID string) (Prefs, error) {
	const q = `
		SELECT auctions, deals, chat, new_jobs, marketing,
		       quiet_hours, quiet_from, quiet_to, outbid_always
		  FROM notifications.prefs
		 WHERE user_id = $1::uuid`
	out := DefaultPrefs(userID)
	err := p.pool.QueryRow(ctx, q, userID).Scan(
		&out.Auctions, &out.Deals, &out.Chat, &out.NewJobs, &out.Marketing,
		&out.QuietHours, &out.QuietFrom, &out.QuietTo, &out.OutbidAlways,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		// Человек ничего не менял — действуют настройки по умолчанию.
		return DefaultPrefs(userID), nil
	}
	if err != nil {
		return out, fmt.Errorf("notifications: настройки: %w", err)
	}
	return out, nil
}

func (p *Postgres) SavePrefs(ctx context.Context, pref Prefs, at time.Time) error {
	const q = `
		INSERT INTO notifications.prefs
			(user_id, auctions, deals, chat, new_jobs, marketing,
			 quiet_hours, quiet_from, quiet_to, outbid_always, updated_at)
		VALUES ($1::uuid,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
		ON CONFLICT (user_id) DO UPDATE
		   SET auctions      = EXCLUDED.auctions,
		       deals         = EXCLUDED.deals,
		       chat          = EXCLUDED.chat,
		       new_jobs      = EXCLUDED.new_jobs,
		       marketing     = EXCLUDED.marketing,
		       quiet_hours   = EXCLUDED.quiet_hours,
		       quiet_from    = EXCLUDED.quiet_from,
		       quiet_to      = EXCLUDED.quiet_to,
		       outbid_always = EXCLUDED.outbid_always,
		       updated_at    = EXCLUDED.updated_at`
	_, err := p.pool.Exec(ctx, q, pref.UserID, pref.Auctions, pref.Deals, pref.Chat,
		pref.NewJobs, pref.Marketing, pref.QuietHours, pref.QuietFrom, pref.QuietTo,
		pref.OutbidAlways, at)
	if err != nil {
		return fmt.Errorf("notifications: сохранение настроек: %w", err)
	}
	return nil
}
