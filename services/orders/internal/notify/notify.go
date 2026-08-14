// Package notify — отправка уведомлений о событиях заданий (ТЗ §2.14).
//
// Сервис orders не знает про устройства и FCM: он лишь сообщает сервису
// notifications, кого и о чём предупредить. Отправка всегда best-effort и не
// в транзакции: сорванный push не должен отменять принятое решение заказчика.
// Гарантированную доставку даст outbox на следующей фазе — тогда этот клиент
// станет получателем событий, а не прямым вызовом.
package notify

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"time"
)

// Notifier отправляет уведомление пользователю.
type Notifier interface {
	Send(ctx context.Context, userID, title, body string, data map[string]string)
}

// HTTP — клиент сервиса notifications.
type HTTP struct {
	baseURL string
	client  *http.Client
	log     *slog.Logger
}

func NewHTTP(baseURL string, log *slog.Logger) *HTTP {
	return &HTTP{
		baseURL: baseURL,
		// Короткий таймаут: уведомление не стоит того, чтобы держать запрос
		// пользователя. Не успели — значит не успели.
		client: &http.Client{Timeout: 3 * time.Second},
		log:    log,
	}
}

func (h *HTTP) Send(ctx context.Context, userID, title, body string, data map[string]string) {
	if h.baseURL == "" || userID == "" {
		return
	}
	payload, err := json.Marshal(map[string]any{
		"userId": userID,
		"title":  title,
		"body":   body,
		"data":   data,
	})
	if err != nil {
		return
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		h.baseURL+"/internal/notify", bytes.NewReader(payload))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := h.client.Do(req)
	if err != nil {
		h.log.Warn("уведомление не отправлено", "err", err, "user", userID)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		h.log.Warn("сервис уведомлений отказал", "status", resp.StatusCode, "user", userID)
	}
}

// Noop — заглушка для тестов и запуска без сервиса уведомлений.
type Noop struct{}

func (Noop) Send(context.Context, string, string, string, map[string]string) {}

// Тексты уведомлений держим здесь, а не в местах вызова: их читает человек, и
// формулировки должны быть согласованы между собой.
const (
	TitleNewOffer  = "Новый отклик"
	TitleCounter   = "Заказчик предложил свою цену"
	TitleAccepted  = "Вас выбрали"
	TitleDeclined  = "Предложение отклонено"
	TitleJobClosed = "Задание закрыто"
)

// MoneyRU — сумма для текста уведомления: «42 000 ֏».
func MoneyRU(amount int64, currency string) string {
	digits := fmt.Sprintf("%d", amount)
	var out []byte
	for i := 0; i < len(digits); i++ {
		if i > 0 && (len(digits)-i)%3 == 0 {
			out = append(out, ' ')
		}
		out = append(out, digits[i])
	}
	sign := currency
	if currency == "AMD" {
		sign = "֏"
	}
	return string(out) + " " + sign
}
