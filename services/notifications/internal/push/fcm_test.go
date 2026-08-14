package push

import (
	"context"
	"testing"
)

// Отправка через Firebase Admin SDK покрыта тестами самого SDK; наш код здесь —
// тонкая обёртка. Проверяем то, что принадлежит нам: контракт Provider и
// поведение fake-провайдера, на котором работают dev и тесты сервиса.
func TestFakeProviderCollectsMessages(t *testing.T) {
	f := NewFake()
	if f.Name() != "fake" {
		t.Fatalf("имя провайдера: %q", f.Name())
	}
	msg := Message{Token: "dev-tok", Title: "Задание", Body: "Отклик",
		Data: map[string]string{"type": "deal.updated"}}
	if err := f.Send(context.Background(), msg); err != nil {
		t.Fatalf("send: %v", err)
	}
	if f.Count() != 1 || f.Sent[0].Token != "dev-tok" || f.Sent[0].Data["type"] != "deal.updated" {
		t.Fatalf("fake не сохранил сообщение: %+v", f.Sent)
	}

	// Токен с префиксом invalid — ветка очистки протухших регистраций.
	if err := f.Send(context.Background(), Message{Token: "invalid-1"}); err != ErrTokenInvalid {
		t.Fatalf("ожидали ErrTokenInvalid, получили %v", err)
	}
	if f.Count() != 1 {
		t.Fatalf("протухшее сообщение не должно попадать в доставленные: %d", f.Count())
	}
}
