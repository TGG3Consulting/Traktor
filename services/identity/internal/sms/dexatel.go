package sms

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// Dexatel — реальный провайдер SMS-OTP (стандартный net/http, без внешних
// зависимостей). Эндпоинт/поля уточняются по документации Dexatel после
// заведения аккаунта; интерфейс Provider при этом не меняется.
type Dexatel struct {
	apiKey   string
	senderID string
	baseURL  string
	client   *http.Client
}

func NewDexatel(apiKey, senderID string) *Dexatel {
	return &Dexatel{
		apiKey:   apiKey,
		senderID: senderID,
		baseURL:  "https://api.dexatel.com/v1",
		client:   &http.Client{Timeout: 10 * time.Second},
	}
}

func (d *Dexatel) SendCode(ctx context.Context, phone, code string) (string, error) {
	body, _ := json.Marshal(map[string]any{
		"data": map[string]any{
			"type": "messages",
			"attributes": map[string]any{
				"from": d.senderID,
				"to":   []string{phone},
				"text": fmt.Sprintf("Traktor: код %s", code),
			},
		},
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, d.baseURL+"/messages", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Dexatel-Key", d.apiKey)
	resp, err := d.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("dexatel: status %d", resp.StatusCode)
	}
	return "sms", nil
}
