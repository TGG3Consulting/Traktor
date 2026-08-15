// Package realtime — публикация событий в Centrifugo (ADR-6).
//
// Аукцион теряет смысл, если участники узнают о новой ставке при следующем
// заходе на экран: торг живёт минутами, а решение принимается по текущей цене.
// Поэтому каждая ставка и каждое продление уходят в канал задания, а клиенты
// получают их по вебсокету за доли секунды.
//
// Публикация всегда best-effort: упавший Centrifugo не должен отменять принятую
// ставку. Данные остаются в базе, и экран при следующем обновлении покажет их.
package realtime

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"
)

// Publisher публикует событие в канал.
type Publisher interface {
	Publish(ctx context.Context, channel string, event map[string]any)
}

// Centrifugo — клиент серверного API Centrifugo.
type Centrifugo struct {
	url    string
	apiKey string
	client *http.Client
	log    *slog.Logger
}

func NewCentrifugo(url, apiKey string, log *slog.Logger) *Centrifugo {
	return &Centrifugo{
		url:    url,
		apiKey: apiKey,
		// Короткий таймаут: событие живёт секунды, а запрос человека ждать
		// публикации не должен.
		client: &http.Client{Timeout: 2 * time.Second},
		log:    log,
	}
}

func (c *Centrifugo) Publish(ctx context.Context, channel string, event map[string]any) {
	if c.url == "" || c.apiKey == "" || channel == "" {
		return
	}
	// Время сервера в каждом событии: у клиентов часы врут, а таймер финиша
	// должен идти одинаково у всех (ТЗ §2.9).
	event["serverTime"] = time.Now().UTC().Format(time.RFC3339)

	payload, err := json.Marshal(map[string]any{
		"channel": channel,
		"data":    event,
	})
	if err != nil {
		return
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		c.url+"/api/publish", bytes.NewReader(payload))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", c.apiKey)

	resp, err := c.client.Do(req)
	if err != nil {
		c.log.Warn("событие не опубликовано", "channel", channel, "err", err)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		c.log.Warn("realtime отказал", "channel", channel, "status", resp.StatusCode)
	}
}

// JobChannel — канал задания: лента торга и статусы (namespace job).
func JobChannel(jobID string) string { return "job:" + jobID }

// ChatChannel — канал переписки (namespace chat).
func ChatChannel(chatID string) string { return "chat:" + chatID }

// Noop — заглушка для тестов и запуска без Centrifugo.
type Noop struct{}

func (Noop) Publish(context.Context, string, map[string]any) {}
