package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"traktor/orders/internal/job"
)

// Жалобы и сводка площадки (ТЗ §4.1, п.1 и 6).

const stranger = "33333333-3333-3333-3333-333333333333"

func publishedJob(t *testing.T, svc *Service) *job.Job {
	t.Helper()
	d := fullDraft(t, svc)
	j, err := svc.Publish(context.Background(), client, d.ID)
	if err != nil {
		t.Fatalf("публикация: %v", err)
	}
	return j
}

func TestЖалобаНаЗаданиеПопадаетВОчередь(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := publishedJob(t, svc)

	c, err := svc.Complain(ctx, owner, job.TargetJob, j.ID,
		"В описании просят предоплату на карту до выезда")
	if err != nil {
		t.Fatalf("жалоба: %v", err)
	}
	if c.Status != job.ComplaintOpen {
		t.Fatalf("жалоба должна ждать модерации: %s", c.Status)
	}

	queue, err := svc.ComplaintQueue(ctx, 0)
	if err != nil {
		t.Fatalf("очередь: %v", err)
	}
	if len(queue) != 1 || queue[0].ID != c.ID {
		t.Fatalf("жалоба не в очереди: %+v", queue)
	}
	if queue[0].TargetTitle == "" {
		t.Fatal("модератор должен видеть, на что жалуются, а не только идентификатор")
	}
}

func TestКороткаяЖалобаНаКонтентНеПринимается(t *testing.T) {
	svc := newSvc()
	j := publishedJob(t, svc)

	_, err := svc.Complain(context.Background(), owner, job.TargetJob, j.ID, "обман")
	if !errors.Is(err, job.ErrComplaintReason) {
		t.Fatalf("по слову «обман» смотреть нечего: %v", err)
	}
}

func TestПовторнаяЖалобаОтТогоЖеЧеловекаОтклонена(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := publishedJob(t, svc)

	if _, err := svc.Complain(ctx, owner, job.TargetJob, j.ID,
		"Просят предоплату на карту до выезда"); err != nil {
		t.Fatalf("первая жалоба: %v", err)
	}
	_, err := svc.Complain(ctx, owner, job.TargetJob, j.ID,
		"И телефон в описании чужой, я звонил")
	if !errors.Is(err, job.ErrComplaintExists) {
		t.Fatalf("повторные жалобы только раздувают очередь: %v", err)
	}
}

func TestНаСвоёЗаданиеЖаловатьсяНельзя(t *testing.T) {
	svc := newSvc()
	j := publishedJob(t, svc)

	_, err := svc.Complain(context.Background(), client, job.TargetJob, j.ID,
		"Что-то мне не нравится это задание")
	if !errors.Is(err, job.ErrComplaintSelf) {
		t.Fatalf("это собственный контент автора: %v", err)
	}
}

func TestСнятиеПоЖалобеОтменяетЗадание(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := publishedJob(t, svc)

	c, err := svc.Complain(ctx, owner, job.TargetJob, j.ID,
		"Просят предоплату на карту до выезда")
	if err != nil {
		t.Fatalf("жалоба: %v", err)
	}
	if _, err := svc.ReviewComplaint(ctx, stranger, c.ID, job.ActionRemoved,
		"Предоплата до выезда — запрещённая схема"); err != nil {
		t.Fatalf("разбор: %v", err)
	}

	after, _ := svc.View(ctx, client, j.ID)
	if after.Status != job.StatusCancelled {
		t.Fatalf("снятое задание не должно оставаться в ленте: %s", after.Status)
	}
	queue, _ := svc.ComplaintQueue(ctx, 0)
	if len(queue) != 0 {
		t.Fatalf("разобранная жалоба уходит из очереди: %+v", queue)
	}
}

func TestРазобраннаяЖалобаНеПересматривается(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := publishedJob(t, svc)

	c, _ := svc.Complain(ctx, owner, job.TargetJob, j.ID,
		"Просят предоплату на карту до выезда")
	if _, err := svc.ReviewComplaint(ctx, stranger, c.ID, job.ActionDismissed,
		"В описании нет ничего запрещённого"); err != nil {
		t.Fatalf("разбор: %v", err)
	}
	_, err := svc.ReviewComplaint(ctx, stranger, c.ID, job.ActionRemoved, "Передумали")
	if !errors.Is(err, job.ErrComplaintClosed) {
		t.Fatalf("решение окончательно: %v", err)
	}
}

func TestСводкаСчитаетЗаданияИКонверсию(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := inProgress(t, svc)
	_ = d

	from := svc.now().Add(-24 * time.Hour)
	to := svc.now().Add(24 * time.Hour)
	stats, err := svc.PlatformStats(ctx, from, to)
	if err != nil {
		t.Fatalf("сводка: %v", err)
	}
	if stats.Jobs == 0 || stats.Deals == 0 {
		t.Fatalf("в сводке нет ни заданий, ни сделок: %+v", stats)
	}
	if stats.Conversion() == 0 {
		t.Fatal("конверсия задание→сделка — главная цифра площадки")
	}
}
