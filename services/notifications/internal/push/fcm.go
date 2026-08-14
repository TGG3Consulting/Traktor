package push

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"
)

// FCM — провайдер поверх Firebase Cloud Messaging HTTP v1.
// Только стандартная библиотека: авторизация — scoped access-token от
// metadata-сервера Cloud Run (identity сервисного аккаунта), без файлов-ключей
// в репозитории (инвариант §2.3.15 — секретов в коде нет).
//
// Включается только когда задан FCM_PROJECT_ID (см. config); иначе сервис
// работает на fake-провайдере. «Путь эвакуации» (§2.3.14): при отказе от FCM
// сюда встаёт APNs/веб-push без изменения service.Notify.
type FCM struct {
	projectID string
	http      *http.Client
	tokens    TokenSource
}

// TokenSource выдаёт OAuth2 access-token со scope firebase.messaging.
// В проде — MetadataTokenSource (сервисный аккаунт Cloud Run). В тестах
// подменяется статической функцией.
type TokenSource interface {
	Token(ctx context.Context) (string, error)
}

func NewFCM(projectID string, ts TokenSource) *FCM {
	return &FCM{
		projectID: projectID,
		http:      &http.Client{Timeout: 10 * time.Second},
		tokens:    ts,
	}
}

func (c *FCM) Name() string { return "fcm" }

// Send отправляет сообщение через FCM v1. Токен, помеченный сервером как
// UNREGISTERED/INVALID_ARGUMENT по токену, конвертируется в ErrTokenInvalid,
// чтобы сервис очистил протухшую регистрацию.
func (c *FCM) Send(ctx context.Context, m Message) error {
	access, err := c.tokens.Token(ctx)
	if err != nil {
		return fmt.Errorf("fcm: token: %w", err)
	}

	// Формат FCM HTTP v1: notification + data. Каналы/приоритеты платформ
	// уточняются на Фазе 5 (push-матрица ТЗ §2.14).
	payload := map[string]any{
		"message": map[string]any{
			"token": m.Token,
			"notification": map[string]any{
				"title": m.Title,
				"body":  m.Body,
			},
			"data": m.Data,
		},
	}
	buf, _ := json.Marshal(payload)

	url := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", c.projectID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(buf))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+access)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("fcm: send: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))

	switch {
	case resp.StatusCode == http.StatusOK:
		return nil
	case resp.StatusCode == http.StatusNotFound || resp.StatusCode == http.StatusGone:
		// Токен больше не зарегистрирован — сервис его удалит.
		return ErrTokenInvalid
	case resp.StatusCode == http.StatusBadRequest && isInvalidToken(body):
		return ErrTokenInvalid
	default:
		return fmt.Errorf("fcm: статус %d: %s", resp.StatusCode, string(body))
	}
}

func isInvalidToken(body []byte) bool {
	var e struct {
		Error struct {
			Status  string `json:"status"`
			Details []struct {
				ErrorCode string `json:"errorCode"`
			} `json:"details"`
		} `json:"error"`
	}
	if json.Unmarshal(body, &e) != nil {
		return false
	}
	for _, d := range e.Error.Details {
		if d.ErrorCode == "UNREGISTERED" || d.ErrorCode == "INVALID_ARGUMENT" {
			return true
		}
	}
	return false
}

// MetadataTokenSource берёт scoped access-token у metadata-сервера GCP
// (доступен на Cloud Run). Кэширует токен до истечения. Только stdlib.
type MetadataTokenSource struct {
	http *http.Client
	mu   sync.Mutex
	tok  string
	exp  time.Time
	now  func() time.Time
}

func NewMetadataTokenSource() *MetadataTokenSource {
	return &MetadataTokenSource{http: &http.Client{Timeout: 5 * time.Second}, now: time.Now}
}

const metadataTokenURL = "http://metadata.google.internal/computeMetadata/v1/" +
	"instance/service-accounts/default/token?scopes=" +
	"https://www.googleapis.com/auth/firebase.messaging"

func (s *MetadataTokenSource) Token(ctx context.Context) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.tok != "" && s.now().Before(s.exp) {
		return s.tok, nil
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, metadataTokenURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Metadata-Flavor", "Google")
	resp, err := s.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<12))
		return "", fmt.Errorf("metadata: статус %d: %s", resp.StatusCode, string(b))
	}
	var t struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&t); err != nil {
		return "", err
	}
	s.tok = t.AccessToken
	// Обновляем за 60 с до истечения.
	s.exp = s.now().Add(time.Duration(t.ExpiresIn-60) * time.Second)
	return s.tok, nil
}
