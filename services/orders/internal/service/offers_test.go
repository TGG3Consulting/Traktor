package service

import (
	"context"
	"errors"
	"testing"

	"traktor/orders/internal/job"
)

const owner2 = "33333333-3333-3333-3333-333333333333"

// published — задание с фикс-ценой 120 000, готовое принимать отклики.
func published(t *testing.T, svc *Service) *job.Job {
	t.Helper()
	j := fullDraft(t, svc)
	p, err := svc.Publish(context.Background(), client, j.ID)
	if err != nil {
		t.Fatalf("публикация: %v", err)
	}
	return p
}

func TestОткликСогласиемБерётЦенуСервера(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)

	// Клиент прислал устаревшую цену — сервер подставляет свою.
	o, err := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferAccept, Price: 1})
	if err != nil {
		t.Fatalf("отклик: %v", err)
	}

	if o.Price != 120000 {
		t.Fatalf("при согласии цена берётся из задания, получили %d", o.Price)
	}
	if o.Status != job.OfferActive {
		t.Fatalf("новый отклик активен, получили %s", o.Status)
	}
}

func TestНаСвоёЗаданиеОткликнутьсяНельзя(t *testing.T) {
	svc := newSvc()
	j := published(t, svc)

	_, err := svc.MakeOffer(context.Background(), client, j.ID,
		OfferInput{Kind: job.OfferAccept, Price: 120000})

	if !errors.Is(err, job.ErrOwnJob) {
		t.Fatalf("ожидали запрет на свой заказ, получили %v", err)
	}
}

func TestПовторныйОткликОбновляетПредложение(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)

	first, _ := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferCounter, Price: 100000})
	second, err := svc.MakeOffer(ctx, owner, j.ID,
		OfferInput{Kind: job.OfferCounter, Price: 95000, Comment: "Могу завтра"})
	if err != nil {
		t.Fatalf("повторный отклик: %v", err)
	}

	if first.ID != second.ID {
		t.Fatal("второе предложение того же исполнителя не должно плодить карточки")
	}
	if second.Price != 95000 || second.Comment != "Могу завтра" {
		t.Fatalf("условия должны обновиться: %+v", second)
	}

	offers, _ := svc.JobOffers(ctx, client, j.ID)
	if len(offers) != 1 {
		t.Fatalf("у заказчика должен быть один отклик, получили %d", len(offers))
	}
}

func TestСчётчикОткликовСчитаетТолькоЖивые(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)

	o1, _ := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferAccept, Price: 120000})
	_, _ = svc.MakeOffer(ctx, owner2, j.ID, OfferInput{Kind: job.OfferCounter, Price: 100000})

	withTwo, _ := svc.View(ctx, client, j.ID)
	if withTwo.OffersCount != 2 {
		t.Fatalf("ожидали 2 отклика, получили %d", withTwo.OffersCount)
	}

	if _, err := svc.WithdrawOffer(ctx, owner, o1.ID); err != nil {
		t.Fatalf("отзыв: %v", err)
	}
	afterWithdraw, _ := svc.View(ctx, client, j.ID)
	if afterWithdraw.OffersCount != 1 {
		t.Fatalf("после отзыва должен остаться 1, получили %d", afterWithdraw.OffersCount)
	}
}

func TestВстречноеПредложениеТолькоОдинРаз(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)
	o, _ := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferCounter, Price: 100000})

	countered, err := svc.CounterOffer(ctx, client, o.ID, 110000)
	if err != nil {
		t.Fatalf("встречная цена: %v", err)
	}
	if countered.Status != job.OfferCounterOffered || *countered.ClientCounterPrice != 110000 {
		t.Fatalf("встречная цена не сохранилась: %+v", countered)
	}

	_, err = svc.CounterOffer(ctx, client, o.ID, 105000)
	if !errors.Is(err, job.ErrCounterUsed) {
		t.Fatalf("второй раунд торга запрещён (ТЗ §2.10), получили %v", err)
	}
}

func TestВыборИсполнителяЗакрываетОстальныеОтклики(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)
	mine, _ := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferCounter, Price: 100000})
	other, _ := svc.MakeOffer(ctx, owner2, j.ID, OfferInput{Kind: job.OfferAccept, Price: 120000})

	accepted, err := svc.AcceptOffer(ctx, client, mine.ID)
	if err != nil {
		t.Fatalf("выбор исполнителя: %v", err)
	}
	if accepted.Status != job.OfferAccepted {
		t.Fatalf("статус выбранного: %s", accepted.Status)
	}

	offers, _ := svc.JobOffers(ctx, client, j.ID)
	for _, o := range offers {
		if o.ID == other.ID && o.Status != job.OfferDeclined {
			t.Fatalf("остальные предложения должны закрыться, у %s статус %s", o.ID, o.Status)
		}
	}

	updated, _ := svc.View(ctx, client, j.ID)
	if updated.Status != job.StatusDealPending {
		t.Fatalf("после выбора задание ждёт подтверждения, получили %s", updated.Status)
	}
}

func TestПриВыбореПослеТоргаДействуетВстречнаяЦена(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)
	o, _ := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferCounter, Price: 100000})
	_, _ = svc.CounterOffer(ctx, client, o.ID, 110000)

	accepted, err := svc.AcceptOffer(ctx, client, o.ID)
	if err != nil {
		t.Fatalf("выбор: %v", err)
	}

	if accepted.Price != 110000 {
		t.Fatalf("работает цена из встречного предложения, получили %d", accepted.Price)
	}
}

func TestЧужиеОткликиНедоступны(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)
	o, _ := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferAccept, Price: 120000})

	if _, err := svc.JobOffers(ctx, owner, j.ID); !errors.Is(err, job.ErrForbidden) {
		t.Fatalf("список откликов видит только заказчик, получили %v", err)
	}
	if _, err := svc.AcceptOffer(ctx, owner2, o.ID); !errors.Is(err, job.ErrForbidden) {
		t.Fatalf("выбирать исполнителя может только заказчик, получили %v", err)
	}
	if _, err := svc.WithdrawOffer(ctx, owner2, o.ID); !errors.Is(err, job.ErrForbidden) {
		t.Fatalf("чужой отклик отозвать нельзя, получили %v", err)
	}
}

func TestНаАукционеОткликовНет(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := fullDraft(t, svc)
	_, _ = svc.UpdateDraft(ctx, client, j.ID, DraftInput{
		Mode:    mode(job.ModeAuction),
		Auction: &job.Auction{DurationH: 24, AutoExtend: true, DecisionWindowH: 12},
	})
	_, _ = svc.Publish(ctx, client, j.ID)

	_, err := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferAccept, Price: 120000})

	if !errors.Is(err, job.ErrAuctionMode) {
		t.Fatalf("на аукционе делаются ставки, получили %v", err)
	}
}

func TestНаЗакрытоеЗаданиеОткликнутьсяНельзя(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)
	_, _ = svc.Cancel(ctx, client, j.ID)

	_, err := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferAccept, Price: 120000})

	if !errors.Is(err, job.ErrJobNotOpen) {
		t.Fatalf("снятое задание откликов не принимает, получили %v", err)
	}
}

func TestВыбранныйОткликНеОтзывается(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)
	o, _ := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferAccept, Price: 120000})
	_, _ = svc.AcceptOffer(ctx, client, o.ID)

	_, err := svc.WithdrawOffer(ctx, owner, o.ID)

	if !errors.Is(err, job.ErrOfferNotActive) {
		t.Fatalf("после выбора это обязательство, а не предложение: %v", err)
	}
}

func TestМоиПредложенияИсполнителя(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j1 := published(t, svc)
	j2 := published(t, svc)
	_, _ = svc.MakeOffer(ctx, owner, j1.ID, OfferInput{Kind: job.OfferAccept, Price: 120000})
	_, _ = svc.MakeOffer(ctx, owner, j2.ID, OfferInput{Kind: job.OfferCounter, Price: 90000})

	mine, err := svc.MyOffers(ctx, owner, 20, 0)
	if err != nil {
		t.Fatalf("мои предложения: %v", err)
	}
	if len(mine) != 2 {
		t.Fatalf("ожидали 2 предложения, получили %d", len(mine))
	}
}
