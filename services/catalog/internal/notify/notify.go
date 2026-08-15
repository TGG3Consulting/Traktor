// Package notify — сообщения владельцу техники о решении модерации (ТЗ §2.5).
//
// Каталог не знает про устройства и FCM: он лишь говорит сервису
// notifications, кого и о чём предупредить. Отправка best-effort — сорванное
// уведомление не должно отменять решение модератора, оно уже в базе.
package notify

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
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
		// Тип события из push-матрицы (ТЗ §2.14): по нему центр уведомлений
		// рисует иконку. Передаём его же в data — экран назначения читает
		// оттуда всё, что ему нужно.
		"kind":  kindOf(data),
		"title": title,
		"body":  body,
		"data":  data,
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

// kindOf — тип события для центра уведомлений (ТЗ §2.14). Если вызывающий не
// указал его явно, выводим из маршрута перехода: тип нужен только для иконки и
// группировки, и держать его вторым списком рядом с маршрутами — лишний повод
// для расхождений.
func kindOf(data map[string]string) string {
	if k := data["kind"]; k != "" {
		return k
	}
	route := data["route"]
	switch {
	case strings.HasPrefix(route, "/chats"):
		return "message"
	case strings.Contains(route, "/bids"):
		return "auction"
	case strings.Contains(route, "/offers"):
		return "offer"
	case strings.Contains(route, "/review"):
		return "review"
	case strings.HasPrefix(route, "/deals"):
		return "deal"
	case strings.HasPrefix(route, "/jobs"):
		return "job"
	default:
		return "system"
	}
}

// Noop — заглушка для тестов и запуска без сервиса уведомлений.
type Noop struct{}

func (Noop) Send(context.Context, string, string, string, map[string]string) {}
