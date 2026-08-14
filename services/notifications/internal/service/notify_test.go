package service

import (
	"context"
	"testing"
	"time"

	"traktor/notifications/internal/push"
	"traktor/notifications/internal/store"
)

func newSUT() (*Notifier, *push.Fake, store.Store) {
	st := store.NewMemory()
	fake := push.NewFake()
	fixed := time.Date(2026, 8, 14, 12, 0, 0, 0, time.UTC)
	return New(st, fake, func() time.Time { return fixed }), fake, st
}

func TestRegisterAndNotify_AllDevices(t *testing.T) {
	n, fake, _ := newSUT()
	ctx := context.Background()

	// Два устройства одного пользователя (телефон + web).
	must(t, n.RegisterDevice(ctx, RegisterInput{UserID: "u1", Token: "tok-a", Platform: store.PlatformAndroid, Locale: "ru"}))
	must(t, n.RegisterDevice(ctx, RegisterInput{UserID: "u1", Token: "tok-b", Platform: store.PlatformWeb, Locale: "hy"}))
	// Чужое устройство — не должно получить.
	must(t, n.RegisterDevice(ctx, RegisterInput{UserID: "u2", Token: "tok-c", Platform: store.PlatformIOS}))

	delivered, err := n.Notify(ctx, "u1", Notification{Title: "Задание", Body: "Новый отклик"})
	if err != nil {
		t.Fatalf("notify: %v", err)
	}
	if delivered != 2 {
		t.Fatalf("ожидалось 2 доставки, получено %d", delivered)
	}
	if fake.Count() != 2 {
		t.Fatalf("fake получил %d сообщений, ожидалось 2", fake.Count())
	}
}

func TestRegister_Idempotent(t *testing.T) {
	n, _, st := newSUT()
	ctx := context.Background()
	must(t, n.RegisterDevice(ctx, RegisterInput{UserID: "u1", Token: "tok-a", Platform: store.PlatformAndroid}))
	// Повторная регистрация того же токена не плодит дубликаты.
	must(t, n.RegisterDevice(ctx, RegisterInput{UserID: "u1", Token: "tok-a", Platform: store.PlatformAndroid}))
	devs, _ := st.ListDevicesByUser(ctx, "u1")
	if len(devs) != 1 {
		t.Fatalf("ожидалось 1 устройство, получено %d", len(devs))
	}
}

func TestNotify_PurgesInvalidToken(t *testing.T) {
	n, _, st := newSUT()
	ctx := context.Background()
	// Fake считает токены с префиксом "invalid" протухшими.
	must(t, n.RegisterDevice(ctx, RegisterInput{UserID: "u1", Token: "invalid-tok", Platform: store.PlatformAndroid}))
	must(t, n.RegisterDevice(ctx, RegisterInput{UserID: "u1", Token: "good-tok", Platform: store.PlatformAndroid}))

	delivered, err := n.Notify(ctx, "u1", Notification{Title: "t", Body: "b"})
	if err != nil {
		t.Fatalf("notify: %v", err)
	}
	if delivered != 1 {
		t.Fatalf("ожидалась 1 доставка (второй токен протух), получено %d", delivered)
	}
	// Протухший токен должен быть удалён.
	devs, _ := st.ListDevicesByUser(ctx, "u1")
	if len(devs) != 1 || devs[0].Token != "good-tok" {
		t.Fatalf("протухший токен не вычищен: %+v", devs)
	}
}

func TestUnregister(t *testing.T) {
	n, _, st := newSUT()
	ctx := context.Background()
	must(t, n.RegisterDevice(ctx, RegisterInput{UserID: "u1", Token: "tok-a", Platform: store.PlatformAndroid}))
	must(t, n.UnregisterDevice(ctx, "tok-a"))
	devs, _ := st.ListDevicesByUser(ctx, "u1")
	if len(devs) != 0 {
		t.Fatalf("устройство не снято: %+v", devs)
	}
}

func TestRegister_Validation(t *testing.T) {
	n, _, _ := newSUT()
	ctx := context.Background()
	if err := n.RegisterDevice(ctx, RegisterInput{UserID: "", Token: "t"}); err == nil {
		t.Fatal("ожидалась ошибка при пустом userID")
	}
	if err := n.RegisterDevice(ctx, RegisterInput{UserID: "u1", Token: ""}); err == nil {
		t.Fatal("ожидалась ошибка при пустом токене")
	}
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}
