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

	// Состояние в модерации (ТЗ §4.1, п.3): active — обычная работа,
	// frozen — нельзя откликаться и ставить ставки, banned — вход закрыт.
	// Бан обратимый: ошибку модератора должно быть можно исправить, не заводя
	// человеку новый номер.
	Status       string
	StatusReason string
	StatusAt     *time.Time
	StatusBy     string

	// Удаление аккаунта с отсрочкой (ТЗ §2.3): DeleteAfter — когда истекает
	// срок, до которого человек может передумать.
	DeleteAfter  *time.Time
	AnonymizedAt *time.Time
}

// Состояния пользователя в модерации.
const (
	StatusActive = "active"
	StatusFrozen = "frozen"
	StatusBanned = "banned"
)

// Verification — заявка человека на бейдж «Проверен» (ТЗ §2.3).
//
// Бейдж — главный сигнал доверия в ленте, поэтому выдаётся не по факту
// загрузки файла, а после того, как документ посмотрел человек.
type Verification struct {
	ID        string
	UserID    string
	Documents []string
	DocKind   string
	Status    string
	Reason    string

	ReviewedBy string
	ReviewedAt *time.Time
	CreatedAt  time.Time

	// Подмешивается в очередь модерации.
	UserName  string
	UserPhone string
}

// Состояния заявки на проверку.
const (
	VerifyPending  = "pending"
	VerifyApproved = "approved"
	VerifyRejected = "rejected"
)

// AdminAction — запись журнала действий модерации (ТЗ §4.1, п.8).
//
// Без журнала ошибку или злоупотребление невозможно ни найти, ни оспорить.
type AdminAction struct {
	ID        string
	ActorID   string
	Action    string
	TargetID  string
	Reason    string
	CreatedAt time.Time
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

	// CountUsers — регистрации за период. Нужен сводке площадки в orders:
	// пользователи живут здесь, и считать их должен тот, кто ими владеет
	// (правило 12: cross-schema JOIN запрещён).
	CountUsers(ctx context.Context, from, to time.Time) (int, error)

	GetUserByPhone(ctx context.Context, phone string) (*User, error)
	GetUserByID(ctx context.Context, id string) (*User, error)
	CreateUser(ctx context.Context, u User) error
	UpdateUser(ctx context.Context, u User) error

	// ── модерация пользователей (ТЗ §4.1, п.3 и 8) ───────────────────────────
	// SearchUsers — поиск по телефону, имени или идентификатору.
	SearchUsers(ctx context.Context, query string, limit int) ([]User, error)
	// SetUserStatus — заморозка, бан или снятие ограничений.
	SetUserStatus(ctx context.Context, id, status, reason, byID string, at time.Time) error
	LogAdminAction(ctx context.Context, a AdminAction) error

	// ── проверка человека (ТЗ §2.3) ──────────────────────────────────────────
	CreateVerification(ctx context.Context, v *Verification) error
	UpdateVerification(ctx context.Context, v *Verification) error
	VerificationByID(ctx context.Context, id string) (*Verification, error)
	// MyVerification — последняя заявка человека: по ней экран профиля решает,
	// показывать кнопку подачи или состояние проверки.
	MyVerification(ctx context.Context, userID string) (*Verification, error)
	// PendingVerifications — очередь модерации, старые сверху.
	PendingVerifications(ctx context.Context, limit int) ([]Verification, error)
	// SetVerified — выдать или снять бейдж.
	SetVerified(ctx context.Context, userID string, verified bool) error

	// ── удаление аккаунта (ТЗ §2.3, §4.3) ────────────────────────────────────
	// RequestDeletion ставит запрос в очередь, deleteAfter — конец отсрочки.
	RequestDeletion(ctx context.Context, userID string, requestedAt, deleteAfter time.Time) error
	// CancelDeletion — человек передумал и вошёл снова.
	CancelDeletion(ctx context.Context, userID string) error
	// DueDeletions — те, у кого отсрочка истекла.
	DueDeletions(ctx context.Context, now time.Time, limit int) ([]User, error)
	// Anonymize обезличивает профиль: имя и телефон стираются, сделки и
	// отзывы второй стороны остаются целыми.
	Anonymize(ctx context.Context, userID string, at time.Time) error
	// AdminActionsFor — история решений по конкретному человеку.
	AdminActionsFor(ctx context.Context, targetID string, limit int) ([]AdminAction, error)

	SaveRefresh(ctx context.Context, r Refresh) error
	GetRefresh(ctx context.Context, tokenHash string) (*Refresh, error)
	MarkRefreshUsed(ctx context.Context, tokenHash string) error
	RevokeFamily(ctx context.Context, familyID string) error
	// RevokeAllRefresh — обрыв всех сессий человека. Нужен при бане: иначе
	// забаненный работает ещё до истечения access-токена.
	RevokeAllRefresh(ctx context.Context, userID string) error
}
