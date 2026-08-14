// Package service — бизнес-логика notifications: регистрация push-токенов
// устройств и рассылка уведомлений пользователю на все его устройства.
// Сервер — источник истины (§2.3.9): что и когда слать решает сервер, не клиент.
package service

import (
	"context"
	"errors"
	"time"

	"traktor/notifications/internal/push"
	"traktor/notifications/internal/store"
)

// Now — источник времени (подменяется в тестах).
type Now func() time.Time

type Notifier struct {
	store    store.Store
	provider push.Provider
	now      Now
}

func New(s store.Store, p push.Provider, now Now) *Notifier {
	if now == nil {
		now = time.Now
	}
	return &Notifier{store: s, provider: p, now: now}
}

// RegisterInput — регистрация токена устройства (идемпотентна по токену).
type RegisterInput struct {
	UserID     string
	Token      string
	Platform   store.Platform
	Locale     string
	AppVersion string
}

var ErrInvalidInput = errors.New("invalid input")

// RegisterDevice сохраняет/обновляет push-токен пользователя.
func (n *Notifier) RegisterDevice(ctx context.Context, in RegisterInput) error {
	if in.UserID == "" || in.Token == "" {
		return ErrInvalidInput
	}
	if in.Platform == "" {
		in.Platform = store.PlatformAndroid
	}
	now := n.now()
	return n.store.UpsertDevice(ctx, store.Device{
		Token:      in.Token,
		UserID:     in.UserID,
		Platform:   in.Platform,
		Locale:     in.Locale,
		AppVersion: in.AppVersion,
		CreatedAt:  now,
		LastSeenAt: now,
	})
}

// UnregisterDevice снимает регистрацию токена (logout / отзыв разрешения).
func (n *Notifier) UnregisterDevice(ctx context.Context, token string) error {
	if token == "" {
		return ErrInvalidInput
	}
	return n.store.DeleteDevice(ctx, token)
}

// Notification — что доставляем пользователю. На Фазе 5 обрастёт категорией,
// тихими часами и центром уведомлений (push-матрица ТЗ §2.14); здесь — ядро.
type Notification struct {
	Title string
	Body  string
	Data  map[string]string
}

// Notify рассылает уведомление на все устройства пользователя. Протухшие
// токены (провайдер вернул ErrTokenInvalid) удаляются на месте. Возвращает
// число успешно доставленных сообщений.
func (n *Notifier) Notify(ctx context.Context, userID string, msg Notification) (delivered int, err error) {
	devices, err := n.store.ListDevicesByUser(ctx, userID)
	if err != nil {
		return 0, err
	}
	for _, d := range devices {
		sendErr := n.provider.Send(ctx, push.Message{
			Token: d.Token,
			Title: msg.Title,
			Body:  msg.Body,
			Data:  msg.Data,
		})
		switch {
		case sendErr == nil:
			delivered++
		case errors.Is(sendErr, push.ErrTokenInvalid):
			// Чистим мёртвый токен, чтобы не копить и не слать в пустоту.
			_ = n.store.DeleteDevice(ctx, d.Token)
		default:
			// Иные сбои — не роняем всю рассылку; на Фазе 5 добавится ретрай
			// через outbox+Pub/Sub (инвариант §2.3.12).
		}
	}
	return delivered, nil
}
