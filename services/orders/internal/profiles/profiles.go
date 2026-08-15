// Package profiles — публичные карточки пользователей из сервиса identity.
//
// Сервис orders хранит только идентификаторы: имя и рейтинг живут в identity
// (schema-per-service, cross-schema JOIN запрещён). Поэтому карточки берутся
// по HTTP пачкой на весь список — один запрос на экран, а не по одному на строку.
package profiles

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Profile — то, что можно показать про человека до сделки.
type Profile struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	City        string  `json:"city"`
	Verified    bool    `json:"verified"`
	Rating      float64 `json:"rating"`
	RatingCount int     `json:"ratingCount"`
}

// Client отдаёт карточки по идентификаторам.
type Client interface {
	ByIDs(ctx context.Context, ids []string) map[string]Profile
}

// HTTP — клиент identity с коротким кэшем.
type HTTP struct {
	baseURL string
	client  *http.Client

	// Имена меняются редко, а список откликов перечитывается на каждое
	// обновление экрана: минутный кэш убирает лишние походы в identity,
	// оставаясь незаметным для человека.
	mu    sync.RWMutex
	cache map[string]cached
	ttl   time.Duration
}

type cached struct {
	profile Profile
	at      time.Time
}

func NewHTTP(baseURL string) *HTTP {
	return &HTTP{
		baseURL: baseURL,
		client:  &http.Client{Timeout: 3 * time.Second},
		cache:   map[string]cached{},
		ttl:     time.Minute,
	}
}

func (h *HTTP) ByIDs(ctx context.Context, ids []string) map[string]Profile {
	out := make(map[string]Profile, len(ids))
	if h.baseURL == "" || len(ids) == 0 {
		return out
	}

	var missing []string
	now := time.Now()
	h.mu.RLock()
	for _, id := range ids {
		if c, ok := h.cache[id]; ok && now.Sub(c.at) < h.ttl {
			out[id] = c.profile
		} else if id != "" {
			missing = append(missing, id)
		}
	}
	h.mu.RUnlock()
	if len(missing) == 0 {
		return out
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		h.baseURL+"/internal/profiles?ids="+strings.Join(missing, ","), nil)
	if err != nil {
		return out
	}
	resp, err := h.client.Do(req)
	if err != nil {
		// Профили — украшение, а не суть: без них экран покажет обезличенные
		// подписи, но работать не перестанет.
		return out
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return out
	}

	var body struct {
		Items []Profile `json:"items"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return out
	}

	h.mu.Lock()
	for _, p := range body.Items {
		out[p.ID] = p
		h.cache[p.ID] = cached{profile: p, at: now}
	}
	h.mu.Unlock()
	return out
}

// Noop — заглушка для тестов и запуска без identity.
type Noop struct{}

func (Noop) ByIDs(context.Context, []string) map[string]Profile { return nil }

// DisplayName — имя для интерфейса. Пустое имя заменяем на обезличенную
// подпись: пустая строка на экране выглядит как поломка.
func DisplayName(p Profile, fallback string) string {
	if strings.TrimSpace(p.Name) != "" {
		return p.Name
	}
	return fallback
}

// CountUsers — регистрации за период из identity (ТЗ §4.1, п.1).
//
// Считает тот сервис, которому принадлежат пользователи: orders о них ничего
// не знает и знать не должен (правило 12).
func (h *HTTP) CountUsers(ctx context.Context, from, to time.Time) int {
	if h.baseURL == "" {
		return 0
	}
	url := h.baseURL + "/internal/stats/users?from=" +
		from.UTC().Format(time.RFC3339) + "&to=" + to.UTC().Format(time.RFC3339)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return 0
	}
	resp, err := h.client.Do(req)
	if err != nil {
		return 0
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return 0
	}
	var body struct {
		Users int `json:"users"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return 0
	}
	return body.Users
}
