package job

import (
	"errors"
	"testing"
	"time"
)

func auctionJob(endsIn time.Duration, now time.Time) *Job {
	ends := now.Add(endsIn)
	return &Job{
		Mode:   ModeAuction,
		Status: StatusBidding,
		Auction: &Auction{
			DurationH: 24, AutoExtend: true, DecisionWindowH: 12, EndsAt: &ends,
		},
	}
}

func TestСтавкаДолжнаБытьНижеЛучшей(t *testing.T) {
	if err := ValidateBid(90000, 100000, 120000); err != nil {
		t.Fatalf("ставка ниже лучшей должна проходить: %v", err)
	}

	var ve *ValidationError
	if !errors.As(ValidateBid(100000, 100000, 120000), &ve) {
		t.Fatal("равная лучшей ставка — не торг")
	}
	if !errors.As(ValidateBid(110000, 100000, 120000), &ve) {
		t.Fatal("ставка выше лучшей в обратном аукционе бессмысленна")
	}
}

func TestПерваяСтавкаМожетБытьЛюбойВышеПорога(t *testing.T) {
	if err := ValidateBid(119000, 0, 120000); err != nil {
		t.Fatalf("первая ставка ниже стартовой цены допустима: %v", err)
	}
}

func TestАнтидемпингОтсекаетСлишкомНизкие(t *testing.T) {
	var ve *ValidationError
	if !errors.As(ValidateBid(30000, 0, 120000), &ve) || ve.Fields["price"] == "" {
		t.Fatal("ставка ниже трети стартовой отсекается")
	}
}

func TestСтавкиПринимаютсяТолькоВИдущемАукционе(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)

	if err := CanBid(auctionJob(2*time.Hour, now), now); err != nil {
		t.Fatalf("идущий аукцион принимает ставки: %v", err)
	}
	if !errors.Is(CanBid(auctionJob(-time.Minute, now), now), ErrAuctionClosed) {
		t.Fatal("после финиша ставки не принимаются")
	}

	fixed := &Job{Mode: ModeFixed, Status: StatusCollectingOffers}
	if !errors.Is(CanBid(fixed, now), ErrNotAuction) {
		t.Fatal("на фикс-цене делают отклики, а не ставки")
	}
}

func TestАнтиснайпингПродлеваетТолькоВПоследниеМинуты(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)

	if ShouldExtend(auctionJob(time.Hour, now), now) {
		t.Fatal("за час до финиша продлевать нечего")
	}
	if !ShouldExtend(auctionJob(3*time.Minute, now), now) {
		t.Fatal("ставка за 3 минуты до конца должна продлевать торг")
	}

	noExtend := auctionJob(3*time.Minute, now)
	noExtend.Auction.AutoExtend = false
	if ShouldExtend(noExtend, now) {
		t.Fatal("если заказчик выключил автопродление, торг не продлевается")
	}
}

func TestОтзывСтавкиЗапрещёнНаФинишнойПрямой(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)

	if err := CanWithdrawBid(auctionJob(5*time.Hour, now), now); err != nil {
		t.Fatalf("за 5 часов до финиша отзыв разрешён: %v", err)
	}
	if !errors.Is(CanWithdrawBid(auctionJob(time.Hour, now), now), ErrBidTooLate) {
		t.Fatal("за час до финиша отзывать нельзя (ТЗ §2.9)")
	}
}

func TestСкорингУчитываетЦенуРейтингИБлизость(t *testing.T) {
	items := []BidScore{
		{Bid: Bid{ID: "дорогой-но-лучший", Price: 100000}, Rating: 5, DistanceM: 1000, UnitMatch: true},
		{Bid: Bid{ID: "дешёвый-новичок", Price: 80000}, Rating: 0, DistanceM: 50000, UnitMatch: false},
	}

	scored := Score(items, nil)

	if len(scored) != 2 {
		t.Fatalf("обе ставки должны попасть в расчёт: %d", len(scored))
	}
	// Дешёвый выигрывает по цене (0.6), но проигрывает по рейтингу и близости.
	// Проверяем не конкретные числа, а что оценка посчитана и список отсортирован.
	if scored[0].Bid.Score == nil || scored[1].Bid.Score == nil {
		t.Fatal("оценка должна быть у каждой ставки")
	}
	if *scored[0].Bid.Score < *scored[1].Bid.Score {
		t.Fatal("список должен идти от лучшего к худшему")
	}
}

func TestСтавкиНижеРезерваНеУчаствуют(t *testing.T) {
	reserve := int64(70000)
	items := []BidScore{
		{Bid: Bid{ID: "ниже-резерва", Price: 60000}, Rating: 5},
		{Bid: Bid{ID: "нормальная", Price: 90000}, Rating: 4},
	}

	scored := Score(items, &reserve)

	if len(scored) != 1 || scored[0].Bid.ID != "нормальная" {
		t.Fatalf("ставки ниже резерва в расчёт не идут: %+v", scored)
	}
}

func TestОднаСтавкаПолучаетМаксимумПоЦене(t *testing.T) {
	items := []BidScore{{Bid: Bid{ID: "единственная", Price: 90000}, Rating: 5, UnitMatch: true}}

	scored := Score(items, nil)

	if len(scored) != 1 || scored[0].Bid.Score == nil {
		t.Fatal("единственная ставка должна получить оценку")
	}
	if *scored[0].Bid.Score < 0.9 {
		t.Fatalf("сравнивать не с чем — цена получает максимум: %f", *scored[0].Bid.Score)
	}
}
