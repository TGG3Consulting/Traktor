// Package service — бизнес-логика notifications: регистрация push-токенов
// устройств и рассылка уведомлений пользователю на все его устройства.
// Сервер — источник истины (§2.3.9): что и когда слать решает сервер, не клиент.
package service

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"

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

// Notification — что доставляем пользователю.
type Notification struct {
	// Kind — тип события из push-матрицы (ТЗ §2.14): по нему клиент рисует
	// иконку в центре уведомлений и группирует настройки.
	Kind  string
	Title string
	Body  string
	Data  map[string]string
}

// Notify рассылает уведомление на все устройства пользователя. Протухшие
// токены (провайдер вернул ErrTokenInvalid) удаляются на месте. Возвращает
// число успешно доставленных сообщений.
func (n *Notifier) Notify(ctx context.Context, userID string, msg Notification) (delivered int, err error) {
	// Сначала лента, потом push: push может не дойти (телефон выключен, баннер
	// смахнули), а центр уведомлений человек откроет сам (ТЗ §2.14).
	if err := n.saveToFeed(ctx, userID, msg); err != nil {
		return 0, err
	}

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

// saveToFeed сохраняет уведомление в центр уведомлений.
func (n *Notifier) saveToFeed(ctx context.Context, userID string, msg Notification) error {
	kind := msg.Kind
	if kind == "" {
		kind = "system"
	}
	return n.store.SaveNotification(ctx, store.Notification{
		ID:        uuid.NewString(),
		UserID:    userID,
		Kind:      kind,
		Title:     msg.Title,
		Body:      msg.Body,
		Data:      msg.Data,
		CreatedAt: n.now().UTC(),
	})
}

// Feed — центр уведомлений пользователя вместе со счётчиком непрочитанного.
func (n *Notifier) Feed(ctx context.Context, userID string, limit, offset int) ([]store.Notification, int, error) {
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	if offset < 0 {
		offset = 0
	}
	items, err := n.store.ListNotifications(ctx, userID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	unread, err := n.store.UnreadCount(ctx, userID)
	if err != nil {
		return nil, 0, err
	}
	return items, unread, nil
}

// MarkRead отмечает уведомления прочитанными. Пустой список — «прочитать все».
func (n *Notifier) MarkRead(ctx context.Context, userID string, ids []string) error {
	if userID == "" {
		return ErrInvalidInput
	}
	return n.store.MarkNotificationsRead(ctx, userID, ids, n.now().UTC())
}

// Cleanup убирает уведомления старше срока хранения (ТЗ §2.14: 90 дней).
func (n *Notifier) Cleanup(ctx context.Context) (int, error) {
	return n.store.DeleteOldNotifications(ctx, n.now().UTC().Add(-RetentionPeriod))
}

// RetentionPeriod — сколько живёт запись в центре уведомлений.
const RetentionPeriod = 90 * 24 * time.Hour
