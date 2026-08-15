package service

import (
	"context"
	"errors"
	"testing"

	"traktor/identity/internal/store"
)

// Бейдж «Проверен» (ТЗ §2.3): главный сигнал доверия в ленте.

// verified — человек с заполненным именем: документ не с чем сверять, если
// профиль пустой.
func namedUser(t *testing.T, a *Auth, fake interface{ Last(string) string }, phone, name string) *Session {
	t.Helper()
	sess := login(t, a, fake, phone)
	if _, err := a.UpdateProfile(context.Background(), sess.User.ID,
		ProfilePatch{Name: &name}); err != nil {
		t.Fatalf("профиль: %v", err)
	}
	return sess
}

func TestЗаявкаБезДокументаНеПринимается(t *testing.T) {
	a, fake, _ := newAuth(t)
	user := namedUser(t, a, fake, "+37491000001", "Карен")

	_, err := a.SubmitVerification(context.Background(), user.User.ID, "passport", nil)
	if !errors.Is(err, ErrNoDocuments) {
		t.Fatalf("модератору нужно что-то смотреть: %v", err)
	}
}

func TestБезИмениПроверятьНечего(t *testing.T) {
	a, fake, _ := newAuth(t)
	user := login(t, a, fake, "+37491000002")

	_, err := a.SubmitVerification(context.Background(), user.User.ID, "passport",
		[]string{"https://media/doc1.jpg"})
	if !errors.Is(err, ErrNeedNameCity) {
		t.Fatalf("документ не с чем сверить: %v", err)
	}
}

func TestВтораяЗаявкаНеУдлиняетОчередь(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)
	user := namedUser(t, a, fake, "+37491000003", "Ашот")

	if _, err := a.SubmitVerification(ctx, user.User.ID, "passport",
		[]string{"https://media/doc1.jpg"}); err != nil {
		t.Fatalf("первая заявка: %v", err)
	}
	_, err := a.SubmitVerification(ctx, user.User.ID, "passport",
		[]string{"https://media/doc2.jpg"})
	if !errors.Is(err, store.ErrVerifyPending) {
		t.Fatalf("вторая заявка должна быть отклонена: %v", err)
	}
}

func TestОдобрениеВыдаётБейдж(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)
	moder := login(t, a, fake, "+37490000001")
	user := namedUser(t, a, fake, "+37491000004", "Гурген")

	v, err := a.SubmitVerification(ctx, user.User.ID, "passport",
		[]string{"https://media/doc1.jpg"})
	if err != nil {
		t.Fatalf("заявка: %v", err)
	}

	queue, err := a.VerificationQueue(ctx, 0)
	if err != nil || len(queue) != 1 {
		t.Fatalf("очередь: %v / %d", err, len(queue))
	}
	if queue[0].UserName != "Гурген" {
		t.Fatalf("модератор сверяет документ с профилем: %q", queue[0].UserName)
	}

	if _, err := a.ReviewVerification(ctx, moder.User.ID, v.ID, true, ""); err != nil {
		t.Fatalf("одобрение: %v", err)
	}
	after, err := a.Me(ctx, user.User.ID)
	if err != nil {
		t.Fatalf("профиль: %v", err)
	}
	if !after.Verified {
		t.Fatal("после одобрения бейдж должен появиться")
	}
}

func TestОтказТребуетПричины(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)
	moder := login(t, a, fake, "+37490000001")
	user := namedUser(t, a, fake, "+37491000005", "Тигран")

	v, _ := a.SubmitVerification(ctx, user.User.ID, "passport",
		[]string{"https://media/doc1.jpg"})

	if _, err := a.ReviewVerification(ctx, moder.User.ID, v.ID, false, "нет"); !errors.Is(err, ErrNeedReason) {
		// Без причины человек не поймёт, что переснять.
		t.Fatalf("отказ без объяснения не должен проходить: %v", err)
	}
	if _, err := a.ReviewVerification(ctx, moder.User.ID, v.ID, false,
		"Снимок засвечен, номер документа не читается"); err != nil {
		t.Fatalf("отказ с причиной: %v", err)
	}

	after, _ := a.Me(ctx, user.User.ID)
	if after.Verified {
		t.Fatal("после отказа бейджа быть не должно")
	}
	// После отказа человек должен иметь возможность переснять и подать снова.
	if _, err := a.SubmitVerification(ctx, user.User.ID, "passport",
		[]string{"https://media/doc-new.jpg"}); err != nil {
		t.Fatalf("повторная подача после отказа: %v", err)
	}
}

func TestПроверенномуПовторноНеНужно(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)
	moder := login(t, a, fake, "+37490000001")
	user := namedUser(t, a, fake, "+37491000006", "Ваган")

	v, _ := a.SubmitVerification(ctx, user.User.ID, "passport",
		[]string{"https://media/doc1.jpg"})
	if _, err := a.ReviewVerification(ctx, moder.User.ID, v.ID, true, ""); err != nil {
		t.Fatalf("одобрение: %v", err)
	}
	_, err := a.SubmitVerification(ctx, user.User.ID, "passport",
		[]string{"https://media/doc2.jpg"})
	if !errors.Is(err, ErrVerifyClosed) {
		t.Fatalf("работа модерации впустую: %v", err)
	}
}
