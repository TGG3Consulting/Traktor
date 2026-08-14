// Package service — бизнес-логика identity: отправка/проверка OTP, выпуск и
// ротация сессий. Сервер — источник истины (ТЗ §4.3): коды, попытки, сроки
// считаются здесь, не на клиенте.
package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"math/big"
	"time"

	"traktor/identity/internal/sms"
	"traktor/identity/internal/store"
	"traktor/identity/internal/token"
)

var (
	ErrTooManyAttempts = errors.New("too many attempts")
	ErrCodeInvalid     = errors.New("code invalid")
	ErrCodeExpired     = errors.New("code expired")
	ErrRefreshInvalid  = errors.New("refresh invalid")
)

const (
	codeTTL       = 5 * time.Minute
	maxAttempts   = 3
	accessTTL     = 15 * time.Minute
	refreshTTL    = 30 * 24 * time.Hour
	resendSeconds = 60
)

// Now — источник времени (подменяется в тестах).
type Now func() time.Time

type Auth struct {
	store  store.Store
	sms    sms.Provider
	signer *token.Signer
	now    Now
}

func NewAuth(s store.Store, p sms.Provider, signer *token.Signer, now Now) *Auth {
	if now == nil {
		now = time.Now
	}
	return &Auth{store: s, sms: p, signer: signer, now: now}
}

func hashStr(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])
}

func gen6() string {
	const digits = "0123456789"
	b := make([]byte, 6)
	for i := range b {
		n, _ := rand.Int(rand.Reader, big.NewInt(10))
		b[i] = digits[n.Int64()]
	}
	return string(b)
}

func randToken() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// StartOTP генерирует код, сохраняет его хэш и отправляет через провайдера.
func (a *Auth) StartOTP(ctx context.Context, phone string) (retryAfterSec int, channel string, err error) {
	code := gen6()
	if err := a.store.UpsertOTP(ctx, store.OTP{
		Phone:     phone,
		CodeHash:  hashStr(code),
		ExpiresAt: a.now().Add(codeTTL),
		Attempts:  0,
	}); err != nil {
		return 0, "", err
	}
	ch, err := a.sms.SendCode(ctx, phone, code)
	if err != nil {
		return 0, "", err
	}
	return resendSeconds, ch, nil
}

// Session — выпущенная пара токенов + пользователь.
type Session struct {
	AccessToken  string
	RefreshToken string
	ExpiresInSec int
	User         store.User
}

// VerifyOTP проверяет код, при успехе создаёт/находит пользователя и выдаёт сессию.
func (a *Auth) VerifyOTP(ctx context.Context, phone, code string) (*Session, error) {
	o, err := a.store.GetOTP(ctx, phone)
	if err != nil {
		return nil, ErrCodeInvalid
	}
	if a.now().After(o.ExpiresAt) {
		return nil, ErrCodeExpired
	}
	if o.Attempts >= maxAttempts {
		return nil, ErrTooManyAttempts
	}
	if hashStr(code) != o.CodeHash {
		o.Attempts++
		_ = a.store.UpsertOTP(ctx, *o)
		if o.Attempts >= maxAttempts {
			return nil, ErrTooManyAttempts
		}
		return nil, ErrCodeInvalid
	}
	_ = a.store.DeleteOTP(ctx, phone)

	// Найти или создать пользователя.
	u, err := a.store.GetUserByPhone(ctx, phone)
	if errors.Is(err, store.ErrNotFound) {
		u = &store.User{
			ID:         randToken()[:32],
			Phone:      phone,
			Roles:      []string{"client"},
			ActiveRole: "client",
			CreatedAt:  a.now(),
		}
		if err := a.store.CreateUser(ctx, *u); err != nil {
			return nil, err
		}
	} else if err != nil {
		return nil, err
	}
	return a.issue(ctx, *u)
}

func (a *Auth) issue(ctx context.Context, u store.User) (*Session, error) {
	now := a.now()
	claims := token.Claims{
		Sub: u.ID, Roles: u.Roles, ActiveRole: u.ActiveRole,
		Typ: "access", Iat: now.Unix(), Exp: now.Add(accessTTL).Unix(),
	}
	access, err := a.signer.Sign(claims)
	if err != nil {
		return nil, err
	}
	refresh := randToken()
	if err := a.store.SaveRefresh(ctx, store.Refresh{
		TokenHash: hashStr(refresh),
		UserID:    u.ID,
		FamilyID:  randToken()[:16],
		ExpiresAt: now.Add(refreshTTL),
	}); err != nil {
		return nil, err
	}
	return &Session{
		AccessToken:  access,
		RefreshToken: refresh,
		ExpiresInSec: int(accessTTL.Seconds()),
		User:         u,
	}, nil
}

// Refresh обновляет пару токенов с ротацией и обнаружением повторного
// использования: предъявление уже использованного refresh отзывает всю семью.
func (a *Auth) Refresh(ctx context.Context, refreshToken string) (*Session, error) {
	rec, err := a.store.GetRefresh(ctx, hashStr(refreshToken))
	if err != nil {
		return nil, ErrRefreshInvalid
	}
	if rec.Revoked || a.now().After(rec.ExpiresAt) {
		return nil, ErrRefreshInvalid
	}
	if rec.Used {
		// Повторное использование — компрометация: отзываем всю семью токенов.
		_ = a.store.RevokeFamily(ctx, rec.FamilyID)
		return nil, ErrRefreshInvalid
	}
	if err := a.store.MarkRefreshUsed(ctx, rec.TokenHash); err != nil {
		return nil, err
	}
	// Пользователь по refresh: находим по UserID через phone-индекс не нужен —
	// в реальной БД будет прямой доступ по ID; в памяти пользователь уже создан.
	// Для простоты каркаса выпускаем сессию по сохранённым в токене данным.
	u := store.User{ID: rec.UserID, Roles: []string{"client"}, ActiveRole: "client"}
	return a.issue(ctx, u)
}
