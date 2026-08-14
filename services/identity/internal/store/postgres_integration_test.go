//go:build integration

// Интеграционные тесты Postgres-хранилища. Запускаются только с тегом
// `integration` и переменной TEST_DATABASE_URL (локально — Postgres в Docker,
// см. scripts/pg-up.bat). Без них обычный `go test ./...` остаётся быстрым и
// не требует базы.
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

	pg, err := NewPostgres(pool, "тестовый-ключ-шифрования")
	if err != nil {
		t.Fatalf("хранилище: %v", err)
	}
	return pg, ctx
}

// Полный цикл пользователя: создание, поиск по телефону и по id, обновление.
// Заодно проверяет, что телефон реально лежит зашифрованным.
func TestPostgresUserRoundTrip(t *testing.T) {
	pg, ctx := newPG(t)
	phone := "+3749100" + time.Now().Format("0405")

	u := User{
		ID: uuid.NewString(), Phone: phone,
		Roles: []string{"client"}, ActiveRole: "client",
		CreatedAt: time.Now().UTC().Truncate(time.Millisecond),
	}
	if err := pg.CreateUser(ctx, u); err != nil {
		t.Fatalf("создание: %v", err)
	}

	got, err := pg.GetUserByPhone(ctx, phone)
	if err != nil {
		t.Fatalf("поиск по телефону: %v", err)
	}
	if got.ID != u.ID || got.Phone != phone || got.ActiveRole != "client" {
		t.Fatalf("прочитан не тот пользователь: %+v", got)
	}

	// Телефон в базе не должен храниться открытым текстом.
	var raw []byte
	if err := pg.pool.QueryRow(ctx,
		`SELECT phone_enc FROM identity.users WHERE id = $1::uuid`, u.ID).Scan(&raw); err != nil {
		t.Fatalf("чтение phone_enc: %v", err)
	}
	if len(raw) == 0 || string(raw) == phone {
		t.Fatal("телефон должен храниться зашифрованным")
	}

	// Обновление профиля.
	got.Name = "Тигран"
	got.City = "Ереван"
	got.ActiveRole = "owner"
	got.Roles = []string{"client", "owner"}
	got.Verified = true
	if err := pg.UpdateUser(ctx, *got); err != nil {
		t.Fatalf("обновление: %v", err)
	}
	after, err := pg.GetUserByID(ctx, u.ID)
	if err != nil {
		t.Fatalf("поиск по id: %v", err)
	}
	if after.Name != "Тигран" || after.City != "Ереван" || after.ActiveRole != "owner" ||
		len(after.Roles) != 2 || !after.Verified {
		t.Fatalf("профиль не обновился: %+v", after)
	}

	if _, err := pg.GetUserByID(ctx, uuid.NewString()); err != ErrNotFound {
		t.Fatalf("несуществующий пользователь должен дать ErrNotFound, получили %v", err)
	}
}

func TestPostgresOTP(t *testing.T) {
	pg, ctx := newPG(t)
	phone := "+3749133" + time.Now().Format("0405")

	o := OTP{Phone: phone, CodeHash: "hash-1",
		ExpiresAt: time.Now().Add(5 * time.Minute).UTC(), Attempts: 0}
	if err := pg.UpsertOTP(ctx, o); err != nil {
		t.Fatalf("сохранение кода: %v", err)
	}

	// Повторный upsert — обновление, а не вторая строка.
	o.CodeHash, o.Attempts = "hash-2", 2
	if err := pg.UpsertOTP(ctx, o); err != nil {
		t.Fatalf("обновление кода: %v", err)
	}
	got, err := pg.GetOTP(ctx, phone)
	if err != nil {
		t.Fatalf("чтение кода: %v", err)
	}
	if got.CodeHash != "hash-2" || got.Attempts != 2 {
		t.Fatalf("код не обновился: %+v", got)
	}

	if err := pg.DeleteOTP(ctx, phone); err != nil {
		t.Fatalf("удаление кода: %v", err)
	}
	if _, err := pg.GetOTP(ctx, phone); err != ErrNotFound {
		t.Fatalf("после удаления ждали ErrNotFound, получили %v", err)
	}
}

// Ротация refresh-токенов: повторное использование не проходит, отзыв семьи
// помечает все токены.
func TestPostgresRefreshRotation(t *testing.T) {
	pg, ctx := newPG(t)
	phone := "+3749155" + time.Now().Format("0405")
	u := User{ID: uuid.NewString(), Phone: phone,
		Roles: []string{"client"}, ActiveRole: "client", CreatedAt: time.Now().UTC()}
	if err := pg.CreateUser(ctx, u); err != nil {
		t.Fatal(err)
	}

	family := uuid.NewString()
	r := Refresh{TokenHash: uuid.NewString(), UserID: u.ID, FamilyID: family,
		ExpiresAt: time.Now().Add(24 * time.Hour).UTC()}
	if err := pg.SaveRefresh(ctx, r); err != nil {
		t.Fatalf("сохранение refresh: %v", err)
	}

	if err := pg.MarkRefreshUsed(ctx, r.TokenHash); err != nil {
		t.Fatalf("пометка использования: %v", err)
	}
	// Повторная пометка того же токена — признак повторного использования.
	if err := pg.MarkRefreshUsed(ctx, r.TokenHash); err != ErrNotFound {
		t.Fatalf("повторное использование должно давать ErrNotFound, получили %v", err)
	}

	second := Refresh{TokenHash: uuid.NewString(), UserID: u.ID, FamilyID: family,
		ExpiresAt: time.Now().Add(24 * time.Hour).UTC()}
	if err := pg.SaveRefresh(ctx, second); err != nil {
		t.Fatal(err)
	}
	if err := pg.RevokeFamily(ctx, family); err != nil {
		t.Fatalf("отзыв семьи: %v", err)
	}
	got, err := pg.GetRefresh(ctx, second.TokenHash)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Revoked {
		t.Fatal("после отзыва семьи токен должен быть revoked")
	}
}
