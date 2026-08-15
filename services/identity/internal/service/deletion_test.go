package service

import (
	"context"
	"testing"
	"time"

	"traktor/identity/internal/store"
)

// Удаление аккаунта с отсрочкой (ТЗ §2.3, §4.3).

func TestУдалениеНеМгновенное(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)
	user := login(t, a, fake, "+37492000001")

	until, err := a.RequestDeletion(ctx, user.User.ID)
	if err != nil {
		t.Fatalf("запрос: %v", err)
	}
	if !until.After(a.now().Add(29 * 24 * time.Hour)) {
		t.Fatalf("отсрочка короче обещанных тридцати дней: %v", until)
	}

	// Пока срок не вышел, профиль на месте: человек может передумать.
	u, err := a.Me(ctx, user.User.ID)
	if err != nil {
		t.Fatalf("профиль: %v", err)
	}
	if u.Name != user.User.Name || u.DeleteAfter == nil {
		t.Fatalf("аккаунт не должен исчезать сразу: %+v", u)
	}
}

func TestВходОтменяетУдаление(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)
	user := login(t, a, fake, "+37492000002")

	if _, err := a.RequestDeletion(ctx, user.User.ID); err != nil {
		t.Fatalf("запрос: %v", err)
	}
	// Вернулся — значит передумал; отдельный экран с вопросом здесь лишний.
	login(t, a, fake, "+37492000002")

	u, _ := a.Me(ctx, user.User.ID)
	if u.DeleteAfter != nil {
		t.Fatalf("после входа удаление должно быть отменено: %v", u.DeleteAfter)
	}
}

func TestПоИстеченииСрокаПрофильОбезличивается(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)
	user := login(t, a, fake, "+37492000003")
	if _, err := a.UpdateProfile(ctx, user.User.ID, ProfilePatch{Name: strptr("Ашот")}); err != nil {
		t.Fatalf("профиль: %v", err)
	}
	if _, err := a.RequestDeletion(ctx, user.User.ID); err != nil {
		t.Fatalf("запрос: %v", err)
	}

	// Перематываем часы за конец отсрочки.
	later := time.Now().Add(DeleteGrace + time.Hour)
	a.now = func() time.Time { return later }

	n, err := a.RunDeletions(ctx)
	if err != nil || n != 1 {
		t.Fatalf("обработчик: %v / %d", err, n)
	}

	u, err := a.Me(ctx, user.User.ID)
	if err != nil {
		// Профиль остаётся в базе: на него ссылаются сделки и отзывы второй
		// стороны, и удалить их значило бы наказать того, кто остался.
		t.Fatalf("запись должна сохраниться обезличенной: %v", err)
	}
	if u.Name != "" || u.AnonymizedAt == nil {
		t.Fatalf("профиль не обезличен: %+v", u)
	}
	if _, err := a.Refresh(ctx, user.RefreshToken); err == nil {
		t.Fatal("сессии удалённого аккаунта должны обрываться")
	}
}

func TestНомерОсвобождаетсяПослеУдаления(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)
	const phone = "+37492000004"
	user := login(t, a, fake, phone)
	if _, err := a.RequestDeletion(ctx, user.User.ID); err != nil {
		t.Fatalf("запрос: %v", err)
	}

	later := time.Now().Add(DeleteGrace + time.Hour)
	a.now = func() time.Time { return later }
	if _, err := a.RunDeletions(ctx); err != nil {
		t.Fatalf("обработчик: %v", err)
	}

	// Тот же номер должен снова работать: человек имеет право вернуться,
	// а не остаться заблокированным собственным удалением.
	again := login(t, a, fake, phone)
	if again.User.ID == user.User.ID {
		t.Fatal("после удаления заводится новый аккаунт, а не оживает старый")
	}
}

func TestПовторныйЗапросНеСдвигаетСрок(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)
	user := login(t, a, fake, "+37492000005")

	first, err := a.RequestDeletion(ctx, user.User.ID)
	if err != nil {
		t.Fatalf("запрос: %v", err)
	}
	second, err := a.RequestDeletion(ctx, user.User.ID)
	if err != ErrAlreadyDeleting {
		t.Fatalf("повторный запрос: %v", err)
	}
	if !first.Equal(second) {
		t.Fatalf("двойное нажатие не должно продлевать срок: %v и %v", first, second)
	}
}

var _ = store.User{}
