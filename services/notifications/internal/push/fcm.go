package push

import (
	"context"
	"errors"
	"fmt"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
)

// FCM — провайдер поверх официального Firebase Admin SDK (правило 23: ручной
// HTTP-клиент к FCM v1 заменён библиотекой Google).
//
// Авторизация — Application Default Credentials: на Cloud Run это сервисный
// аккаунт ревизии, локально — GOOGLE_APPLICATION_CREDENTIALS. Файлов-ключей в
// репозитории нет (инвариант §2.3.15).
//
// Включается только когда задан FCM_PROJECT_ID (см. config); иначе сервис
// работает на fake-провайдере. «Путь эвакуации» (§2.3.14): при отказе от FCM
// сюда встаёт APNs/веб-push без изменения service.Notify.
type FCM struct {
	client *messaging.Client
}

// NewFCM поднимает клиента Firebase. Ошибка здесь означает, что учётные данные
// недоступны — сервис должен об этом сообщить на старте, а не в момент первой
// отправки.
func NewFCM(ctx context.Context, projectID string) (*FCM, error) {
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: projectID})
	if err != nil {
		return nil, fmt.Errorf("fcm: инициализация Firebase: %w", err)
	}
	client, err := app.Messaging(ctx)
	if err != nil {
		return nil, fmt.Errorf("fcm: клиент messaging: %w", err)
	}
	return &FCM{client: client}, nil
}

func (c *FCM) Name() string { return "fcm" }

// Send отправляет одно сообщение. Токен, который FCM считает отозванным,
// превращается в ErrTokenInvalid — сервис удалит протухшую регистрацию.
func (c *FCM) Send(ctx context.Context, m Message) error {
	msg := &messaging.Message{
		Token: m.Token,
		Notification: &messaging.Notification{
			Title: m.Title,
			Body:  m.Body,
		},
		Data: m.Data,
	}
	if _, err := c.client.Send(ctx, msg); err != nil {
		if isTokenInvalid(err) {
			return ErrTokenInvalid
		}
		return fmt.Errorf("fcm: отправка: %w", err)
	}
	return nil
}

// isTokenInvalid распознаёт ответы FCM про мёртвый токен: приложение удалено
// или токен перевыпущен.
func isTokenInvalid(err error) bool {
	return messaging.IsUnregistered(err) ||
		messaging.IsSenderIDMismatch(err) ||
		errors.Is(err, ErrTokenInvalid)
}

// Проверка контракта на этапе компиляции.
var _ Provider = (*FCM)(nil)
