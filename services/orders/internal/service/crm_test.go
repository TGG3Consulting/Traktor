package service

import (
	"context"
	"testing"
	"time"

	"traktor/orders/internal/job"
	"traktor/orders/internal/store"
)

// CRM исполнителя (ТЗ §3.1): цифры считаются из завершённых сделок, человек
// ничего не заполняет руками.

func TestСводкаСчитаетДоходИСреднийЧек(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc := New(store.NewMemory(), func() time.Time { return now })
	ctx := context.Background()

	for i := 0; i < 2; i++ {
		d := completed(t, svc)
		_ = d
	}

	b, err := svc.Business(ctx, owner, job.PeriodMonth)
	if err != nil {
		t.Fatalf("сводка: %v", err)
	}

	if b.Deals != 2 {
		t.Fatalf("завершённых сделок: %d", b.Deals)
	}
	if b.Income != 240000 {
		t.Fatalf("доход за месяц: %d", b.Income)
	}
	if b.Average != 120000 {
		t.Fatalf("средний чек: %d", b.Average)
	}
}

func TestВоронкаПоказываетГдеТеряютсяЗаказы(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc := New(store.NewMemory(), func() time.Time { return now })
	ctx := context.Background()

	// Один отклик довели до конца, второй остался просто откликом.
	_ = completed(t, svc)
	j := published(t, svc)
	if _, err := svc.MakeOffer(ctx, owner, j.ID, OfferInput{
		Kind: job.OfferAccept, Price: 120000,
	}); err != nil {
		t.Fatalf("отклик: %v", err)
	}

	b, _ := svc.Business(ctx, owner, job.PeriodMonth)

	if b.Funnel.Offers != 2 || b.Funnel.Won != 1 || b.Funnel.Completed != 1 {
		t.Fatalf("воронка: %+v", b.Funnel)
	}
	if b.Funnel.WinRate() != 0.5 {
		t.Fatalf("доля побед: %v", b.Funnel.WinRate())
	}
}

func TestКлиентскаяБазаСобираетсяСама(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc := New(store.NewMemory(), func() time.Time { return now })
	ctx := context.Background()

	_ = completed(t, svc)
	_ = completed(t, svc)

	b, _ := svc.Business(ctx, owner, job.PeriodMonth)

	if len(b.Clients) != 1 {
		t.Fatalf("работали с одним заказчиком: %+v", b.Clients)
	}
	if b.Clients[0].Deals != 2 || b.Clients[0].Total != 240000 {
		t.Fatalf("итоги по клиенту: %+v", b.Clients[0])
	}
	if b.Clients[0].Regular() {
		t.Fatal("постоянным клиент становится с третьей сделки")
	}
}

func TestДельтаБезПрошлогоДоходаНеСчитается(t *testing.T) {
	b := job.Business{Income: 100000, PrevIncome: 0}

	if _, ok := b.Delta(); ok {
		t.Fatal("рост с нуля в процентах не выражается — сравнивать не с чем")
	}

	b = job.Business{Income: 120000, PrevIncome: 100000}
	percent, ok := b.Delta()
	if !ok || percent != 20 {
		t.Fatalf("рост на пятую часть: %d%% (сравнимо: %v)", percent, ok)
	}
}

func TestПериодыРазворачиваютсяВДаты(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)

	week := job.RangeOf(job.PeriodWeek, now)
	if now.Sub(week.From) != 7*24*time.Hour {
		t.Fatalf("неделя — это семь дней назад: %v", week.From)
	}
	// Прошлый отрезок той же длины и кончается за мгновение до текущего:
	// сделка на стыке не должна попасть в оба.
	if !week.PrevTo.Before(week.From) || week.From.Sub(week.PrevFrom) != 7*24*time.Hour {
		t.Fatalf("прошлый отрезок посчитан неверно: %+v", week)
	}
}
