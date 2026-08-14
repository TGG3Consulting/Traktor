package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"traktor/orders/internal/job"
	"traktor/orders/internal/store"
)

const (
	client = "11111111-1111-1111-1111-111111111111"
	owner  = "22222222-2222-2222-2222-222222222222"
	catID  = "c02b2502-1789-5217-be9f-d5fc04fe1cae"
)

func newSvc() *Service {
	fixed := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	return New(store.NewMemory(), func() time.Time { return fixed })
}

func s(v string) *string        { return &v }
func i64(v int64) *int64        { return &v }
func mode(v job.Mode) *job.Mode { return &v }

// fullDraft — черновик, заполненный до состояния «можно публиковать».
func fullDraft(t *testing.T, svc *Service) *job.Job {
	t.Helper()
	j, err := svc.CreateDraft(context.Background(), client, DraftInput{
		CategoryID:   s(catID),
		Title:        s("Выкопать траншею 40 м под водопровод"),
		Description:  s("Траншея вдоль забора, глубина 1,2 м, грунт мягкий, подъезд есть."),
		Geo:          &job.Geo{Lat: 40.1872, Lng: 44.5152},
		Address:      s("Ереван, Аван"),
		BudgetAmount: i64(120000),
	})
	if err != nil {
		t.Fatalf("создание черновика: %v", err)
	}
	return j
}

func TestЧерновикСоздаётсяСРазумнымиУмолчаниями(t *testing.T) {
	svc := newSvc()

	j, err := svc.CreateDraft(context.Background(), client, DraftInput{})
	if err != nil {
		t.Fatalf("не удалось создать черновик: %v", err)
	}

	if j.Status != job.StatusDraft || j.DraftStep != 1 {
		t.Fatalf("новый черновик должен быть на первом шаге: %s / %d", j.Status, j.DraftStep)
	}
	if j.Currency != "AMD" || j.Mode != job.ModeFixed || j.OrderType != job.TypeJob {
		t.Fatalf("умолчания нарушены: %s %s %s", j.Currency, j.Mode, j.OrderType)
	}
}

func TestСохранениеШагаНеЗатираетДругиеШаги(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := fullDraft(t, svc)

	// Шаг 3: меняем только место.
	updated, err := svc.UpdateDraft(ctx, client, j.ID, DraftInput{
		Address:   s("Ереван, Арабкир"),
		DraftStep: intp(3),
	})
	if err != nil {
		t.Fatalf("обновление черновика: %v", err)
	}

	if updated.Address != "Ереван, Арабкир" {
		t.Fatal("адрес не сохранился")
	}
	if updated.Title == "" || updated.BudgetAmount == nil {
		t.Fatal("сохранение одного шага затёрло данные других шагов")
	}
	if updated.DraftStep != 3 {
		t.Fatalf("шаг должен стать 3, получили %d", updated.DraftStep)
	}

	// Возврат назад по визарду не должен откатывать прогресс.
	back, _ := svc.UpdateDraft(ctx, client, j.ID, DraftInput{DraftStep: intp(2)})
	if back.DraftStep != 3 {
		t.Fatalf("прогресс визарда не должен уменьшаться: %d", back.DraftStep)
	}
}

func TestЧужойЧерновикНедоступен(t *testing.T) {
	svc := newSvc()
	j := fullDraft(t, svc)

	_, err := svc.UpdateDraft(context.Background(), owner, j.ID, DraftInput{Title: s("подмена")})

	if !errors.Is(err, job.ErrForbidden) {
		t.Fatalf("ожидали отказ по владельцу, получили %v", err)
	}
}

func TestПубликацияФиксЦеныСобираетОтклики(t *testing.T) {
	svc := newSvc()
	j := fullDraft(t, svc)

	published, err := svc.Publish(context.Background(), client, j.ID)
	if err != nil {
		t.Fatalf("публикация: %v", err)
	}

	if published.Status != job.StatusCollectingOffers {
		t.Fatalf("ожидали collecting_offers, получили %s", published.Status)
	}
	if published.PublishedAt == nil {
		t.Fatal("не проставлено время публикации")
	}
}

func TestПубликацияАукционаСчитаетФинишНаСервере(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := fullDraft(t, svc)

	if _, err := svc.UpdateDraft(ctx, client, j.ID, DraftInput{
		Mode:    mode(job.ModeAuction),
		Auction: &job.Auction{DurationH: 24, AutoExtend: true, DecisionWindowH: 12},
	}); err != nil {
		t.Fatalf("настройка аукциона: %v", err)
	}

	published, err := svc.Publish(ctx, client, j.ID)
	if err != nil {
		t.Fatalf("публикация: %v", err)
	}

	if published.Status != job.StatusBidding {
		t.Fatalf("аукцион должен уйти в торги, получили %s", published.Status)
	}
	if published.Auction == nil || published.Auction.EndsAt == nil {
		t.Fatal("сервер обязан посчитать время финиша")
	}
	want := time.Date(2026, 8, 16, 10, 0, 0, 0, time.UTC)
	if !published.Auction.EndsAt.Equal(want) {
		t.Fatalf("финиш должен быть через 24 часа (%s), получили %s", want, published.Auction.EndsAt)
	}
}

func TestНеполныйЧерновикНеПубликуется(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j, _ := svc.CreateDraft(ctx, client, DraftInput{Title: s("Что-то сделать")})

	_, err := svc.Publish(ctx, client, j.ID)

	var ve *job.ValidationError
	if !errors.As(err, &ve) {
		t.Fatalf("ожидали список незаполненных полей, получили %v", err)
	}
	if ve.Fields["description"] == "" || ve.Fields["geo"] == "" || ve.Fields["budgetAmount"] == "" {
		t.Fatalf("клиенту нужно показать все пропуски: %+v", ve.Fields)
	}
}

func TestПовторнаяПубликацияОтклоняется(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := fullDraft(t, svc)
	if _, err := svc.Publish(ctx, client, j.ID); err != nil {
		t.Fatalf("первая публикация: %v", err)
	}

	_, err := svc.Publish(ctx, client, j.ID)

	if !errors.Is(err, job.ErrNotDraft) {
		t.Fatalf("второй раз публиковать нельзя, получили %v", err)
	}
}

func TestОпубликованноеЗаданиеНеРедактируетсяКакЧерновик(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := fullDraft(t, svc)
	_, _ = svc.Publish(ctx, client, j.ID)

	_, err := svc.UpdateDraft(ctx, client, j.ID, DraftInput{BudgetAmount: i64(1)})

	if !errors.Is(err, job.ErrNotDraft) {
		t.Fatalf("условия под исполнителями менять нельзя, получили %v", err)
	}
}

func TestЛентаОтдаётТолькоОткрытыеЗаданияИСчитаетРасстояние(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	published := fullDraft(t, svc)
	_, _ = svc.Publish(ctx, client, published.ID)
	_ = fullDraft(t, svc) // остался черновиком

	lat, lng := 40.1772, 44.5052 // ~1,4 км от задания
	radius := 25000.0
	feed, err := svc.Feed(ctx, store.Filter{Lat: &lat, Lng: &lng, RadiusM: &radius, Sort: store.SortNear})
	if err != nil {
		t.Fatalf("лента: %v", err)
	}

	if len(feed) != 1 {
		t.Fatalf("в ленте должно быть одно опубликованное задание, получили %d", len(feed))
	}
	if feed[0].DistanceM == nil {
		t.Fatal("лента должна отдавать расстояние")
	}
	if *feed[0].DistanceM > 3000 {
		t.Fatalf("расстояние посчитано неверно: %.0f м", *feed[0].DistanceM)
	}
}

func TestРадиусОтсекаетДалёкиеЗадания(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := fullDraft(t, svc)
	_, _ = svc.Publish(ctx, client, j.ID)

	lat, lng := 39.0, 46.0 // далеко от Еревана
	radius := 10000.0
	feed, _ := svc.Feed(ctx, store.Filter{Lat: &lat, Lng: &lng, RadiusM: &radius})

	if len(feed) != 0 {
		t.Fatalf("за пределами радиуса заданий быть не должно, получили %d", len(feed))
	}
}

func TestПросмотрСчитаетсяОдинРазИНеСвой(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := fullDraft(t, svc)
	_, _ = svc.Publish(ctx, client, j.ID)

	// Заказчик открывает своё задание — счётчик не растёт.
	own, _ := svc.View(ctx, client, j.ID)
	if own.ViewsCount != 0 {
		t.Fatalf("свой просмотр не считается, получили %d", own.ViewsCount)
	}

	first, _ := svc.View(ctx, owner, j.ID)
	second, _ := svc.View(ctx, owner, j.ID)
	if first.ViewsCount != 1 || second.ViewsCount != 1 {
		t.Fatalf("повторный просмотр тем же человеком не должен накручивать счётчик: %d, %d",
			first.ViewsCount, second.ViewsCount)
	}
}

func TestРезервнаяЦенаСкрытаОтИсполнителя(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := fullDraft(t, svc)
	reserve := int64(70000)
	_, _ = svc.UpdateDraft(ctx, client, j.ID, DraftInput{
		Mode:    mode(job.ModeAuction),
		Auction: &job.Auction{DurationH: 24, AutoExtend: true, DecisionWindowH: 12, ReserveAmount: &reserve},
	})
	_, _ = svc.Publish(ctx, client, j.ID)

	forOwner, _ := svc.View(ctx, owner, j.ID)
	forClient, _ := svc.View(ctx, client, j.ID)

	if forOwner.Auction != nil && forOwner.Auction.ReserveAmount != nil {
		t.Fatal("исполнитель не должен видеть минимальную цену")
	}
	if forClient.Auction == nil || forClient.Auction.ReserveAmount == nil {
		t.Fatal("заказчик свою минимальную цену видеть должен")
	}
}

func TestОтменаЗаданияИЗапретПослеЗавершения(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := fullDraft(t, svc)
	_, _ = svc.Publish(ctx, client, j.ID)

	cancelled, err := svc.Cancel(ctx, client, j.ID)
	if err != nil {
		t.Fatalf("отмена: %v", err)
	}
	if cancelled.Status != job.StatusCancelled {
		t.Fatalf("ожидали cancelled, получили %s", cancelled.Status)
	}

	_, err = svc.Cancel(ctx, client, j.ID)
	if !errors.Is(err, job.ErrBadTransition) {
		t.Fatalf("отменённое повторно не отменяется, получили %v", err)
	}
}

func TestИдемпотентностьВозвращаетПрежнееЗадание(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := fullDraft(t, svc)

	if err := svc.RememberIdempotent(ctx, "key-1", client, "POST /v1/jobs", j.ID); err != nil {
		t.Fatalf("запоминание ключа: %v", err)
	}

	got, ok, err := svc.Idempotent(ctx, "key-1", client, "POST /v1/jobs")
	if err != nil || !ok || got.ID != j.ID {
		t.Fatalf("повтор с тем же ключом должен вернуть прежнее задание: %v %v %+v", err, ok, got)
	}

	// Чужой ключ того же пользователя — не найден.
	if _, ok, _ := svc.Idempotent(ctx, "key-2", client, "POST /v1/jobs"); ok {
		t.Fatal("неизвестный ключ не должен находиться")
	}
}

func intp(v int) *int { return &v }
