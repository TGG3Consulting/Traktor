package service

import (
	"context"
	"errors"
	"testing"

	"traktor/identity/internal/store"
	"traktor/identity/internal/token"
)

// Управление пользователями у модерации (ТЗ §4.1, п.3 и 8).

// login — вошедший человек: без него не на кого применять решения.
func login(t *testing.T, a *Auth, fake interface{ Last(string) string }, phone string) *Session {
	t.Helper()
	ctx := context.Background()
	if _, _, err := a.StartOTP(ctx, phone); err != nil {
		t.Fatalf("отправка кода: %v", err)
	}
	sess, err := a.VerifyOTP(ctx, phone, fake.Last(phone))
	if err != nil {
		t.Fatalf("вход: %v", err)
	}
	return sess
}

func TestЗаморозкаПопадаетВТокен(t *testing.T) {
	ctx := context.Background()
	a, fake, pub := newAuth(t)

	moder := login(t, a, fake, "+37490000001")
	user := login(t, a, fake, "+37491111111")

	if _, err := a.SetStatus(ctx, moder.User.ID, user.User.ID, store.StatusFrozen,
		"Просит оплату мимо площадки в переписке"); err != nil {
		t.Fatalf("заморозка: %v", err)
	}

	// Заморозка оставляет вход: у человека могут быть незакрытые сделки.
	again := login(t, a, fake, "+37491111111")
	claims, err := token.Parse(again.AccessToken, pub, a.now())
	if err != nil {
		t.Fatalf("разбор токена: %v", err)
	}
	if claims.Status != store.StatusFrozen {
		t.Fatalf("сервисы узнают о заморозке из токена, а там %q", claims.Status)
	}
}

func TestБанЗакрываетВход(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)

	moder := login(t, a, fake, "+37490000001")
	user := login(t, a, fake, "+37492222222")

	if _, err := a.SetStatus(ctx, moder.User.ID, user.User.ID, store.StatusBanned,
		"Три подтверждённые жалобы на обман заказчиков"); err != nil {
		t.Fatalf("бан: %v", err)
	}

	if _, _, err := a.StartOTP(ctx, "+37492222222"); err != nil {
		t.Fatalf("отправка кода: %v", err)
	}
	_, err := a.VerifyOTP(ctx, "+37492222222", fake.Last("+37492222222"))
	if !errors.Is(err, ErrBanned) {
		t.Fatalf("забаненному вход закрыт, а получили: %v", err)
	}
}

func TestБанОбрываетСтарыеСессии(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)

	moder := login(t, a, fake, "+37490000001")
	user := login(t, a, fake, "+37493333333")

	if _, err := a.SetStatus(ctx, moder.User.ID, user.User.ID, store.StatusBanned,
		"Оскорбления в переписке после отказа"); err != nil {
		t.Fatalf("бан: %v", err)
	}
	// Иначе бан начинает работать только через 30 дней, когда истечёт refresh.
	if _, err := a.Refresh(ctx, user.RefreshToken); err == nil {
		t.Fatal("забаненный продлил сессию")
	}
}

func TestБанОбратим(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)

	moder := login(t, a, fake, "+37490000001")
	user := login(t, a, fake, "+37494444444")

	if _, err := a.SetStatus(ctx, moder.User.ID, user.User.ID, store.StatusBanned,
		"Ошибочно принят за другого человека"); err != nil {
		t.Fatalf("бан: %v", err)
	}
	if _, err := a.SetStatus(ctx, moder.User.ID, user.User.ID, store.StatusActive,
		"Разобрались: жалоба была на однофамильца"); err != nil {
		t.Fatalf("снятие: %v", err)
	}
	// Ошибку модератора должно быть можно исправить, не заводя новый номер.
	if _, _, err := a.StartOTP(ctx, "+37494444444"); err != nil {
		t.Fatalf("отправка кода: %v", err)
	}
	if _, err := a.VerifyOTP(ctx, "+37494444444", fake.Last("+37494444444")); err != nil {
		t.Fatalf("после снятия бана вход должен работать: %v", err)
	}
}

func TestРешениеТребуетПричины(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)

	moder := login(t, a, fake, "+37490000001")
	user := login(t, a, fake, "+37495555555")

	_, err := a.SetStatus(ctx, moder.User.ID, user.User.ID, store.StatusBanned, "плохой")
	if !errors.Is(err, ErrNeedReason) {
		t.Fatalf("«плохой» не объясняет ничего ни человеку, ни следующему модератору: %v", err)
	}
}

func TestРешенияПопадаютВЖурнал(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)

	moder := login(t, a, fake, "+37490000001")
	user := login(t, a, fake, "+37496666666")

	if _, err := a.SetStatus(ctx, moder.User.ID, user.User.ID, store.StatusFrozen,
		"Две подтверждённые жалобы на срыв договорённостей"); err != nil {
		t.Fatalf("заморозка: %v", err)
	}
	card, err := a.UserCard(ctx, user.User.ID)
	if err != nil {
		t.Fatalf("карточка: %v", err)
	}
	if len(card.History) != 1 || card.History[0].ActorID != moder.User.ID {
		t.Fatalf("без журнала решение невозможно ни найти, ни оспорить: %+v", card.History)
	}
}

func TestПоискПоТелефонуИИмени(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)

	user := login(t, a, fake, "+37497777777")
	if _, err := a.UpdateProfile(ctx, user.User.ID, ProfilePatch{Name: strptr("Карен")}); err != nil {
		t.Fatalf("профиль: %v", err)
	}

	byPhone, err := a.SearchUsers(ctx, "+37497777777", 0)
	if err != nil || len(byPhone) != 1 {
		t.Fatalf("поиск по номеру: %v / %d", err, len(byPhone))
	}
	byName, err := a.SearchUsers(ctx, "карен", 0)
	if err != nil || len(byName) != 1 {
		t.Fatalf("поиск по имени без учёта регистра: %v / %d", err, len(byName))
	}
}

func strptr(s string) *string { return &s }
