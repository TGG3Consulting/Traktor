package job

import (
	"errors"
	"testing"
	"time"
)

func valid() *Job {
	cat := "c02b2502-1789-5217-be9f-d5fc04fe1cae"
	amount := int64(120000)
	return &Job{
		ClientID:     "11111111-1111-1111-1111-111111111111",
		OrderType:    TypeJob,
		CategoryID:   &cat,
		Title:        "Выкопать траншею 40 м под водопровод",
		Description:  "Траншея вдоль забора, глубина 1,2 м, грунт мягкий, подъезд есть.",
		Geo:          &Geo{Lat: 40.1872, Lng: 44.5152},
		Address:      "Ереван, Аван",
		DateMode:     DateASAP,
		BudgetAmount: &amount,
		Currency:     "AMD",
		Mode:         ModeFixed,
		Params:       map[string]any{},
		Photos:       []string{},
	}
}

func TestПравильноеЗаданиеПроходитПроверку(t *testing.T) {
	if err := valid().ValidateForPublish(); err != nil {
		t.Fatalf("ожидали успех, получили: %v", err)
	}
}

func TestКороткоеОписаниеНеПропускается(t *testing.T) {
	j := valid()
	j.Description = "копать"

	err := j.ValidateForPublish()

	if !errors.Is(err, ErrValidation) {
		t.Fatalf("ожидали ошибку валидации, получили %v", err)
	}
	var ve *ValidationError
	if !errors.As(err, &ve) || ve.Fields["description"] == "" {
		t.Fatalf("ошибка должна указывать на поле description: %+v", err)
	}
}

func TestБезМестаИЦеныНеПубликуем(t *testing.T) {
	j := valid()
	j.Geo = nil
	j.BudgetAmount = nil

	var ve *ValidationError
	if !errors.As(j.ValidateForPublish(), &ve) {
		t.Fatal("ожидали ValidationError")
	}
	if ve.Fields["geo"] == "" || ve.Fields["budgetAmount"] == "" {
		t.Fatalf("должны быть отмечены оба поля: %+v", ve.Fields)
	}
}

func TestКатегорияИлиОткрытыйЗапрос(t *testing.T) {
	j := valid()
	j.CategoryID = nil

	var ve *ValidationError
	if !errors.As(j.ValidateForPublish(), &ve) || ve.Fields["categoryId"] == "" {
		t.Fatal("без категории и без openToAny публиковать нельзя")
	}

	// «Опишу задачу — пусть исполнители сами предложат технику» (§2.6 шаг 1).
	j.OpenToAny = true
	if err := j.ValidateForPublish(); err != nil {
		t.Fatalf("с openToAny категория не нужна: %v", err)
	}
}

func TestАукционПроверяетДлительностьИРезерв(t *testing.T) {
	j := valid()
	j.Mode = ModeAuction
	j.Auction = &Auction{DurationH: 500, DecisionWindowH: 12}

	var ve *ValidationError
	if !errors.As(j.ValidateForPublish(), &ve) || ve.Fields["auction.durationH"] == "" {
		t.Fatal("длительность больше 7 дней должна отклоняться")
	}

	reserve := int64(200000) // выше стартовых 120 000
	j.Auction = &Auction{DurationH: 24, DecisionWindowH: 12, ReserveAmount: &reserve}
	if !errors.As(j.ValidateForPublish(), &ve) || ve.Fields["auction.reserveAmount"] == "" {
		t.Fatal("резерв выше стартовой цены должен отклоняться: торг невозможен")
	}

	ok := int64(70000)
	j.Auction = &Auction{DurationH: 24, DecisionWindowH: 12, ReserveAmount: &ok}
	if err := j.ValidateForPublish(); err != nil {
		t.Fatalf("корректный аукцион должен проходить: %v", err)
	}
}

func TestДиапазонДатПроверяетПорядок(t *testing.T) {
	j := valid()
	j.DateMode = DateRange
	start := time.Date(2026, 8, 20, 9, 0, 0, 0, time.UTC)
	end := start.Add(-24 * time.Hour)
	j.DateStart, j.DateEnd = &start, &end

	var ve *ValidationError
	if !errors.As(j.ValidateForPublish(), &ve) || ve.Fields["dates"] == "" {
		t.Fatal("конец раньше начала должен отклоняться")
	}
}

func TestСтатусПослеПубликацииЗависитОтРежима(t *testing.T) {
	if StatusAfterPublish(ModeFixed) != StatusCollectingOffers {
		t.Fatal("фикс-цена должна собирать отклики")
	}
	if StatusAfterPublish(ModeAuction) != StatusBidding {
		t.Fatal("аукцион должен сразу идти в торги")
	}
}

func TestМатрицаПереходов(t *testing.T) {
	cases := []struct {
		from, to Status
		want     bool
	}{
		{StatusDraft, StatusPublished, true},
		{StatusBidding, StatusDeciding, true},
		{StatusBidding, StatusExpiredNoBids, true},
		{StatusDeciding, StatusConfirmed, true},
		{StatusDeciding, StatusDeclinedAll, true},
		{StatusCompleted, StatusInProgress, false}, // назад из завершённого нельзя
		{StatusDraft, StatusConfirmed, false},      // нельзя перепрыгнуть публикацию
		{StatusCancelled, StatusPublished, false},  // отменённое не воскрешаем
	}
	for _, c := range cases {
		if got := CanTransition(c.from, c.to); got != c.want {
			t.Errorf("переход %s → %s: получили %v, ожидали %v", c.from, c.to, got, c.want)
		}
	}
}
