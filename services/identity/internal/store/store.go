// Package store — доступ к данным identity. Есть две реализации одного
// интерфейса: Memory (dev и тесты) и Postgres на pgx/v5 (прод). Какая из них
// используется, решает cmd/identity по наличию DATABASE_URL.
package store

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"
)

var ErrNotFound = errors.New("store: not found")

// PhoneHash — детерминированный ключ поиска по номеру. Сам номер в базе лежит
// зашифрованным (pgcrypto), а искать по шифротексту нельзя, поэтому рядом
// хранится этот хэш.
func PhoneHash(phone string) string {
	h := sha256.Sum256([]byte(phone))
	return hex.EncodeToString(h[:])
}

// User — минимальная сущность пользователя (полная модель — в ТЗ §1.12).
type User struct {
	ID         string
	Phone      string
	Name       string
	City       string
	Roles      []string
	ActiveRole string
	Verified   bool
	CreatedAt  time.Time
}

// OTP — запись одноразового кода: хэш кода, срок, счётчик попыток.
type OTP struct {
	Phone     string
	CodeHash  string
	ExpiresAt time.Time
	Attempts  int
}

// Refresh — сессия обновления (rotating, с обнаружением повторного использования).
type Refresh struct {
	TokenHash string
	UserID    string
	FamilyID  string
	ExpiresAt time.Time
	Used      bool
	Revoked   bool
}

type Store interface {
	UpsertOTP(ctx context.Context, o OTP) error
	GetOTP(ctx context.Context, phone string) (*OTP, error)
	DeleteOTP(ctx context.Context, phone string) error

	GetUserByPhone(ctx context.Context, phone string) (*User, error)
	GetUserByID(ctx context.Context, id string) (*User, error)
	CreateUser(ctx context.Context, u User) error
	UpdateUser(ctx context.Context, u User) error

	SaveRefresh(ctx context.Context, r Refresh) error
	GetRefresh(ctx context.Context, tokenHash string) (*Refresh, error)
	MarkRefreshUsed(ctx context.Context, tokenHash string) error
	RevokeFamily(ctx context.Context, familyID string) error
}
