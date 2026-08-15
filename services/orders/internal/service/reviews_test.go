package service

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"traktor/orders/internal/job"
	"traktor/orders/internal/store"
)

// completed — сделка, доведённая до «работа принята»: только после этого
// открывается взаимная оценка (ТЗ §2.13).
func completed(t *testing.T, svc *Service) *job.Deal {
	t.Helper()
	ctx := context.Background()
	j, _ := dealReady(t, svc)

	d, err := svc.ConfirmDeal(ctx, client, j.ID)
	if err != nil {
		t.Fatalf("подтверждение сделки: %v", err)
	}
	for _, step := range []struct {
		to  job.DealStatus
		who string
	}{
		{job.DealOnTheWay, owner},
		{job.DealInProgress, owner},
		{job.DealWorkDone, owner},
		{job.DealCompleted, client},
	} {
		if _, err := svc.AdvanceDeal(ctx, step.who, d.ID, step.to, ""); err != nil {
			t.Fatalf("шаг %s: %v", step.to, err)
		}
	}
	done, err := svc.Deal(ctx, client, d.ID)
	if err != nil {
		t.Fatalf("сделка: %v", err)
	}
	return done
}

func TestОценкаТолькоПослеЗавершения(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j, _ := dealReady(t, svc)
	d, _ := svc.ConfirmDeal(ctx, client, j.ID)

	_, err := svc.LeaveReview(ctx, client, d.ID, job.Review{Stars: 5})

	if !errors.Is(err, job.ErrReviewTooEarly) {
		t.Fatalf("незавершённую работу оценивать рано: %v", err)
	}
}

func TestПостороннийНеОценивает(t *testing.T) {
	svc := newSvc()
	d := completed(t, svc)

	_, err := svc.LeaveReview(context.Background(), owner2, d.ID, job.Review{Stars: 1})

	if !errors.Is(err, job.ErrReviewForbidden) {
		t.Fatalf("оценивать может только участник: %v", err)
	}
}

func TestПерваяОценкаСкрытаДоОтветаВторойСтороны(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := completed(t, svc)

	mine, err := svc.LeaveReview(ctx, client, d.ID, job.Review{
		Stars: 5,
		Tags:  []string{"Пунктуально", "Аккуратно"},
		Text:  "Приехал вовремя, участок выровнял идеально",
	})
	if err != nil {
		t.Fatalf("оценка: %v", err)
	}
	if mine.Published() {
		t.Fatal("одинокая оценка не должна публиковаться сразу — иначе вторая сторона подстроит свою")
	}

	// Посторонний ничего не видит, пока отзыв скрыт.
	about, summary, err := svc.ReviewsAbout(ctx, owner, 20, 0)
	if err != nil {
		t.Fatalf("отзывы о человеке: %v", err)
	}
	if len(about) != 0 || summary.Count != 0 {
		t.Fatalf("скрытый отзыв не должен попадать в карточку: %+v", about)
	}
}

func TestВстречнаяОценкаОткрываетОбе(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := completed(t, svc)

	if _, err := svc.LeaveReview(ctx, client, d.ID, job.Review{Stars: 5}); err != nil {
		t.Fatalf("оценка заказчика: %v", err)
	}
	theirs, err := svc.LeaveReview(ctx, owner, d.ID, job.Review{
		Stars: 4,
		Tags:  []string{"Чёткое ТЗ"},
	})
	if err != nil {
		t.Fatalf("оценка исполнителя: %v", err)
	}

	if !theirs.Published() {
		t.Fatal("вторая оценка публикуется сразу")
	}
	aboutOwner, summary, _ := svc.ReviewsAbout(ctx, owner, 20, 0)
	if len(aboutOwner) != 1 || summary.Rating != 5 || summary.Count != 1 {
		t.Fatalf("отзыв об исполнителе должен открыться: %+v %+v", aboutOwner, summary)
	}
	aboutClient, _, _ := svc.ReviewsAbout(ctx, client, 20, 0)
	if len(aboutClient) != 1 {
		t.Fatal("вместе с ним открывается и отзыв о заказчике")
	}
}

func TestДваждыОценитьНельзя(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := completed(t, svc)

	if _, err := svc.LeaveReview(ctx, client, d.ID, job.Review{Stars: 5}); err != nil {
		t.Fatalf("оценка: %v", err)
	}
	_, err := svc.LeaveReview(ctx, client, d.ID, job.Review{Stars: 1})

	if !errors.Is(err, job.ErrReviewTwice) {
		t.Fatalf("вторая оценка по той же сделке недопустима: %v", err)
	}
}

func TestОтметкиПроверяютсяПоРоли(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := completed(t, svc)

	// «Чёткое ТЗ» — про заказчика; заказчик так исполнителя не отметит.
	_, err := svc.LeaveReview(ctx, client, d.ID, job.Review{
		Stars: 5,
		Tags:  []string{"Чёткое ТЗ"},
	})

	if !errors.Is(err, job.ErrReviewTag) {
		t.Fatalf("чужие отметки не принимаются: %v", err)
	}
}

func TestЗвёздыОбязательны(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := completed(t, svc)

	_, err := svc.LeaveReview(ctx, client, d.ID, job.Review{Text: "всё хорошо"})

	if !errors.Is(err, job.ErrReviewStars) {
		t.Fatalf("оценка без звёзд бессмысленна: %v", err)
	}
}

func TestОдинокаяОценкаОткрываетсяЧерезНеделю(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	svc := New(store.NewMemory(), func() time.Time { return now })
	ctx := context.Background()
	d := completed(t, svc)

	if _, err := svc.LeaveReview(ctx, client, d.ID, job.Review{Stars: 5}); err != nil {
		t.Fatalf("оценка: %v", err)
	}

	// Шесть дней — ещё рано.
	now = now.Add(6 * 24 * time.Hour)
	if err := svc.publishDueReviews(ctx); err != nil {
		t.Fatalf("публикация: %v", err)
	}
	if about, _, _ := svc.ReviewsAbout(ctx, owner, 20, 0); len(about) != 0 {
		t.Fatal("до срока отзыв остаётся скрытым")
	}

	// Через неделю ожидание заканчивается.
	now = now.Add(2 * 24 * time.Hour)
	if err := svc.publishDueReviews(ctx); err != nil {
		t.Fatalf("публикация: %v", err)
	}
	about, summary, _ := svc.ReviewsAbout(ctx, owner, 20, 0)
	if len(about) != 1 || summary.Count != 1 {
		t.Fatalf("молчание второй стороны не должно прятать честный отзыв навсегда: %+v", about)
	}
}

func TestОтветНаОтзывОдинРаз(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	d := completed(t, svc)
	_, _ = svc.LeaveReview(ctx, client, d.ID, job.Review{Stars: 2, Text: "опоздал"})
	mine, _ := svc.LeaveReview(ctx, owner, d.ID, job.Review{Stars: 5})
	_ = mine

	about, _, _ := svc.ReviewsAbout(ctx, owner, 20, 0)
	if len(about) != 1 {
		t.Fatalf("отзыв должен быть опубликован: %+v", about)
	}
	target := about[0]

	// Отвечает тот, о ком отзыв.
	if _, err := svc.ReplyToReview(ctx, client, target.ID, "разберёмся"); !errors.Is(err, job.ErrReplyForeign) {
		t.Fatalf("отвечать может только тот, кого оценили: %v", err)
	}
	replied, err := svc.ReplyToReview(ctx, owner, target.ID, "Задержался из-за перекрытого моста, предупредил заранее")
	if err != nil {
		t.Fatalf("ответ: %v", err)
	}
	if !strings.Contains(replied.ReplyText, "моста") || replied.ReplyAt == nil {
		t.Fatalf("ответ должен сохраниться: %+v", replied)
	}

	if _, err := svc.ReplyToReview(ctx, owner, target.ID, "и ещё"); !errors.Is(err, job.ErrReplyTwice) {
		t.Fatalf("второй ответ недопустим: %v", err)
	}
}

func TestНизкаяОценкаСпрашиваетЧтоПошлоНеТак(t *testing.T) {
	if !job.AsksWhatWentWrong(2) {
		t.Fatal("ниже трёх звёзд — повод спросить, что случилось")
	}
	if job.AsksWhatWentWrong(4) {
		t.Fatal("на хорошую оценку лишних вопросов не задаём")
	}
}

func TestРейтингСчитаетсяЗаПоследнийГод(t *testing.T) {
	now := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	old := now.Add(-2 * 365 * 24 * time.Hour)
	published := now.Add(-time.Hour)

	summary := job.Rating([]job.Review{
		{Stars: 1, CreatedAt: old, PublishedAt: &old}, // старый грех не тянет вниз
		{Stars: 5, CreatedAt: now, PublishedAt: &published},
		{Stars: 4, CreatedAt: now, PublishedAt: &published},
		{Stars: 5, CreatedAt: now}, // скрытый в рейтинг не идёт
	}, now)

	if summary.Count != 2 || summary.Rating != 4.5 {
		t.Fatalf("рейтинг за год по опубликованным: %+v", summary)
	}
}

func TestОценкаСообщаетВторойСтороне(t *testing.T) {
	svc, rec := newSvcWithNotifier()
	ctx := context.Background()
	d := completed(t, svc)

	if _, err := svc.LeaveReview(ctx, client, d.ID, job.Review{Stars: 5}); err != nil {
		t.Fatalf("оценка: %v", err)
	}

	if len(rec.to(owner)) == 0 {
		t.Fatal("исполнителю нужно напомнить оценить в ответ — иначе оба отзыва висят скрытыми")
	}
}
