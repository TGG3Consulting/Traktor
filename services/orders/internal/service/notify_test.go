package service

import (
	"context"
	"testing"
	"time"

	"traktor/orders/internal/job"
	"traktor/orders/internal/store"
)

// recorder запоминает отправленные уведомления, чтобы проверить: доходят ли
// они до нужных людей и в нужный момент.
type recorder struct {
	sent []sentNotification
}

type sentNotification struct {
	userID string
	title  string
	body   string
	route  string
}

func (r *recorder) Send(_ context.Context, userID, title, body string, data map[string]string) {
	r.sent = append(r.sent, sentNotification{userID, title, body, data["route"]})
}

func (r *recorder) to(userID string) []sentNotification {
	var out []sentNotification
	for _, s := range r.sent {
		if s.userID == userID {
			out = append(out, s)
		}
	}
	return out
}

func newSvcWithNotifier() (*Service, *recorder) {
	rec := &recorder{}
	fixed := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	return NewWithNotifier(store.NewMemory(), func() time.Time { return fixed }, rec), rec
}

func TestЗаказчикУзнаётОНовомОтклике(t *testing.T) {
	svc, rec := newSvcWithNotifier()
	ctx := context.Background()
	j := published(t, svc)

	_, err := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferAccept, Price: 120000})
	if err != nil {
		t.Fatalf("отклик: %v", err)
	}

	msgs := rec.to(client)
	if len(msgs) != 1 {
		t.Fatalf("заказчик должен получить одно уведомление, получил %d", len(msgs))
	}
	if msgs[0].route != "/jobs/"+j.ID+"/offers" {
		t.Fatalf("уведомление должно вести на экран откликов, ведёт на %s", msgs[0].route)
	}
	if !contains(msgs[0].body, "120 000") {
		t.Fatalf("в тексте нужна цена предложения: %s", msgs[0].body)
	}
}

func TestИсполнительУзнаётОВстречнойЦенеИВыборе(t *testing.T) {
	svc, rec := newSvcWithNotifier()
	ctx := context.Background()
	j := published(t, svc)
	o, _ := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferCounter, Price: 100000})

	if _, err := svc.CounterOffer(ctx, client, o.ID, 110000); err != nil {
		t.Fatalf("встречная цена: %v", err)
	}
	if _, err := svc.AcceptOffer(ctx, client, o.ID); err != nil {
		t.Fatalf("выбор: %v", err)
	}

	msgs := rec.to(owner)
	if len(msgs) != 2 {
		t.Fatalf("исполнителю нужны два уведомления (встречная цена и выбор), пришло %d", len(msgs))
	}
	if !contains(msgs[0].body, "110 000") {
		t.Fatalf("в первом должна быть встречная цена: %s", msgs[0].body)
	}
	if msgs[1].title == "" || !contains(msgs[1].body, "110 000") {
		t.Fatalf("во втором — цена сделки: %+v", msgs[1])
	}
}

func TestПроигравшимТожеСообщают(t *testing.T) {
	svc, rec := newSvcWithNotifier()
	ctx := context.Background()
	j := published(t, svc)
	mine, _ := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferAccept, Price: 120000})
	_, _ = svc.MakeOffer(ctx, owner2, j.ID, OfferInput{Kind: job.OfferCounter, Price: 90000})

	if _, err := svc.AcceptOffer(ctx, client, mine.ID); err != nil {
		t.Fatalf("выбор: %v", err)
	}

	// Молчание для проигравшего — худший сценарий: человек ждёт ответа днями.
	if len(rec.to(owner2)) == 0 {
		t.Fatal("исполнителю, которого не выбрали, тоже нужно уведомление")
	}
}

func TestОтклонениеСПричинойУходитИсполнителю(t *testing.T) {
	svc, rec := newSvcWithNotifier()
	ctx := context.Background()
	j := published(t, svc)
	o, _ := svc.MakeOffer(ctx, owner, j.ID, OfferInput{Kind: job.OfferCounter, Price: 90000})

	if _, err := svc.DeclineOffer(ctx, client, o.ID, "дорого для этого объёма"); err != nil {
		t.Fatalf("отклонение: %v", err)
	}

	msgs := rec.to(owner)
	if len(msgs) != 1 || !contains(msgs[0].body, "дорого") {
		t.Fatalf("причина отказа должна дойти до исполнителя: %+v", msgs)
	}
}

func contains(s, sub string) bool {
	// Своя проверка вместо strings.Contains — чтобы тест не зависел от того,
	// каким пробелом разделены разряды в сумме (обычный или неразрывный).
	normalize := func(v string) string {
		out := make([]rune, 0, len(v))
		for _, r := range v {
			if r == ' ' {
				r = ' '
			}
			out = append(out, r)
		}
		return string(out)
	}
	s, sub = normalize(s), normalize(sub)
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
