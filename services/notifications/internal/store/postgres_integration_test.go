//go:build integration

// Интеграционные тесты Postgres-хранилища notifications. Запускаются с тегом
// `integration` и переменной TEST_DATABASE_URL (Postgres в Docker).
package store

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
)

func newPG(t *testing.T) (*Postgres, context.Context) {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL не задан — пропускаем интеграционные тесты")
	}
	ctx := context.Background()
	if err := Migrate(ctx, dsn); err != nil {
		t.Fatalf("миграции: %v", err)
	}
	pool, err := OpenPool(ctx, dsn)
	if err != nil {
		t.Fatalf("пул: %v", err)
	}
	t.Cleanup(pool.Close)
	return NewPostgres(pool), ctx
}

func TestPostgresDeviceRoundTrip(t *testing.T) {
	pg, ctx := newPG(t)
	user := uuid.NewString()
	now := time.Now().UTC().Truncate(time.Millisecond)

	d := Device{Token: "tok-" + uuid.NewString(), UserID: user,
		Platform: PlatformIOS, Locale: "hy", AppVersion: "1.0.0",
		CreatedAt: now, LastSeenAt: now}
	if err := pg.UpsertDevice(ctx, d); err != nil {
		t.Fatalf("регистрация устройства: %v", err)
	}

	// Повторная регистрация того же токена — обновление, не дубль.
	d.LastSeenAt = now.Add(time.Minute)
	d.AppVersion = "1.1.0"
	if err := pg.UpsertDevice(ctx, d); err != nil {
		t.Fatalf("повторная регистрация: %v", err)
	}

	// Второе устройство того же пользователя (телефон + web).
	web := Device{Token: "tok-" + uuid.NewString(), UserID: user,
		Platform: PlatformWeb, Locale: "ru", CreatedAt: now, LastSeenAt: now}
	if err := pg.UpsertDevice(ctx, web); err != nil {
		t.Fatal(err)
	}

	list, err := pg.ListDevicesByUser(ctx, user)
	if err != nil {
		t.Fatalf("список устройств: %v", err)
	}
	if len(list) != 2 {
		t.Fatalf("ожидали 2 устройства, получили %d: %+v", len(list), list)
	}
	// Сортировка по последней активности: обновлённое устройство первое.
	if list[0].Token != d.Token || list[0].AppVersion != "1.1.0" || list[0].Platform != PlatformIOS {
		t.Fatalf("первым должно идти недавно активное устройство: %+v", list[0])
	}

	if err := pg.DeleteDevice(ctx, d.Token); err != nil {
		t.Fatalf("снятие регистрации: %v", err)
	}
	list, err = pg.ListDevicesByUser(ctx, user)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].Token != web.Token {
		t.Fatalf("после удаления должно остаться web-устройство: %+v", list)
	}

	// Чужой пользователь — пустой список, не ошибка.
	other, err := pg.ListDevicesByUser(ctx, uuid.NewString())
	if err != nil || len(other) != 0 {
		t.Fatalf("для пользователя без устройств ждали пустой список: %v %+v", err, other)
	}
}
