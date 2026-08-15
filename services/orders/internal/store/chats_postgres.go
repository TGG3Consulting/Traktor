package store

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"traktor/orders/internal/job"
)

const chatColumns = `
  id, job_id, client_id, owner_id, kind, last_message_at, created_at, updated_at`

func (p *Postgres) CreateChat(ctx context.Context, c *job.Chat) error {
	const q = `
	INSERT INTO orders.chats (id, job_id, client_id, owner_id, kind, created_at, updated_at)
	VALUES ($1,$2,$3,$4,$5,$6,$7)`
	if _, err := p.pool.Exec(ctx, q, c.ID, c.JobID, c.ClientID, c.OwnerID,
		string(c.Kind), c.CreatedAt, c.UpdatedAt); err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			// На пару «задание + исполнитель» чат один: параллельные запросы
			// не должны создавать вторую ветку переписки.
			return job.ErrChatNotFound
		}
		return fmt.Errorf("orders: создание чата: %w", err)
	}
	return nil
}

func (p *Postgres) ChatByID(ctx context.Context, id string) (*job.Chat, error) {
	rows, err := p.pool.Query(ctx, `SELECT`+chatColumns+` FROM orders.chats WHERE id=$1`, id)
	if err != nil {
		return nil, fmt.Errorf("orders: выборка чата: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrChatNotFound
	}
	return scanChat(rows)
}

func (p *Postgres) ChatByJobOwner(ctx context.Context, jobID, ownerID string) (*job.Chat, error) {
	q := `SELECT` + chatColumns + ` FROM orders.chats WHERE job_id=$1 AND owner_id=$2`
	rows, err := p.pool.Query(ctx, q, jobID, ownerID)
	if err != nil {
		return nil, fmt.Errorf("orders: чат по заданию: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrChatNotFound
	}
	return scanChat(rows)
}

// ChatsByUser — список чатов с превью последнего сообщения и числом
// непрочитанного. Собирается одним запросом: список чатов открывают часто, и
// «плюс запрос на каждую строку» здесь превратился бы в десятки обращений.
func (p *Postgres) ChatsByUser(ctx context.Context, userID string, limit, offset int) ([]job.Chat, error) {
	q := `
	SELECT c.id, c.job_id, c.client_id, c.owner_id, c.kind, c.last_message_at,
	       c.created_at, c.updated_at,
	       COALESCE(j.title, ''),
	       COALESCE((SELECT m.text FROM orders.messages m
	                 WHERE m.chat_id = c.id ORDER BY m.created_at DESC LIMIT 1), ''),
	       (SELECT count(*) FROM orders.messages m
	        WHERE m.chat_id = c.id AND NOT ($1 = ANY(m.read_by))
	          AND (m.sender_id IS NULL OR m.sender_id <> $1))
	FROM orders.chats c
	LEFT JOIN orders.jobs j ON j.id = c.job_id
	WHERE c.client_id = $1 OR c.owner_id = $1
	ORDER BY c.last_message_at DESC NULLS LAST, c.created_at DESC
	LIMIT $2 OFFSET $3`

	rows, err := p.pool.Query(ctx, q, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("orders: чаты пользователя: %w", err)
	}
	defer rows.Close()

	out := []job.Chat{}
	for rows.Next() {
		var c job.Chat
		if err := rows.Scan(&c.ID, &c.JobID, &c.ClientID, &c.OwnerID, &c.Kind,
			&c.LastMessageAt, &c.CreatedAt, &c.UpdatedAt,
			&c.JobTitle, &c.LastText, &c.Unread); err != nil {
			return nil, fmt.Errorf("orders: чтение чата: %w", err)
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (p *Postgres) UpdateChat(ctx context.Context, c *job.Chat) error {
	const q = `UPDATE orders.chats SET kind=$2, last_message_at=$3, updated_at=$4 WHERE id=$1`
	tag, err := p.pool.Exec(ctx, q, c.ID, string(c.Kind), c.LastMessageAt, c.UpdatedAt)
	if err != nil {
		return fmt.Errorf("orders: обновление чата: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return job.ErrChatNotFound
	}
	return nil
}

func (p *Postgres) CreateMessage(ctx context.Context, m *job.Message) error {
	const q = `
	INSERT INTO orders.messages (id, chat_id, sender_id, kind, text, media_url, read_by, created_at)
	VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`
	if _, err := p.pool.Exec(ctx, q, m.ID, m.ChatID, m.SenderID, string(m.Kind),
		m.Text, m.MediaURL, m.ReadBy, m.CreatedAt); err != nil {
		return fmt.Errorf("orders: вставка сообщения: %w", err)
	}
	return nil
}

func (p *Postgres) Messages(ctx context.Context, chatID string, limit, offset int) ([]job.Message, error) {
	q := `
	SELECT id, chat_id, sender_id, kind, text, media_url, read_by, created_at
	FROM orders.messages WHERE chat_id=$1
	ORDER BY created_at DESC LIMIT $2 OFFSET $3`
	rows, err := p.pool.Query(ctx, q, chatID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("orders: сообщения: %w", err)
	}
	defer rows.Close()

	out := []job.Message{}
	for rows.Next() {
		var m job.Message
		if err := rows.Scan(&m.ID, &m.ChatID, &m.SenderID, &m.Kind, &m.Text,
			&m.MediaURL, &m.ReadBy, &m.CreatedAt); err != nil {
			return nil, fmt.Errorf("orders: чтение сообщения: %w", err)
		}
		if m.ReadBy == nil {
			m.ReadBy = []string{}
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// MarkRead отмечает прочитанными все чужие сообщения чата.
func (p *Postgres) MarkRead(ctx context.Context, chatID, userID string) error {
	const q = `
	UPDATE orders.messages
	SET read_by = array_append(read_by, $2::uuid)
	WHERE chat_id = $1 AND NOT ($2 = ANY(read_by))
	  AND (sender_id IS NULL OR sender_id <> $2)`
	if _, err := p.pool.Exec(ctx, q, chatID, userID); err != nil {
		return fmt.Errorf("orders: отметка о прочтении: %w", err)
	}
	return nil
}

func scanChat(rows pgx.Rows) (*job.Chat, error) {
	var c job.Chat
	if err := rows.Scan(&c.ID, &c.JobID, &c.ClientID, &c.OwnerID, &c.Kind,
		&c.LastMessageAt, &c.CreatedAt, &c.UpdatedAt); err != nil {
		return nil, fmt.Errorf("orders: чтение чата: %w", err)
	}
	return &c, nil
}
