package service

import (
	"context"
	"testing"
	"time"

	"traktor/notifications/internal/push"
	"traktor/notifications/internal/store"
)

// Настройки и тихие часы (ТЗ §2.14).

func TestВыключеннаяГруппаНеЗвонитНоСобытиеОстаётся(t *testing.T) {
	day := time.Date(2026, 8, 15, 10, 0, 0, 0, localZone)
	st := store.NewMemory()
	svc := New(st, push.NewFake(), func() time.Time { return day })
	ctx := context.Background()

	p := store.DefaultPrefs("u1")
	p.Chat = false
	if err := svc.SavePrefs(ctx, p); err != nil {
		t.Fatalf("настройки: %v", err)
	}
	_ = st.UpsertDevice(ctx, store.Device{Token: "t1", UserID: "u1"})

	delivered, err := svc.Notify(ctx, "u1", Notification{Kind: "message", Title: "Новое сообщение"})
	if err != nil {
		t.Fatalf("рассылка: %v", err)
	}

	if delivered != 0 {
		t.Fatal("человек выключил уведомления о сообщениях — push слать не нужно")
	}
	items, unread, _ := svc.Feed(ctx, "u1", 20, 0)
	if len(items) != 1 || unread != 1 {
		t.Fatalf("в центре уведомлений событие должно быть: %+v", items)
	}
}

func TestНочьюPushМолчит(t *testing.T) {
	night := time.Date(2026, 8, 15, 2, 0, 0, 0, localZone)
	st := store.NewMemory()
	svc := New(st, push.NewFake(), func() time.Time { return night })
	ctx := context.Background()
	_ = st.UpsertDevice(ctx, store.Device{Token: "t1", UserID: "u1"})

	delivered, _ := svc.Notify(ctx, "u1", Notification{Kind: "job", Title: "Новое задание рядом"})

	if delivered != 0 {
		t.Fatal("в тихие часы некритичные уведомления не будят человека")
	}
}

func TestПеребитаяСтавкаПроходитНочьюЕслиРазрешено(t *testing.T) {
	night := time.Date(2026, 8, 15, 2, 0, 0, 0, localZone)
	st := store.NewMemory()
	svc := New(st, push.NewFake(), func() time.Time { return night })
	ctx := context.Background()
	_ = st.UpsertDevice(ctx, store.Device{Token: "t1", UserID: "u1"})

	p := store.DefaultPrefs("u1")
	p.OutbidAlways = true
	_ = svc.SavePrefs(ctx, p)

	delivered, _ := svc.Notify(ctx, "u1", Notification{Kind: "outbid", Title: "Вашу ставку перебили"})

	if delivered != 1 {
		t.Fatal("на аукционе минуты решают: человек сам разрешил будить его ради ставки")
	}
}

func TestДнёмУведомленияПроходят(t *testing.T) {
	day := time.Date(2026, 8, 15, 12, 0, 0, 0, localZone)
	st := store.NewMemory()
	svc := New(st, push.NewFake(), func() time.Time { return day })
	ctx := context.Background()
	_ = st.UpsertDevice(ctx, store.Device{Token: "t1", UserID: "u1"})

	delivered, _ := svc.Notify(ctx, "u1", Notification{Kind: "deal", Title: "Сделка подтверждена"})

	if delivered != 1 {
		t.Fatalf("днём уведомление должно дойти: %d", delivered)
	}
}

func TestМаркетингТолькоПоСогласию(t *testing.T) {
	day := time.Date(2026, 8, 15, 12, 0, 0, 0, localZone)
	st := store.NewMemory()
	svc := New(st, push.NewFake(), func() time.Time { return day })
	ctx := context.Background()
	_ = st.UpsertDevice(ctx, store.Device{Token: "t1", UserID: "u1"})

	delivered, _ := svc.Notify(ctx, "u1", Notification{Kind: "marketing", Title: "Скидка"})

	if delivered != 0 {
		t.Fatal("рассылка по умолчанию выключена — это opt-in")
	}
}

func TestТихиеЧасыПереходятЧерезПолночь(t *testing.T) {
	p := store.DefaultPrefs("u1") // 22:00–08:00

	cases := []struct {
		hour  int
		quiet bool
	}{{23, true}, {2, true}, {7, true}, {8, false}, {12, false}, {21, false}, {22, true}}
	for _, c := range cases {
		at := time.Date(2026, 8, 15, c.hour, 0, 0, 0, localZone)
		if got := inQuietHours(p, at); got != c.quiet {
			t.Fatalf("%02d:00 — тишина должна быть %v, получили %v", c.hour, c.quiet, got)
		}
	}
}
