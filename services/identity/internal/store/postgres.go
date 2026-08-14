// Postgres-реализация Store на pgx/v5 (правило 23 — драйвер из экосистемы,
// не самопис). Схема — migrations/000001_init.up.sql, принадлежит только
// сервису identity (schema-per-service, ADR-3/4).
//
// PII (правило 15): телефон хранится зашифрованным (pgcrypto, pgp_sym_encrypt)
// в phone_enc; поиск идёт по неповторимому phone_hash (SHA-256), чтобы не
// расшифровывать таблицу целиком.
package store

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Postgres struct {
	pool   *pgxpool.Pool
	encKey string // ключ шифрования телефонов (Secret Manager → env)
}

// NewPostgres создаёт хранилище. encKey не может быть пустым: без него телефоны
// легли бы в базу открытым текстом.
func NewPostgres(pool *pgxpool.Pool, encKey string) (*Postgres, error) {
	if encKey == "" {
		return nil, errors.New("store: пустой ключ шифрования телефонов (PHONE_ENC_KEY)")
	}
	return &Postgres{pool: pool, encKey: encKey}, nil
}

func mapErr(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	return err
}

// ── OTP ───────────────────────────────────────────────────

func (p *Postgres) UpsertOTP(ctx context.Context, o OTP) error {
	const q = `
		INSERT INTO identity.otps (phone_hash, code_hash, expires_at, attempts)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (phone_hash) DO UPDATE
		   SET code_hash  = EXCLUDED.code_hash,
		       expires_at = EXCLUDED.expires_at,
		       attempts   = EXCLUDED.attempts`
	_, err := p.pool.Exec(ctx, q, PhoneHash(o.Phone), o.CodeHash, o.ExpiresAt, o.Attempts)
	return err
}

func (p *Postgres) GetOTP(ctx context.Context, phone string) (*OTP, error) {
	const q = `SELECT code_hash, expires_at, attempts FROM identity.otps WHERE phone_hash = $1`
	o := OTP{Phone: phone}
	err := p.pool.QueryRow(ctx, q, PhoneHash(phone)).Scan(&o.CodeHash, &o.ExpiresAt, &o.Attempts)
	if err != nil {
		return nil, mapErr(err)
	}
	return &o, nil
}

func (p *Postgres) DeleteOTP(ctx context.Context, phone string) error {
	_, err := p.pool.Exec(ctx, `DELETE FROM identity.otps WHERE phone_hash = $1`, PhoneHash(phone))
	return err
}

// ── Пользователи ──────────────────────────────────────────

// userCols — общий список колонок. Ключ расшифровки всегда идёт параметром $2,
// поэтому оба запроса ниже принимают (условие, encKey) именно в таком порядке.
const userCols = `
	id::text,
	pgp_sym_decrypt(phone_enc, $2)::text AS phone,
	COALESCE(name, ''), COALESCE(city, ''),
	roles, active_role, verified, created_at`

func (p *Postgres) scanUser(row pgx.Row) (*User, error) {
	var u User
	err := row.Scan(&u.ID, &u.Phone, &u.Name, &u.City, &u.Roles, &u.ActiveRole, &u.Verified, &u.CreatedAt)
	if err != nil {
		return nil, mapErr(err)
	}
	return &u, nil
}

func (p *Postgres) GetUserByPhone(ctx context.Context, phone string) (*User, error) {
	const q = `SELECT ` + userCols + `
		FROM identity.users WHERE phone_hash = $1 AND deleted_at IS NULL`
	return p.scanUser(p.pool.QueryRow(ctx, q, PhoneHash(phone), p.encKey))
}

func (p *Postgres) GetUserByID(ctx context.Context, id string) (*User, error) {
	const q = `SELECT ` + userCols + `
		FROM identity.users WHERE id = $1::uuid AND deleted_at IS NULL`
	return p.scanUser(p.pool.QueryRow(ctx, q, id, p.encKey))
}

func (p *Postgres) CreateUser(ctx context.Context, u User) error {
	const q = `
		INSERT INTO identity.users
			(id, phone_enc, phone_hash, name, city, roles, active_role, verified, created_at)
		VALUES
			($1::uuid, pgp_sym_encrypt($2, $3), $4, NULLIF($5,''), NULLIF($6,''), $7, $8, $9, $10)`
	_, err := p.pool.Exec(ctx, q,
		u.ID, u.Phone, p.encKey, PhoneHash(u.Phone),
		u.Name, u.City, u.Roles, u.ActiveRole, u.Verified, u.CreatedAt)
	return err
}

func (p *Postgres) UpdateUser(ctx context.Context, u User) error {
	const q = `
		UPDATE identity.users
		   SET name = NULLIF($2,''), city = NULLIF($3,''),
		       roles = $4, active_role = $5, verified = $6
		 WHERE id = $1::uuid AND deleted_at IS NULL`
	tag, err := p.pool.Exec(ctx, q, u.ID, u.Name, u.City, u.Roles, u.ActiveRole, u.Verified)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// ── Refresh-сессии ────────────────────────────────────────

func (p *Postgres) SaveRefresh(ctx context.Context, r Refresh) error {
	const q = `
		INSERT INTO identity.refresh_tokens (token_hash, user_id, family_id, expires_at, used, revoked)
		VALUES ($1, $2::uuid, $3::uuid, $4, $5, $6)`
	_, err := p.pool.Exec(ctx, q, r.TokenHash, r.UserID, r.FamilyID, r.ExpiresAt, r.Used, r.Revoked)
	return err
}

func (p *Postgres) GetRefresh(ctx context.Context, tokenHash string) (*Refresh, error) {
	const q = `
		SELECT token_hash, user_id::text, family_id::text, expires_at, used, revoked
		  FROM identity.refresh_tokens WHERE token_hash = $1`
	var r Refresh
	err := p.pool.QueryRow(ctx, q, tokenHash).
		Scan(&r.TokenHash, &r.UserID, &r.FamilyID, &r.ExpiresAt, &r.Used, &r.Revoked)
	if err != nil {
		return nil, mapErr(err)
	}
	return &r, nil
}

// MarkRefreshUsed помечает токен использованным. Условие used = false делает
// операцию атомарной: при гонке двух одновременных refresh второй получит
// ErrNotFound, и клиент уйдёт на повторный вход вместо двойной выдачи сессии.
func (p *Postgres) MarkRefreshUsed(ctx context.Context, tokenHash string) error {
	const q = `UPDATE identity.refresh_tokens SET used = true WHERE token_hash = $1 AND used = false`
	tag, err := p.pool.Exec(ctx, q, tokenHash)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (p *Postgres) RevokeFamily(ctx context.Context, familyID string) error {
	_, err := p.pool.Exec(ctx,
		`UPDATE identity.refresh_tokens SET revoked = true WHERE family_id = $1::uuid`, familyID)
	return err
}

// Убеждаемся на этапе компиляции, что контракт Store реализован полностью.
var _ Store = (*Postgres)(nil)
