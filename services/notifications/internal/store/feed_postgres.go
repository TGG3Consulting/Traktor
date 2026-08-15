package store

import (
	"context"
	"encoding/json"
	"fmt"
	"time"
)

// Лента уведомлений в Postgres (ТЗ §2.14).

func (p *Postgres) SaveNotification(ctx context.Context, n Notification) error {
	data, err := json.Marshal(n.Data)
	if err != nil {
		return fmt.Errorf("notifications: данные уведомления: %w", err)
	}
	const q = `
		INSERT INTO notifications.feed (id, user_id, kind, title, body, data, created_at)
		VALUES ($1, $2::uuid, $3, $4, $5, $6::jsonb, $7)`
	if _, err := p.pool.Exec(ctx, q, n.ID, n.UserID, n.Kind, n.Title, n.Body,
		string(data), n.CreatedAt); err != nil {
		return fmt.Errorf("notifications: сохранение уведомления: %w", err)
	}
	return nil
}

func (p *Postgres) ListNotifications(ctx context.Context, userID string, limit, offset int) ([]Notification, error) {
	const q = `
		SELECT id::text, user_id::text, kind, title, body, data, read_at, created_at
		  FROM notifications.feed
		 WHERE user_id = $1::uuid
		 ORDER BY created_at DESC
		 LIMIT $2 OFFSET $3`
	rows, err := p.pool.Query(ctx, q, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("notifications: лента: %w", err)
	}
	defer rows.Close()

	out := []Notification{}
	for rows.Next() {
		var n Notification
		var raw []byte
		if err := rows.Scan(&n.ID, &n.UserID, &n.Kind, &n.Title, &n.Body, &raw,
			&n.ReadAt, &n.CreatedAt); err != nil {
			return nil, fmt.Errorf("notifications: чтение уведомления: %w", err)
		}
		if len(raw) > 0 {
			_ = json.Unmarshal(raw, &n.Data)
		}
		out = append(out, n)
	}
	return out, rows.Err()
}

func (p *Postgres) UnreadCount(ctx context.Context, userID string) (int, error) {
	const q = `SELECT count(*) FROM notifications.feed WHERE user_id = $1::uuid AND read_at IS NULL`
	var count int
	if err := p.pool.QueryRow(ctx, q, userID).Scan(&count); err != nil {
		return 0, fmt.Errorf("notifications: счётчик непрочитанного: %w", err)
	}
	return count, nil
}

func (p *Postgres) MarkNotificationsRead(ctx context.Context, userID string, ids []string, at time.Time) error {
	// Пустой список — «прочитать все»: кнопка в шапке центра уведомлений.
	if len(ids) == 0 {
		const q = `
			UPDATE notifications.feed SET read_at = $2
			 WHERE user_id = $1::uuid AND read_at IS NULL`
		_, err := p.pool.Exec(ctx, q, userID, at)
		return err
	}
	const q = `
		UPDATE notifications.feed SET read_at = $3
		 WHERE user_id = $1::uuid AND id = ANY($2::uuid[]) AND read_at IS NULL`
	_, err := p.pool.Exec(ctx, q, userID, ids, at)
	return err
}

func (p *Postgres) DeleteOldNotifications(ctx context.Context, before time.Time) (int, error) {
	tag, err := p.pool.Exec(ctx,
		`DELETE FROM notifications.feed WHERE created_at < $1`, before)
	if err != nil {
		return 0, fmt.Errorf("notifications: уборка ленты: %w", err)
	}
	return int(tag.RowsAffected()), nil
}
