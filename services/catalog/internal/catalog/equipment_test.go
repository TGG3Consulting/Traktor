package catalog

import (
	"errors"
	"testing"
	"time"
)

var now = time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)

func full() *Equipment {
	year := 2019
	return &Equipment{
		OwnerID:    "u1",
		CategoryID: "c1",
		Brand:      "JCB",
		Model:      "3CX",
		Year:       &year,
		Photos:     []string{"p1.jpg"},
	}
}

func TestКарточкуБезФотоНеПубликуем(t *testing.T) {
	e := full()
	e.Photos = nil

	err := ValidateForPublish(e, now)

	var ve *ValidationError
	if !errors.As(err, &ve) || ve.Fields["photos"] == "" {
		t.Fatalf("без фото карточка в ленте откликов выглядит пустой: %v", err)
	}
}

func TestГодПроверяетсяПоЗдравомуСмыслу(t *testing.T) {
	e := full()
	future := now.Year() + 1
	e.Year = &future

	err := ValidateForPublish(e, now)

	var ve *ValidationError
	if !errors.As(err, &ve) || ve.Fields["year"] == "" {
		t.Fatalf("техники из будущего не бывает: %v", err)
	}
}

func TestПолнаяКарточкаПроходит(t *testing.T) {
	if err := ValidateForPublish(full(), now); err != nil {
		t.Fatalf("заполненная карточка должна публиковаться: %v", err)
	}
}

func TestБезДокументовПубликуетсяСразу(t *testing.T) {
	if got := StatusAfterSubmit(false); got != StatusUnverified {
		t.Fatalf("без документов техника работает, но без бейджа: %s", got)
	}
	if got := StatusAfterSubmit(true); got != StatusPending {
		t.Fatalf("с документами уходит на проверку: %s", got)
	}
}

func TestНаПроверкеКарточкуНеПравят(t *testing.T) {
	e := full()
	e.Status = StatusPending

	if err := CanEdit(e, "u1"); !errors.Is(err, ErrEquipmentStatus) {
		t.Fatalf("пока модерация смотрит, менять данные нельзя: %v", err)
	}
}

func TestЧужуюТехникуНеПравят(t *testing.T) {
	if err := CanEdit(full(), "u2"); !errors.Is(err, ErrEquipmentForeign) {
		t.Fatalf("чужая карточка недоступна: %v", err)
	}
}

func TestNormalizeУбираетМусор(t *testing.T) {
	e := full()
	neg := int64(-100)
	huge := 999
	e.PriceHour = &neg
	e.CrewSize = 500
	e.MinHours = &huge
	e.Photos = []string{"1", "2", "3", "4", "5", "6", "7", "8", "9", "10"}

	Normalize(e)

	if e.PriceHour != nil {
		t.Fatal("отрицательный тариф — это отсутствие тарифа")
	}
	if e.CrewSize != 20 {
		t.Fatalf("бригада в 500 человек — опечатка: %d", e.CrewSize)
	}
	if *e.MinHours != 24 {
		t.Fatalf("минимальный заказ ограничен сутками: %d", *e.MinHours)
	}
	if len(e.Photos) != 8 {
		t.Fatalf("фото не больше восьми: %d", len(e.Photos))
	}
}

func TestАктивнаяТехникаУчаствуетВОткликах(t *testing.T) {
	cases := map[Status]bool{
		StatusVerified:   true,
		StatusUnverified: true,
		StatusDraft:      false,
		StatusPending:    false,
		StatusRejected:   false,
		StatusArchived:   false,
	}
	for status, want := range cases {
		e := full()
		e.Status = status
		if e.Active() != want {
			t.Fatalf("%s: активность должна быть %v", status, want)
		}
	}
}

func TestНазваниеСобираетсяИзМаркиИМодели(t *testing.T) {
	if got := full().Title(); got != "JCB 3CX" {
		t.Fatalf("название машины: %q", got)
	}
}
