package service

import (
	"context"
	"testing"
	"time"

	"traktor/orders/internal/job"
	"traktor/orders/internal/store"
)

// Календарь занятости (ТЗ §3.1): дни со сделками система знает сама, а отпуск
// и ремонт техники человек отмечает руками.

func TestДеньСоСделкойПопадаетВКалендарь(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j, _ := dealReady(t, svc)
	if _, err := svc.ConfirmDeal(ctx, client, j.ID); err != nil {
		t.Fatalf("подтверждение: %v", err)
	}

	days, err := svc.Calendar(ctx, owner, time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatalf("календарь: %v", err)
	}

	if len(days) != 1 || days[0].Source != job.BusySourceDeal {
		t.Fatalf("день сделки должен быть занят: %+v", days)
	}
	if days[0].DealID == "" {
		t.Fatal("из календаря нужно уметь открыть сделку")
	}
}

func TestСвояОтметкаЗанимаетДень(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	day := time.Date(2026, 8, 20, 0, 0, 0, 0, time.UTC)

	if err := svc.MarkBusy(ctx, owner, day, "ремонт техники"); err != nil {
		t.Fatalf("отметка: %v", err)
	}

	days, _ := svc.Calendar(ctx, owner, day)
	if len(days) != 1 || days[0].Source != job.BusySourceManual {
		t.Fatalf("свой день должен быть в календаре: %+v", days)
	}
	if days[0].Note != "ремонт техники" {
		t.Fatalf("пометка сохраняется: %q", days[0].Note)
	}

	busy, _ := svc.BusyOn(ctx, owner, day)
	if !busy {
		t.Fatal("в отмеченный день исполнитель занят")
	}
}

func TestОтметкуМожноСнять(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	day := time.Date(2026, 8, 20, 0, 0, 0, 0, time.UTC)
	_ = svc.MarkBusy(ctx, owner, day, "отпуск")

	if err := svc.UnmarkBusy(ctx, owner, day); err != nil {
		t.Fatalf("снятие: %v", err)
	}

	days, _ := svc.Calendar(ctx, owner, day)
	if len(days) != 0 {
		t.Fatalf("после снятия день свободен: %+v", days)
	}
}

func TestСделкаСильнееСвоейОтметки(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j, _ := dealReady(t, svc)
	d, _ := svc.ConfirmDeal(ctx, client, j.ID)

	// Человек помечает тот же день «не работаю» — сделка уже подтверждена,
	// и календарь должен показывать именно её.
	_ = svc.MarkBusy(ctx, owner, d.CreatedAt, "передумал")

	days, _ := svc.Calendar(ctx, owner, d.CreatedAt)
	if len(days) != 1 {
		t.Fatalf("на день должна быть одна отметка: %+v", days)
	}
	if days[0].Source != job.BusySourceDeal {
		t.Fatalf("сделка важнее своей пометки: %+v", days[0])
	}
}

func TestКалендарьПоказываетТолькоСвоиДни(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	day := time.Date(2026, 8, 20, 0, 0, 0, 0, time.UTC)
	_ = svc.MarkBusy(ctx, owner, day, "отпуск")

	days, _ := svc.Calendar(ctx, owner2, day)
	if len(days) != 0 {
		t.Fatalf("чужая занятость не видна: %+v", days)
	}
}

func TestМесяцРаскрываетсяВГраницы(t *testing.T) {
	from, to := job.MonthRange(time.Date(2026, 8, 15, 12, 0, 0, 0, time.UTC))

	if from.Day() != 1 || from.Month() != time.August {
		t.Fatalf("начало месяца: %v", from)
	}
	if to.Month() != time.August || to.Day() != 31 {
		t.Fatalf("конец месяца: %v", to)
	}
}

func TestСвободныйДеньНеСчитаетсяЗанятым(t *testing.T) {
	svc := New(store.NewMemory(), func() time.Time {
		return time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	})

	busy, err := svc.BusyOn(context.Background(), owner, time.Date(2026, 8, 21, 0, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatalf("проверка дня: %v", err)
	}
	if busy {
		t.Fatal("день без сделок и отметок свободен")
	}
}
