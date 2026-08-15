package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"traktor/orders/internal/job"
	"traktor/orders/internal/store"
)

// auctionPublished — опубликованный аукцион со стартовой ценой 120 000.
func auctionPublished(t *testing.T, svc *Service, reserve *int64) *job.Job {
	t.Helper()
	ctx := context.Background()
	j := fullDraft(t, svc)
	if _, err := svc.UpdateDraft(ctx, client, j.ID, DraftInput{
		Mode: mode(job.ModeAuction),
		Auction: &job.Auction{
			DurationH: 24, AutoExtend: true, DecisionWindowH: 12, ReserveAmount: reserve,
		},
	}); err != nil {
		t.Fatalf("настройка аукциона: %v", err)
	}
	p, err := svc.Publish(ctx, client, j.ID)
	if err != nil {
		t.Fatalf("публикация: %v", err)
	}
	return p
}

// svcAt — сервис с управляемым временем: аукцион весь про время, и без этого
// нельзя проверить ни антиснайпинг, ни запрет отзыва на финише.
func svcAt(now *time.Time) (*Service, *recorder) {
	rec := &recorder{}
	return NewWithNotifier(store.NewMemory(), func() time.Time { return *now }, rec), rec
}

func TestСтавкаДолжнаСнижатьЦену(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)

	first, err := svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000})
	if err != nil {
		t.Fatalf("первая ставка: %v", err)
	}
	if first.Status != job.BidActive {
		t.Fatalf("новая ставка активна: %s", first.Status)
	}

	// Второй участник обязан предложить меньше.
	if _, err := svc.PlaceBid(ctx, owner2, j.ID, BidInput{Price: 110000}); !errors.Is(err, job.ErrValidation) {
		t.Fatalf("ставка выше лучшей должна отклоняться: %v", err)
	}
	if _, err := svc.PlaceBid(ctx, owner2, j.ID, BidInput{Price: 95000}); err != nil {
		t.Fatalf("ставка ниже лучшей: %v", err)
	}
}

func TestСвоюСтавкуМожноСнижатьБезОглядкиНаСебя(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)
	_, _ = svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000})

	second, err := svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 90000})
	if err != nil {
		t.Fatalf("исполнитель должен мочь снизить свою цену: %v", err)
	}

	bids, _ := svc.JobBids(ctx, j.ID)
	active := 0
	for _, b := range bids {
		if b.Status == job.BidActive {
			active++
		}
	}
	if active != 1 || second.Price != 90000 {
		t.Fatalf("у исполнителя должна остаться одна действующая ставка: %d", active)
	}
}

func TestНаСвоёЗаданиеСтавитьНельзя(t *testing.T) {
	svc := newSvc()
	j := auctionPublished(t, svc, nil)

	_, err := svc.PlaceBid(context.Background(), client, j.ID, BidInput{Price: 100000})

	if !errors.Is(err, job.ErrOwnJob) {
		t.Fatalf("ожидали запрет: %v", err)
	}
}

func TestСтавкаВПоследниеМинутыПродлеваетТорг(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc, _ := svcAt(&now)
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)
	endsBefore := *j.Auction.EndsAt

	// Перематываем время: до финиша осталось 3 минуты.
	now = endsBefore.Add(-3 * time.Minute)
	if _, err := svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000}); err != nil {
		t.Fatalf("ставка: %v", err)
	}

	updated, _ := svc.View(ctx, client, j.ID)
	if !updated.Auction.EndsAt.After(endsBefore) {
		t.Fatal("ставка в последние минуты должна продлевать торг (антиснайпинг)")
	}
	if updated.Auction.EndsAt.Sub(endsBefore) != job.ExtendBy {
		t.Fatalf("продление должно быть на %v, получили %v",
			job.ExtendBy, updated.Auction.EndsAt.Sub(endsBefore))
	}
}

func TestПослеФинишаСтавкиНеПринимаются(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc, _ := svcAt(&now)
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)

	now = j.Auction.EndsAt.Add(time.Minute)
	_, err := svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000})

	if !errors.Is(err, job.ErrAuctionClosed) {
		t.Fatalf("после финиша торг закрыт: %v", err)
	}
}

func TestОтзывСтавкиЗапрещёнЗаДваЧасаДоФиниша(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc, _ := svcAt(&now)
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)
	b, _ := svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000})

	now = j.Auction.EndsAt.Add(-time.Hour)
	_, err := svc.WithdrawBid(ctx, owner, b.ID)

	if !errors.Is(err, job.ErrBidTooLate) {
		t.Fatalf("на финишной прямой ставку не снять: %v", err)
	}
}

func TestФинишВыбираетЛучшуюСтавкуИОткрываетОкноРешения(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)
	_, _ = svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000})
	best, _ := svc.PlaceBid(ctx, owner2, j.ID, BidInput{Price: 90000})

	finished, err := svc.FinishAuction(ctx, j.ID)
	if err != nil {
		t.Fatalf("финиш: %v", err)
	}

	if finished.Status != job.StatusDeciding {
		t.Fatalf("после финиша заказчик выбирает: %s", finished.Status)
	}
	if finished.WinnerBidID == nil || *finished.WinnerBidID != best.ID {
		t.Fatal("лучшей должна стать самая низкая ставка")
	}
	if finished.DecisionDeadline == nil {
		t.Fatal("окно решения должно быть ограничено по времени")
	}
}

func TestФинишБезСтавокЗакрываетЗадание(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)

	finished, err := svc.FinishAuction(ctx, j.ID)

	if err != nil {
		t.Fatalf("финиш: %v", err)
	}
	if finished.Status != job.StatusExpiredNoBids {
		t.Fatalf("без ставок задание закрывается: %s", finished.Status)
	}
}

func TestСтавкиНижеРезерваНеДаютПобедителя(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	reserve := int64(100000)
	j := auctionPublished(t, svc, &reserve)
	_, _ = svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 90000}) // ниже резерва

	finished, _ := svc.FinishAuction(ctx, j.ID)

	if finished.Status != job.StatusExpiredNoBids {
		t.Fatalf("ставки ниже минимальной цены не считаются: %s", finished.Status)
	}
}

func TestВыборПобедителяЗакрываетОстальныеСтавки(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)
	loser, _ := svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000})
	winner, _ := svc.PlaceBid(ctx, owner2, j.ID, BidInput{Price: 90000})
	_, _ = svc.FinishAuction(ctx, j.ID)

	accepted, err := svc.AcceptBid(ctx, client, winner.ID)
	if err != nil {
		t.Fatalf("выбор победителя: %v", err)
	}
	if accepted.Status != job.BidWon {
		t.Fatalf("статус победителя: %s", accepted.Status)
	}

	bids, _ := svc.JobBids(ctx, j.ID)
	for _, b := range bids {
		if b.ID == loser.ID && b.Status != job.BidLost {
			t.Fatalf("проигравшая ставка должна закрыться: %s", b.Status)
		}
	}
	updated, _ := svc.View(ctx, client, j.ID)
	if updated.Status != job.StatusDealPending {
		t.Fatalf("дальше — подтверждение сделки: %s", updated.Status)
	}
}

func TestЗаказчикМожетОтказатьсяОтВсехСтавок(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)
	_, _ = svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000})
	_, _ = svc.FinishAuction(ctx, j.ID)

	closed, err := svc.DeclineAllBids(ctx, client, j.ID)

	if err != nil {
		t.Fatalf("отказ от всех: %v", err)
	}
	if closed.Status != job.StatusDeclinedAll {
		t.Fatalf("задание закрывается: %s", closed.Status)
	}
}

func TestМолчаниеВОкнеРешенияЗакрываетЗадание(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc, _ := svcAt(&now)
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)
	_, _ = svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000})
	finished, _ := svc.FinishAuction(ctx, j.ID)

	// Раньше срока ничего не происходит.
	if before, _ := svc.ExpireDecision(ctx, j.ID); before.Status != job.StatusDeciding {
		t.Fatalf("до истечения окна задание ждёт решения: %s", before.Status)
	}

	now = finished.DecisionDeadline.Add(time.Minute)
	expired, err := svc.ExpireDecision(ctx, j.ID)

	if err != nil {
		t.Fatalf("истечение окна: %v", err)
	}
	if expired.Status != job.StatusExpired {
		t.Fatalf("молчание закрывает задание: %s", expired.Status)
	}
}

func TestУчастникиУзнаютОПеребитойСтавкеИФинише(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc, rec := svcAt(&now)
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)
	_, _ = svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000})
	_, _ = svc.PlaceBid(ctx, owner2, j.ID, BidInput{Price: 90000})

	outbid := rec.to(owner)
	if len(outbid) == 0 {
		t.Fatal("того, чью ставку перебили, надо предупредить")
	}

	_, _ = svc.FinishAuction(ctx, j.ID)
	if len(rec.to(owner2)) == 0 {
		t.Fatal("участники должны узнать об итогах торга")
	}
}
