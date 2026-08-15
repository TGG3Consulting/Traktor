// Package service — бизнес-логика identity: отправка/проверка OTP, выпуск и
// ротация сессий. Сервер — источник истины (ТЗ §4.3): коды, попытки, сроки
// считаются здесь, не на клиенте.
package service

import (
	"strings"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"math/big"
	"time"

	"github.com/google/uuid"

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

	// staticCode — фиксированный код входа для разработки и демонстраций
	// (например «000000»). Пустая строка означает боевое поведение: код
	// случайный. Значение приходит из конфигурации, в коде не зашито.
	staticCode string

	// moderators — телефоны, которым выдаётся роль модератора (ТЗ §4.1).
	// Список задаёт владелец площадки через окружение: отдельной админки для
	// назначения ролей пока нет, а править базу руками — плохая практика.
	moderators []string
}

func NewAuth(s store.Store, p sms.Provider, signer *token.Signer, now Now) *Auth {
	if now == nil {
		now = time.Now
	}
	return &Auth{store: s, sms: p, signer: signer, now: now}
}

// WithModerators задаёт телефоны модераторов.
func (a *Auth) WithModerators(phones []string) *Auth {
	a.moderators = phones
	return a
}

// WithStaticCode включает фиксированный код входа (dev/демо). В проде не
// вызывается: там код всегда случайный.
func (a *Auth) WithStaticCode(code string) *Auth {
	a.staticCode = code
	return a
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
	if a.staticCode != "" {
		code = a.staticCode
	}
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
			ID:         uuid.NewString(),
			Phone:      phone,
			Roles:      a.rolesFor(phone),
			ActiveRole: "client",
			CreatedAt:  a.now(),
		}
		if err := a.store.CreateUser(ctx, *u); err != nil {
			return nil, err
		}
	} else if err != nil {
		return nil, err
	} else if a.isModerator(phone) && !hasRole(u.Roles, roleModerator) {
		// Телефон добавили в список модерации уже после регистрации —
		// выдаём роль при первом же входе, без ручной правки базы.
		u.Roles = append(u.Roles, roleModerator)
		if err := a.store.UpdateUser(ctx, *u); err != nil {
			return nil, err
		}
	}
	return a.issue(ctx, *u)
}

// roleModerator — доступ к очереди проверки техники и спорам (ТЗ §4.1).
// Роль живёт рядом с обычной: модератор остаётся заказчиком или исполнителем,
// просто ему дополнительно видна админская часть.
const roleModerator = "moderator"

func (a *Auth) rolesFor(phone string) []string {
	if a.isModerator(phone) {
		return []string{"client", roleModerator}
	}
	return []string{"client"}
}

// isModerator — телефон из списка MODERATOR_PHONES. Так роль выдаётся без
// отдельной админки и без правки базы руками: список задаёт владелец площадки.
func (a *Auth) isModerator(phone string) bool {
	for _, p := range a.moderators {
		if strings.TrimSpace(p) == phone {
			return true
		}
	}
	return false
}

func hasRole(roles []string, want string) bool {
	for _, r := range roles {
		if r == want {
			return true
		}
	}
	return false
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
		FamilyID:  uuid.NewString(),
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
	// Восстанавливаем реального пользователя по ID: роли/активная роль/профиль
	// должны сохраниться после ротации (владелец не должен «превратиться» в
	// заказчика). Инвариант §2.3.9 — источник истины сервер.
	u, err := a.store.GetUserByID(ctx, rec.UserID)
	if err != nil {
		return nil, ErrRefreshInvalid
	}
	return a.issue(ctx, *u)
}

// Me возвращает актуальный профиль пользователя по его ID (claims.Sub).
func (a *Auth) Me(ctx context.Context, id string) (*store.User, error) {
	return a.store.GetUserByID(ctx, id)
}

// ProfilePatch — частичное обновление профиля (nil-поля не трогаются).
type ProfilePatch struct {
	Name       *string
	City       *string
	ActiveRole *string
}

var ErrInvalidRole = errors.New("invalid role")

// UpdateProfile применяет частичные изменения профиля. Смена активной роли,
// которой ещё нет у пользователя, добавляет её в список ролей (пользователь
// может быть и заказчиком, и исполнителем — ТЗ §2.4). Профиль с именем считаем
// подтверждённым (verified) — этого ждёт клиент, чтобы уйти с шага «первый профиль».
func (a *Auth) UpdateProfile(ctx context.Context, id string, p ProfilePatch) (*store.User, error) {
	u, err := a.store.GetUserByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if p.Name != nil {
		u.Name = *p.Name
	}
	// Отметку «Проверен» ставит модерация после проверки документов и техники
	// (ТЗ §2.5). Раньше она выдавалась просто за заполненное имя — это обещало
	// людям доверие, которого никто не проверял.
	if p.City != nil {
		u.City = *p.City
	}
	if p.ActiveRole != nil {
		role := *p.ActiveRole
		if role != "client" && role != "owner" {
			return nil, ErrInvalidRole
		}
		u.ActiveRole = role
		if !contains(u.Roles, role) {
			u.Roles = append(u.Roles, role)
		}
	}
	if err := a.store.UpdateUser(ctx, *u); err != nil {
		return nil, err
	}
	return u, nil
}

func contains(xs []string, x string) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}

// Store открывает хранилище HTTP-слою: публичные карточки пользователей
// читаются напрямую, без бизнес-логики входа.
func (a *Auth) Store() store.Store { return a.store }
