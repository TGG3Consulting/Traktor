// Package store — доступ к данным notifications. Дефолтная сборка использует
// in-memory реализацию (компилируется офлайн, годится для dev/тестов).
// Продовый Postgres — в postgres.go под build-тегом `postgres` (CI).
//
// Сервис владеет только своей схемой (schema-per-service, инвариант §2.3.11):
// здесь — реестр push-токенов устройств. Cross-schema JOIN запрещён; связь с
// пользователями — по user_id (строка), приходящему от gateway после проверки JWT.
package store

import (
	"context"
	"errors"
	"time"
)

var ErrNotFound = errors.New("store: not found")

// Platform — тип клиента (для выбора формата пуша и статистики доставки).
type Platform string

const (
	PlatformAndroid Platform = "android"
	PlatformIOS     Platform = "ios"
	PlatformWeb     Platform = "web"
)

// Device — зарегистрированный push-токен устройства пользователя.
// Токен уникален (PRIMARY KEY): одно устройство = один активный токен FCM.
// При переустановке/ротации FCM выдаёт новый токен — старый чистится по
// протуханию (провайдер вернёт "unregistered", см. service.Notify).
type Device struct {
	Token      string   // регистрационный токен FCM
	UserID     string   // владелец (из проверенного X-User-Id)
	Platform   Platform // android|ios|web
	Locale     string   // hy|ru|en — для локализованного текста пуша
	AppVersion string   // для сегментации и диагностики
	CreatedAt  time.Time
	LastSeenAt time.Time
}

// Notification — запись центра уведомлений (ТЗ §2.14).
//
// Push доходит не всегда: телефон выключен, разрешение не выдано, баннер
// смахнули. Лента — надёжный канал, push лишь ускоряет доставку.
type Notification struct {
	ID     string
	UserID string
	// Тип события из push-матрицы: по нему клиент рисует иконку.
	Kind  string
	Title string
	Body  string
	// Куда вести по нажатию (deep link) и данные для экрана назначения.
	Data      map[string]string
	ReadAt    *time.Time
	CreatedAt time.Time
}

// Prefs — настройки уведомлений (ТЗ §2.14).
//
// Управление по группам, а не один рубильник: иначе человек отключает всё
// разом и пропускает важное.
type Prefs struct {
	UserID    string
	Auctions  bool
	Deals     bool
	Chat      bool
	NewJobs   bool
	Marketing bool

	// Тихие часы для некритичных уведомлений (местное время).
	QuietHours bool
	QuietFrom  int
	QuietTo    int

	// «Вашу ставку перебили» приходит и ночью, если человек сам так решил.
	OutbidAlways bool
}

// DefaultPrefs — то, что действует, пока человек ничего не менял. Маркетинг
// выключен: рассылка только по согласию.
func DefaultPrefs(userID string) Prefs {
	return Prefs{
		UserID:     userID,
		Auctions:   true,
		Deals:      true,
		Chat:       true,
		NewJobs:    true,
		Marketing:  false,
		QuietHours: true,
		QuietFrom:  22,
		QuietTo:    8,
	}
}

// Store — хранилище токенов устройств, ленты уведомлений и настроек.
type Store interface {
	// UpsertDevice регистрирует/обновляет токен (идемпотентно по Token).
	UpsertDevice(ctx context.Context, d Device) error
	// DeleteDevice снимает регистрацию токена (logout, отзыв разрешения,
	// протухший токен от провайдера).
	DeleteDevice(ctx context.Context, token string) error
	// ListDevicesByUser — все активные токены пользователя (у него может быть
	// несколько устройств: телефон + web).
	ListDevicesByUser(ctx context.Context, userID string) ([]Device, error)

	// Центр уведомлений (ТЗ §2.14).
	SaveNotification(ctx context.Context, n Notification) error
	ListNotifications(ctx context.Context, userID string, limit, offset int) ([]Notification, error)
	UnreadCount(ctx context.Context, userID string) (int, error)
	// MarkNotificationsRead отмечает прочитанными: пустой список — все.
	MarkNotificationsRead(ctx context.Context, userID string, ids []string, at time.Time) error
	// DeleteOldNotifications — уборка старше срока хранения (90 дней).
	DeleteOldNotifications(ctx context.Context, before time.Time) (int, error)

	// Настройки уведомлений (ТЗ §2.14).
	PrefsOf(ctx context.Context, userID string) (Prefs, error)
	SavePrefs(ctx context.Context, p Prefs, at time.Time) error
}
