package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"traktor/orders/internal/job"
	"traktor/orders/internal/store"
	"traktor/orders/internal/units"
)

// Техника в откликах и ставках (ТЗ §2.5, §2.9): ставка «подтверждена машиной»
// только если машина действительно своя и опубликована.

type fakeUnits map[string]units.Unit

func (f fakeUnits) ByID(_ context.Context, id string) (units.Unit, bool) {
	u, ok := f[id]
	return u, ok
}

func svcWithUnits(catalog fakeUnits) *Service {
	fixed := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	return NewWithUnits(store.NewMemory(), func() time.Time { return fixed }, nil, nil, catalog)
}

func TestОткликСвоейАктивнойТехникой(t *testing.T) {
	svc := svcWithUnits(fakeUnits{
		"u-1": {ID: "u-1", OwnerID: owner, Active: true, Status: "verified"},
	})
	ctx := context.Background()
	j := published(t, svc)
	unit := "u-1"

	o, err := svc.MakeOffer(ctx, owner, j.ID, OfferInput{
		Kind: job.OfferAccept, Price: 120000, UnitID: &unit,
	})
	if err != nil {
		t.Fatalf("отклик своей техникой: %v", err)
	}
	if o.UnitID == nil || *o.UnitID != unit {
		t.Fatalf("техника должна сохраниться в отклике: %+v", o.UnitID)
	}
}

func TestЧужойТехникойОткликнутьсяНельзя(t *testing.T) {
	svc := svcWithUnits(fakeUnits{
		"u-1": {ID: "u-1", OwnerID: "someone-else", Active: true},
	})
	ctx := context.Background()
	j := published(t, svc)
	unit := "u-1"

	_, err := svc.MakeOffer(ctx, owner, j.ID, OfferInput{
		Kind: job.OfferAccept, Price: 120000, UnitID: &unit,
	})

	if !errors.Is(err, job.ErrUnitForeign) {
		t.Fatalf("чужой машиной откликаться нельзя: %v", err)
	}
}

func TestНеопубликованнойТехникойОткликнутьсяНельзя(t *testing.T) {
	svc := svcWithUnits(fakeUnits{
		"u-1": {ID: "u-1", OwnerID: owner, Active: false, Status: "draft"},
	})
	ctx := context.Background()
	j := published(t, svc)
	unit := "u-1"

	_, err := svc.MakeOffer(ctx, owner, j.ID, OfferInput{
		Kind: job.OfferAccept, Price: 120000, UnitID: &unit,
	})

	if !errors.Is(err, job.ErrUnitInactive) {
		t.Fatalf("черновиком карточки откликаться нельзя: %v", err)
	}
}

func TestБезТехникиОткликВозможен(t *testing.T) {
	svc := svcWithUnits(fakeUnits{})
	ctx := context.Background()
	j := published(t, svc)

	// Часть заданий открыта «исполнитель предложит технику» — там машину
	// указывать незачем, и отклик всё равно должен пройти.
	if _, err := svc.MakeOffer(ctx, owner, j.ID, OfferInput{
		Kind: job.OfferAccept, Price: 120000,
	}); err != nil {
		t.Fatalf("отклик без техники: %v", err)
	}
}

func TestНедоступныйКаталогНеБлокируетОтклик(t *testing.T) {
	// Каталог не ответил — справки нет. Ронять отклик из-за этого нельзя:
	// человек не виноват, что у нас сеть моргнула.
	svc := svcWithUnits(fakeUnits{})
	ctx := context.Background()
	j := published(t, svc)
	unit := "unknown"

	if _, err := svc.MakeOffer(ctx, owner, j.ID, OfferInput{
		Kind: job.OfferAccept, Price: 120000, UnitID: &unit,
	}); err != nil {
		t.Fatalf("недоступный каталог не должен мешать: %v", err)
	}
}

func TestСтавкаПроверяетТехникуТакЖе(t *testing.T) {
	svc := svcWithUnits(fakeUnits{
		"u-1": {ID: "u-1", OwnerID: "someone-else", Active: true},
	})
	ctx := context.Background()
	j := auctionPublished(t, svc, nil)
	unit := "u-1"

	_, err := svc.PlaceBid(ctx, owner, j.ID, BidInput{Price: 100000, UnitID: &unit})

	if !errors.Is(err, job.ErrUnitForeign) {
		t.Fatalf("на аукционе правило то же: %v", err)
	}
}
