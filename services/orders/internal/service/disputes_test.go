package service

import (
	"context"
	"errors"
	"testing"

	"traktor/orders/internal/job"
)

// Споры (ТЗ §4.1): арбитр вместо ссоры в переписке.

// inProgress — сделка, в которой исполнитель уже начал работу: до этого
// спорить не о чем, сделку просто отменяют.
func inProgress(t *testing.T, svc *Service) *job.Deal {
	t.Helper()
	ctx := context.Background()
	j, _ := dealReady(t, svc)
	d, err := svc.ConfirmDeal(ctx, client, j.ID)
	if err != nil {
		t.Fatalf("подтверждение: %v", err)
	}
	if _, err := svc.AdvanceDeal(ctx, owner, d.ID, job.DealOnTheWay, ""); err != nil {
		t.Fatalf("выехал: %v", err)
	}
	if _, err := svc.AdvanceDeal(ctx, owner, d.ID, job.DealInProgress, ""); err != nil {
		t.Fatalf("работает: %v", err)
	}
	got, _ := svc.Deal(ctx, client, d.ID)
	return got
}

func TestСпорОткрываетсяПоНачатойРаботе(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := inProgress(t, svc)

	dispute, err := svc.OpenDispute(ctx, client, d.ID,
		"Исполнитель выкопал траншею вдвое короче, чем договаривались", nil)
	if err != nil {
		t.Fatalf("открытие спора: %v", err)
	}

	if dispute.Status != job.DisputeOpen {
		t.Fatalf("новый спор открыт: %s", dispute.Status)
	}
	updated, _ := svc.Deal(ctx, client, d.ID)
	if updated.Status != job.DealDisputed {
		t.Fatalf("сделка уходит в спор: %s", updated.Status)
	}
}

func TestДоНачалаРаботыСпораНет(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j, _ := dealReady(t, svc)
	d, _ := svc.ConfirmDeal(ctx, client, j.ID)

	_, err := svc.OpenDispute(ctx, client, d.ID, "Мне кажется, он не приедет вовремя", nil)

	if !errors.Is(err, job.ErrDisputeStage) {
		t.Fatalf("до выезда сделку отменяют, а не спорят: %v", err)
	}
}

func TestПостороннийСпорНеОткрывает(t *testing.T) {
	svc := newSvc()
	d := inProgress(t, svc)

	_, err := svc.OpenDispute(context.Background(), owner2, d.ID,
		"Мне не нравится, как они работают вдвоём", nil)

	if !errors.Is(err, job.ErrDealNotParty) {
		t.Fatalf("спор открывает участник сделки: %v", err)
	}
}

func TestКороткаяЖалобаНеПринимается(t *testing.T) {
	svc := newSvc()
	d := inProgress(t, svc)

	_, err := svc.OpenDispute(context.Background(), client, d.ID, "плохо", nil)

	if !errors.Is(err, job.ErrDisputeReason) {
		t.Fatalf("по слову «плохо» разобрать нечего: %v", err)
	}
}

func TestВторойСпорПоСделкеНеОткрыть(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := inProgress(t, svc)
	_, _ = svc.OpenDispute(ctx, client, d.ID, "Работа сделана не полностью,半 участка", nil)

	_, err := svc.OpenDispute(ctx, owner, d.ID, "А заказчик не пускал на объект утром", nil)

	if !errors.Is(err, job.ErrDisputeExists) {
		t.Fatalf("на сделку один открытый спор: %v", err)
	}
}

func TestНаВремяСпораОценкиЗаморожены(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := inProgress(t, svc)
	_, _ = svc.AdvanceDeal(ctx, owner, d.ID, job.DealWorkDone, "")
	_, _ = svc.AdvanceDeal(ctx, client, d.ID, job.DealCompleted, "")
	_, _ = svc.OpenDispute(ctx, client, d.ID, "Работа принята, но качество оказалось хуже", nil)

	_, err := svc.LeaveReview(ctx, client, d.ID, job.Review{Stars: 1})

	if !errors.Is(err, job.ErrReviewFrozen) {
		t.Fatalf("отзыв не должен становиться оружием в конфликте: %v", err)
	}
}

func TestРешениеТребуетИсходаИОбоснования(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := inProgress(t, svc)
	dispute, _ := svc.OpenDispute(ctx, client, d.ID, "Траншея короче, чем договаривались", nil)

	if _, err := svc.ResolveDispute(ctx, "moder", dispute.ID, "", "Разобрались, всё в порядке"); !errors.Is(err, job.ErrDisputeOutcome) {
		t.Fatalf("исход обязателен: %v", err)
	}
	if _, err := svc.ResolveDispute(ctx, "moder", dispute.ID, job.OutcomeClient, "ок"); !errors.Is(err, job.ErrDisputeResolution) {
		t.Fatalf("решение без обоснования выглядит несправедливым: %v", err)
	}
}

func TestРешениеВПользуЗаказчикаОтменяетСделку(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := inProgress(t, svc)
	dispute, _ := svc.OpenDispute(ctx, client, d.ID, "Траншея короче, чем договаривались", nil)

	resolved, err := svc.ResolveDispute(ctx, "moder", dispute.ID, job.OutcomeClient,
		"По фотографиям видно, что выполнена половина работы. Оплата возвращается.")
	if err != nil {
		t.Fatalf("решение: %v", err)
	}

	if resolved.Status != job.DisputeResolved || resolved.Outcome != job.OutcomeClient {
		t.Fatalf("спор разобран: %+v", resolved)
	}
	deal, _ := svc.Deal(ctx, client, d.ID)
	if deal.Status != job.DealCancelled {
		t.Fatalf("сделка в пользу заказчика отменяется: %s", deal.Status)
	}
}

func TestРешениеВПользуИсполнителяЗакрываетРаботу(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := inProgress(t, svc)
	dispute, _ := svc.OpenDispute(ctx, client, d.ID, "Кажется, работа сделана плохо", nil)

	if _, err := svc.ResolveDispute(ctx, "moder", dispute.ID, job.OutcomeOwner,
		"Гео-чекины и фотографии подтверждают выполненный объём."); err != nil {
		t.Fatalf("решение: %v", err)
	}

	deal, _ := svc.Deal(ctx, client, d.ID)
	if deal.Status != job.DealCompleted {
		t.Fatalf("работа считается выполненной: %s", deal.Status)
	}
}

func TestПовторноеРешениеНевозможно(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := inProgress(t, svc)
	dispute, _ := svc.OpenDispute(ctx, client, d.ID, "Работа выполнена не полностью", nil)
	_, _ = svc.ResolveDispute(ctx, "moder", dispute.ID, job.OutcomeCompromise,
		"Половина работы сделана, стороны договорились о частичной оплате.")

	_, err := svc.ResolveDispute(ctx, "moder", dispute.ID, job.OutcomeOwner,
		"Передумали: работа выполнена полностью.")

	if !errors.Is(err, job.ErrDisputeClosed) {
		t.Fatalf("разобранный спор не пересматривается здесь: %v", err)
	}
}

func TestОбеСтороныУзнаютОРешении(t *testing.T) {
	svc, rec := newSvcWithNotifier()
	ctx := context.Background()
	d := inProgress(t, svc)
	dispute, _ := svc.OpenDispute(ctx, client, d.ID, "Работа выполнена не полностью", nil)

	_, _ = svc.ResolveDispute(ctx, "moder", dispute.ID, job.OutcomeCompromise,
		"Стороны договорились о частичной оплате, претензий больше нет.")

	if len(rec.to(client)) == 0 || len(rec.to(owner)) == 0 {
		t.Fatal("решение получают оба — иначе оно выглядит тайным")
	}
}

func TestОчередьСпоровОтсортированаПоВозрасту(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	first := inProgress(t, svc)
	second := inProgress(t, svc)
	_, _ = svc.OpenDispute(ctx, client, first.ID, "Первая жалоба на объём работы", nil)
	_, _ = svc.OpenDispute(ctx, client, second.ID, "Вторая жалоба на объём работы", nil)

	queue, err := svc.DisputeQueue(ctx, 10)
	if err != nil {
		t.Fatalf("очередь: %v", err)
	}
	if len(queue) != 2 {
		t.Fatalf("в очереди оба спора: %d", len(queue))
	}
	if queue[0].DealID != first.ID {
		t.Fatal("первым разбираем то, что ждёт дольше")
	}
}
