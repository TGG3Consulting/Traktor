package service

import (
	"context"
	"testing"
	"time"

	"traktor/notifications/internal/push"
	"traktor/notifications/internal/store"
)

// Центр уведомлений (ТЗ §2.14): push может не дойти, лента — надёжный канал.

func newFeedSvc(now func() time.Time) (*Notifier, *store.Memory) {
	st := store.NewMemory()
	return New(st, push.NewFake(), now), st
}

func TestУведомлениеПопадаетВЛентуДажеБезУстройств(t *testing.T) {
	fixed := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc, _ := newFeedSvc(func() time.Time { return fixed })
	ctx := context.Background()

	// Устройств у человека нет — push слать некуда.
	delivered, err := svc.Notify(ctx, "u1", Notification{
		Kind:  "offer",
		Title: "Новый отклик",
		Body:  "Карен предложил 85 000 ֏",
		Data:  map[string]string{"route": "/jobs/j1/offers"},
	})
	if err != nil {
		t.Fatalf("рассылка: %v", err)
	}
	if delivered != 0 {
		t.Fatalf("доставлять было некуда: %d", delivered)
	}

	items, unread, err := svc.Feed(ctx, "u1", 20, 0)
	if err != nil {
		t.Fatalf("лента: %v", err)
	}
	if len(items) != 1 || unread != 1 {
		t.Fatalf("событие должно остаться в центре уведомлений: %+v (непрочитано %d)", items, unread)
	}
	if items[0].Kind != "offer" || items[0].Data["route"] != "/jobs/j1/offers" {
		t.Fatalf("тип и переход должны сохраниться: %+v", items[0])
	}
}

func TestЧужиеУведомленияНеВидны(t *testing.T) {
	svc, _ := newFeedSvc(time.Now)
	ctx := context.Background()

	_, _ = svc.Notify(ctx, "u1", Notification{Title: "Вам"})

	items, unread, _ := svc.Feed(ctx, "u2", 20, 0)
	if len(items) != 0 || unread != 0 {
		t.Fatalf("лента строго своя: %+v", items)
	}
}

func TestПрочитатьВсё(t *testing.T) {
	svc, _ := newFeedSvc(time.Now)
	ctx := context.Background()
	for i := 0; i < 3; i++ {
		_, _ = svc.Notify(ctx, "u1", Notification{Title: "Событие"})
	}

	if err := svc.MarkRead(ctx, "u1", nil); err != nil {
		t.Fatalf("отметка: %v", err)
	}

	items, unread, _ := svc.Feed(ctx, "u1", 20, 0)
	if unread != 0 || len(items) != 3 {
		t.Fatalf("после «прочитать все» записи остаются, но непрочитанных нет: %d/%d", unread, len(items))
	}
}

func TestПрочитатьОдно(t *testing.T) {
	svc, _ := newFeedSvc(time.Now)
	ctx := context.Background()
	_, _ = svc.Notify(ctx, "u1", Notification{Title: "Первое"})
	_, _ = svc.Notify(ctx, "u1", Notification{Title: "Второе"})

	items, _, _ := svc.Feed(ctx, "u1", 20, 0)
	if err := svc.MarkRead(ctx, "u1", []string{items[0].ID}); err != nil {
		t.Fatalf("отметка: %v", err)
	}

	_, unread, _ := svc.Feed(ctx, "u1", 20, 0)
	if unread != 1 {
		t.Fatalf("прочитанным должно стать одно уведомление: осталось %d", unread)
	}
}

func TestЛентаОтдаётСвежиеСверху(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc, _ := newFeedSvc(func() time.Time { return now })
	ctx := context.Background()

	_, _ = svc.Notify(ctx, "u1", Notification{Title: "Старое"})
	now = now.Add(time.Hour)
	_, _ = svc.Notify(ctx, "u1", Notification{Title: "Свежее"})

	items, _, _ := svc.Feed(ctx, "u1", 20, 0)
	if items[0].Title != "Свежее" {
		t.Fatalf("свежее должно быть сверху: %+v", items)
	}
}

func TestСтарыеУведомленияУбираютсяЧерез90Дней(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc, _ := newFeedSvc(func() time.Time { return now })
	ctx := context.Background()

	_, _ = svc.Notify(ctx, "u1", Notification{Title: "Древнее"})
	now = now.Add(91 * 24 * time.Hour)
	_, _ = svc.Notify(ctx, "u1", Notification{Title: "Сегодняшнее"})

	removed, err := svc.Cleanup(ctx)
	if err != nil {
		t.Fatalf("уборка: %v", err)
	}
	if removed != 1 {
		t.Fatalf("убрать нужно только просроченное: %d", removed)
	}

	items, _, _ := svc.Feed(ctx, "u1", 20, 0)
	if len(items) != 1 || items[0].Title != "Сегодняшнее" {
		t.Fatalf("свежее остаётся: %+v", items)
	}
}
