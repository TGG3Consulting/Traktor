// Package units — карточки техники из сервиса catalog.
//
// Заказы не хранят технику: ею владеет catalog (schema-per-service). Но
// откликаться и делать ставки можно только своей активной машиной (ТЗ §2.5,
// §2.9), поэтому orders спрашивает у catalog короткую справку по единице.
package units

import (
	"context"
	"encoding/json"
	"net/http"
	"sync"
	"time"
)

// Unit — то, что нужно знать о технике при проверке отклика.
type Unit struct {
	ID         string `json:"id"`
	OwnerID    string `json:"ownerId"`
	CategoryID string `json:"categoryId"`
	Status     string `json:"status"`
	// Active — техника участвует в откликах: проверена или опубликована
	// без документов.
	Active   bool   `json:"active"`
	Title    string `json:"title"`
	Verified bool   `json:"verified"`
}

// Client отдаёт карточку техники по идентификатору.
type Client interface {
	ByID(ctx context.Context, id string) (Unit, bool)
}

// HTTP — клиент catalog с коротким кэшем: карточка меняется редко, а
// спрашивают её на каждой ставке.
type HTTP struct {
	baseURL string
	client  *http.Client

	mu    sync.RWMutex
	cache map[string]cached
	ttl   time.Duration
}

type cached struct {
	unit Unit
	at   time.Time
}

func NewHTTP(baseURL string) *HTTP {
	return &HTTP{
		baseURL: baseURL,
		client:  &http.Client{Timeout: 3 * time.Second},
		cache:   map[string]cached{},
		ttl:     time.Minute,
	}
}

func (h *HTTP) ByID(ctx context.Context, id string) (Unit, bool) {
	if h.baseURL == "" || id == "" {
		return Unit{}, false
	}

	h.mu.RLock()
	if c, ok := h.cache[id]; ok && time.Since(c.at) < h.ttl {
		h.mu.RUnlock()
		return c.unit, true
	}
	h.mu.RUnlock()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		h.baseURL+"/internal/equipment/"+id, nil)
	if err != nil {
		return Unit{}, false
	}
	resp, err := h.client.Do(req)
	if err != nil {
		return Unit{}, false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return Unit{}, false
	}

	var u Unit
	if err := json.NewDecoder(resp.Body).Decode(&u); err != nil {
		return Unit{}, false
	}

	h.mu.Lock()
	h.cache[id] = cached{unit: u, at: time.Now()}
	h.mu.Unlock()
	return u, true
}

// Noop — заглушка для тестов и запуска без каталога: техника не проверяется,
// но и не мешает работать.
type Noop struct{}

func (Noop) ByID(context.Context, string) (Unit, bool) { return Unit{}, false }
