// Package store — доступ к данным identity. Дефолтная сборка использует
// in-memory реализацию (компилируется офлайн, годится для dev/тестов).
// Продовый Postgres — в postgres.go под build-тегом `postgres` (CI).
package store

import (
	"context"
	"errors"
	"time"
)

var ErrNotFound = errors.New("store: not found")

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
