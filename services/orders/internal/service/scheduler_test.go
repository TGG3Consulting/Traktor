package service

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	"traktor/orders/internal/job"
)

func quietLog() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func TestПланировщикЗавершаетИстёкшийАукцион(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc, _ := svcAt(&now)
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)
	_, _ = svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000})

	// Время финиша прошло, но никто ничего не нажимал.
	now = j.Auction.EndsAt.Add(time.Minute)
	NewScheduler(svc, quietLog(), time.Minute).RunOnce(ctx)

	updated, _ := svc.View(ctx, client, j.ID)
	if updated.Status != job.StatusDeciding {
		t.Fatalf("аукцион должен закрыться сам: %s", updated.Status)
	}
}

func TestПланировщикЗакрываетЗаданиеПослеОкнаРешения(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc, _ := svcAt(&now)
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)
	_, _ = svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000})
	now = j.Auction.EndsAt.Add(time.Minute)
	finished, _ := svc.FinishAuction(ctx, j.ID)

	now = finished.DecisionDeadline.Add(time.Minute)
	NewScheduler(svc, quietLog(), time.Minute).RunOnce(ctx)

	updated, _ := svc.View(ctx, client, j.ID)
	if updated.Status != job.StatusExpired {
		t.Fatalf("молчание заказчика должно закрыть задание: %s", updated.Status)
	}
}

func TestПланировщикПринимаетРаботуЧерез48Часов(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc, _ := svcAt(&now)
	ctx := context.Background()
	j, _ := dealReady(t, svc)
	d, _ := svc.ConfirmDeal(ctx, client, j.ID)
	_, _ = svc.AdvanceDeal(ctx, owner, d.ID, job.DealInProgress, "")
	done, _ := svc.AdvanceDeal(ctx, owner, d.ID, job.DealWorkDone, "")

	// Заказчик молчит дольше срока приёмки.
	now = done.AcceptanceDeadline.Add(time.Hour)
	NewScheduler(svc, quietLog(), time.Minute).RunOnce(ctx)

	deal, err := svc.Deal(ctx, client, d.ID)
	if err != nil {
		t.Fatalf("чтение сделки: %v", err)
	}
	if deal.Status != job.DealCompleted {
		t.Fatalf("работа должна быть принята автоматически: %s", deal.Status)
	}
	last := deal.Timeline[len(deal.Timeline)-1]
	if last.Note == "" {
		t.Fatal("в истории должно быть видно, что приёмка автоматическая")
	}
}

func TestПланировщикНеТрогаетТоЧтоЕщёНеИстекло(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc, _ := svcAt(&now)
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)
	_, _ = svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000})

	// До финиша ещё почти сутки.
	NewScheduler(svc, quietLog(), time.Minute).RunOnce(ctx)

	updated, _ := svc.View(ctx, client, j.ID)
	if updated.Status != job.StatusBidding {
		t.Fatalf("идущий торг трогать нельзя: %s", updated.Status)
	}
}
