package service

import (
	"context"
	"errors"
	"strings"

	"github.com/google/uuid"

	"traktor/identity/internal/store"
)

// Управление пользователями у модерации (ТЗ §4.1, п.3 и 8).
//
// Жалобы разбираются, но нарушитель продолжает работать: без блокировки
// решение модерации ничего не меняет. Бан обратимый — ошибку модератора должно
// быть можно исправить, не заводя человеку новый номер.

var (
	ErrBanned       = errors.New("identity: доступ закрыт модерацией")
	ErrBadStatus    = errors.New("identity: неизвестное состояние")
	ErrNeedReason   = errors.New("identity: ограничение нужно обосновать")
	ErrSelfSanction = errors.New("identity: нельзя применить к себе")
)

// minReason — короткое «нарушение правил» ничего не объясняет ни человеку,
// ни следующему модератору, который откроет карточку.
const minReason = 10

// SearchUsers — поиск по телефону (точно, с плюсом), идентификатору или части
// имени. Пустой запрос отдаёт последние зарегистрированные.
func (a *Auth) SearchUsers(ctx context.Context, query string, limit int) ([]store.User, error) {
	return a.store.SearchUsers(ctx, query, limit)
}

// UserCard — карточка человека для модерации: сам пользователь и история
// решений по нему. История нужна, чтобы отличить единичный срыв от привычки.
type UserCard struct {
	User    store.User
	History []store.AdminAction
}

func (a *Auth) UserCard(ctx context.Context, id string) (*UserCard, error) {
	u, err := a.store.GetUserByID(ctx, id)
	if err != nil {
		return nil, err
	}
	history, err := a.store.AdminActionsFor(ctx, id, 20)
	if err != nil {
		return nil, err
	}
	return &UserCard{User: *u, History: history}, nil
}

// SetStatus — заморозка, бан или снятие ограничений.
//
// Заморозка оставляет вход и переписку: у человека могут быть незакрытые
// сделки, и молча оборвать их — навредить второй стороне, а не нарушителю.
func (a *Auth) SetStatus(ctx context.Context, moderatorID, userID, status, reason string) (*store.User, error) {
	if moderatorID == userID {
		return nil, ErrSelfSanction
	}
	switch status {
	case store.StatusActive, store.StatusFrozen, store.StatusBanned:
	default:
		return nil, ErrBadStatus
	}
	reason = strings.TrimSpace(reason)
	if len([]rune(reason)) < minReason {
		return nil, ErrNeedReason
	}

	now := a.now()
	if err := a.store.SetUserStatus(ctx, userID, status, reason, moderatorID, now); err != nil {
		return nil, err
	}
	// Журнал (ТЗ §4.1, п.8): без него ошибку или злоупотребление невозможно
	// ни найти, ни оспорить. Пишем после смены состояния, но до ответа —
	// действие без записи в журнале не считается выполненным.
	if err := a.store.LogAdminAction(ctx, store.AdminAction{
		ID:        uuid.NewString(),
		ActorID:   moderatorID,
		Action:    "status:" + status,
		TargetID:  userID,
		Reason:    reason,
		CreatedAt: now,
	}); err != nil {
		return nil, err
	}

	// Бан обрывает активные сессии: иначе забаненный работает ещё 15 минут,
	// до истечения access-токена.
	if status == store.StatusBanned {
		_ = a.store.RevokeAllRefresh(ctx, userID)
	}
	return a.store.GetUserByID(ctx, userID)
}

// LogAction — запись в журнал о решении, принятом в другом сервисе
// (снятие задания по жалобе, отказ по технике). Нужна, чтобы вся история
// действий модерации собиралась в одном месте.
func (a *Auth) LogAction(ctx context.Context, actorID, action, targetID, reason string) error {
	return a.store.LogAdminAction(ctx, store.AdminAction{
		ID:        uuid.NewString(),
		ActorID:   actorID,
		Action:    action,
		TargetID:  targetID,
		Reason:    reason,
		CreatedAt: a.now(),
	})
}
