package store

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

// Модерация пользователей (ТЗ §4.1, п.3 и 8).
//
// Телефон в базе зашифрован, поэтому искать по нему можно только точным
// совпадением через хэш — расшифровывать таблицу целиком ради подстроки
// недопустимо (правило 15).

// SearchUsers — поиск по телефону (точно), идентификатору или части имени.
func (p *Postgres) SearchUsers(ctx context.Context, query string, limit int) ([]User, error) {
	query = strings.TrimSpace(query)
	if limit <= 0 || limit > 100 {
		limit = 25
	}

	var where string
	var arg any
	switch {
	case strings.HasPrefix(query, "+"):
		where, arg = "phone_hash = $2", PhoneHash(query)
	case isUUID(query):
		where, arg = "id = $2::uuid", query
	case query == "":
		// Пустой запрос — последние зарегистрированные: панель модерации
		// должна что-то показывать до того, как в неё что-то ввели.
		where, arg = "$2 = ''", ""
	default:
		where, arg = "lower(name) LIKE '%' || lower($2) || '%'", query
	}

	// Свой список колонок: ключ расшифровки здесь идёт первым параметром,
	// а не вторым, как в выборках по одному человеку.
	const cols = `
		id::text,
		pgp_sym_decrypt(phone_enc, $1)::text AS phone,
		COALESCE(name, ''), COALESCE(city, ''),
		roles, active_role, verified, created_at,
		status, status_reason, status_at, COALESCE(status_by::text, '')`

	q := `SELECT ` + cols + `
	        FROM identity.users
	       WHERE deleted_at IS NULL AND ` + where + `
	    ORDER BY created_at DESC
	       LIMIT $3`
	rows, err := p.pool.Query(ctx, q, p.encKey, arg, limit)
	if err != nil {
		return nil, fmt.Errorf("identity: поиск пользователей: %w", err)
	}
	defer rows.Close()

	out := []User{}
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Phone, &u.Name, &u.City, &u.Roles, &u.ActiveRole,
			&u.Verified, &u.CreatedAt, &u.Status, &u.StatusReason, &u.StatusAt,
			&u.StatusBy); err != nil {
			return nil, fmt.Errorf("identity: чтение пользователя: %w", err)
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

func (p *Postgres) SetUserStatus(ctx context.Context, id, status, reason, byID string, at time.Time) error {
	const q = `
		UPDATE identity.users
		   SET status = $2, status_reason = $3, status_at = $4, status_by = NULLIF($5,'')::uuid
		 WHERE id = $1::uuid AND deleted_at IS NULL`
	tag, err := p.pool.Exec(ctx, q, id, status, reason, at, byID)
	if err != nil {
		return fmt.Errorf("identity: смена состояния: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (p *Postgres) LogAdminAction(ctx context.Context, a AdminAction) error {
	const q = `
		INSERT INTO identity.admin_actions (id, actor_id, action, target_id, reason, created_at)
		VALUES ($1::uuid, $2::uuid, $3, $4::uuid, $5, $6)`
	if a.ID == "" {
		a.ID = uuid.NewString()
	}
	_, err := p.pool.Exec(ctx, q, a.ID, a.ActorID, a.Action, a.TargetID, a.Reason, a.CreatedAt)
	if err != nil {
		return fmt.Errorf("identity: журнал модерации: %w", err)
	}
	return nil
}

func (p *Postgres) AdminActionsFor(ctx context.Context, targetID string, limit int) ([]AdminAction, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	const q = `
		SELECT id::text, actor_id::text, action, target_id::text, reason, created_at
		  FROM identity.admin_actions
		 WHERE target_id = $1::uuid
	  ORDER BY created_at DESC
		 LIMIT $2`
	rows, err := p.pool.Query(ctx, q, targetID, limit)
	if err != nil {
		return nil, fmt.Errorf("identity: история решений: %w", err)
	}
	defer rows.Close()

	out := []AdminAction{}
	for rows.Next() {
		var a AdminAction
		if err := rows.Scan(&a.ID, &a.ActorID, &a.Action, &a.TargetID, &a.Reason,
			&a.CreatedAt); err != nil {
			return nil, fmt.Errorf("identity: чтение журнала: %w", err)
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

func isUUID(s string) bool {
	_, err := uuid.Parse(s)
	return err == nil
}
