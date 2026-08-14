package service

import (
	"context"
	"errors"
	"testing"

	"traktor/orders/internal/job"
)

// dealReady — задание, доведённое до состояния «исполнитель выбран».
func dealReady(t *testing.T, svc *Service) (*job.Job, *job.Offer) {
	t.Helper()
	ctx := context.Background()
	j := published(t, svc)
	o, err := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferAccept, Price: 120000})
	if err != nil {
		t.Fatalf("отклик: %v", err)
	}
	if _, err := svc.AcceptOffer(ctx, client, o.ID); err != nil {
		t.Fatalf("выбор исполнителя: %v", err)
	}
	return j, o
}

func TestПодтверждениеСоздаётСделкуСЗафиксированнойЦеной(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j, o := dealReady(t, svc)

	d, err := svc.ConfirmDeal(ctx, client, j.ID)
	if err != nil {
		t.Fatalf("подтверждение: %v", err)
	}

	if d.Price != o.Price || d.OwnerID != owner || d.ClientID != client {
		t.Fatalf("сделка собрана неверно: %+v", d)
	}
	if d.Status != job.DealConfirmed || len(d.Timeline) != 1 {
		t.Fatalf("новая сделка должна быть подтверждена и иметь первую отметку: %+v", d)
	}

	updated, _ := svc.View(ctx, client, j.ID)
	if updated.Status != job.StatusConfirmed {
		t.Fatalf("статус задания должен идти следом: %s", updated.Status)
	}
}

func TestПовторноеПодтверждениеВозвращаетТуЖеСделку(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j, _ := dealReady(t, svc)

	first, _ := svc.ConfirmDeal(ctx, client, j.ID)
	second, err := svc.ConfirmDeal(ctx, client, j.ID)

	if err != nil {
		t.Fatalf("повтор не должен быть ошибкой: %v", err)
	}
	if first.ID != second.ID {
		t.Fatal("на задание должна быть одна сделка")
	}
}

func TestШагиСделкиИдутПоПорядкуИДелаютсяНужнойСтороной(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j, _ := dealReady(t, svc)
	d, _ := svc.ConfirmDeal(ctx, client, j.ID)

	// Заказчик не может «выехать» за исполнителя.
	if _, err := svc.AdvanceDeal(ctx, client, d.ID, job.DealOnTheWay, ""); !errors.Is(err, job.ErrDealWrongPerson) {
		t.Fatalf("шаг исполнителя не должен быть доступен заказчику: %v", err)
	}
	// Нельзя принять работу, которая не начиналась.
	if _, err := svc.AdvanceDeal(ctx, client, d.ID, job.DealCompleted, ""); !errors.Is(err, job.ErrDealStep) {
		t.Fatalf("нельзя перепрыгнуть шаги: %v", err)
	}

	if _, err := svc.AdvanceDeal(ctx, owner, d.ID, job.DealOnTheWay, "выехал"); err != nil {
		t.Fatalf("выехал: %v", err)
	}
	if _, err := svc.AdvanceDeal(ctx, owner, d.ID, job.DealInProgress, ""); err != nil {
		t.Fatalf("начал работу: %v", err)
	}
	done, err := svc.AdvanceDeal(ctx, owner, d.ID, job.DealWorkDone, "готово")
	if err != nil {
		t.Fatalf("завершил: %v", err)
	}
	if done.AcceptanceDeadline == nil {
		t.Fatal("после завершения должен появиться срок приёмки")
	}

	completed, err := svc.AdvanceDeal(ctx, client, d.ID, job.DealCompleted, "")
	if err != nil {
		t.Fatalf("приёмка: %v", err)
	}
	if completed.ClosedAt == nil || len(completed.Timeline) != 5 {
		t.Fatalf("таймлайн должен помнить все шаги: %+v", completed.Timeline)
	}

	updated, _ := svc.View(ctx, client, j.ID)
	if updated.Status != job.StatusCompleted {
		t.Fatalf("задание должно стать завершённым: %s", updated.Status)
	}
}

func TestЗакрытуюСделкуБольшеНеДвигают(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j, _ := dealReady(t, svc)
	d, _ := svc.ConfirmDeal(ctx, client, j.ID)
	_, _ = svc.AdvanceDeal(ctx, owner, d.ID, job.DealInProgress, "")
	_, _ = svc.AdvanceDeal(ctx, owner, d.ID, job.DealWorkDone, "")
	_, _ = svc.AdvanceDeal(ctx, client, d.ID, job.DealCompleted, "")

	_, err := svc.AdvanceDeal(ctx, owner, d.ID, job.DealInProgress, "")

	if !errors.Is(err, job.ErrDealClosed) {
		t.Fatalf("завершённую сделку двигать нельзя: %v", err)
	}
}

func TestОтменаТребуетПричиныИЗакрываетЗадание(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j, _ := dealReady(t, svc)
	d, _ := svc.ConfirmDeal(ctx, client, j.ID)

	if _, err := svc.CancelDeal(ctx, client, d.ID, "   "); !errors.Is(err, job.ErrValidation) {
		t.Fatalf("без причины отменять нельзя: %v", err)
	}

	cancelled, err := svc.CancelDeal(ctx, client, d.ID, "сроки сдвинулись")
	if err != nil {
		t.Fatalf("отмена: %v", err)
	}
	if cancelled.CancelReason != "сроки сдвинулись" || cancelled.CancelledBy == nil {
		t.Fatalf("причина и инициатор должны сохраниться: %+v", cancelled)
	}

	updated, _ := svc.View(ctx, client, j.ID)
	if updated.Status != job.StatusCancelled {
		t.Fatalf("задание должно закрыться вместе со сделкой: %s", updated.Status)
	}
}

func TestПостороннийСделкуНеВидит(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j, _ := dealReady(t, svc)
	d, _ := svc.ConfirmDeal(ctx, client, j.ID)

	if _, err := svc.Deal(ctx, owner2, d.ID); !errors.Is(err, job.ErrDealNotParty) {
		t.Fatalf("в сделке есть телефоны сторон — посторонним доступа нет: %v", err)
	}
	if _, err := svc.Deal(ctx, owner, d.ID); err != nil {
		t.Fatalf("исполнитель свою сделку видеть должен: %v", err)
	}
}

func TestОбеСтороныВидятСделкуВСвоёмСписке(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j, _ := dealReady(t, svc)
	_, _ = svc.ConfirmDeal(ctx, client, j.ID)

	forClient, _ := svc.MyDeals(ctx, client, 20, 0)
	forOwner, _ := svc.MyDeals(ctx, owner, 20, 0)

	if len(forClient) != 1 || len(forOwner) != 1 {
		t.Fatalf("сделка должна быть у обеих сторон: %d / %d", len(forClient), len(forOwner))
	}
}

func TestУведомленияОШагахУходятВторойСтороне(t *testing.T) {
	svc, rec := newSvcWithNotifier()
	ctx := context.Background()
	j, _ := dealReady(t, svc)
	d, _ := svc.ConfirmDeal(ctx, client, j.ID)

	_, _ = svc.AdvanceDeal(ctx, owner, d.ID, job.DealOnTheWay, "")
	_, _ = svc.AdvanceDeal(ctx, owner, d.ID, job.DealInProgress, "")
	_, _ = svc.AdvanceDeal(ctx, owner, d.ID, job.DealWorkDone, "")

	// Заказчику: подтверждение выбора не в счёт — оно уходило исполнителю.
	msgs := rec.to(client)
	if len(msgs) < 3 {
		t.Fatalf("заказчик должен узнать про выезд, начало и завершение работы, пришло %d", len(msgs))
	}
}
