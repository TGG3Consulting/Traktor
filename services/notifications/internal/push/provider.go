// Package push — отправка пуш-уведомлений через внешнего провайдера.
// Каждый внешний сервис — за интерфейсом (инвариант §2.3.14), с записанным
// «путём эвакуации»: сегодня FCM, завтра — APNs напрямую/веб-push без смены
// вызывающего кода. Дефолт — fake (для dev/тестов, без сети и ключей).
package push

import (
	"context"
	"errors"
)

// Message — одно уведомление на одно устройство. Тексты уже локализованы
// сервисом (по Device.Locale). Data — «тихая» полезная нагрузка для навигации
// в приложении (например, {"type":"deal.updated","dealId":"..."}).
type Message struct {
	Token string
	Title string
	Body  string
	Data  map[string]string
}

// ErrTokenInvalid — провайдер сообщил, что токен больше не действителен
// (переустановка/отзыв). Вызывающий обязан удалить такой токен из хранилища.
var ErrTokenInvalid = errors.New("push: token invalid")

// Provider — абстракция транспорта пушей.
type Provider interface {
	// Send отправляет одно сообщение. Возвращает ErrTokenInvalid, если токен
	// протух (тогда сервис его удалит), либо иную ошибку при сбое отправки.
	Send(ctx context.Context, m Message) error
	// Name — для логов и метрик.
	Name() string
}
