package middleware

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"
)

// problem — единый формат ошибок шлюза (problem+json).
func problem(w http.ResponseWriter, status int, detail string) {
	w.Header().Set("Content-Type", "application/problem+json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"status": status, "detail": detail})
}

// RateLimit — простой лимит запросов на IP (токен-бакет). На проде дополняется
// лимитами Cloudflare на границе и специфичными лимитами в сервисах (ставки ≤1/с).
type RateLimit struct {
	mu     sync.Mutex
	hits   map[string][]time.Time
	limit  int
	window time.Duration
}

func NewRateLimit(limit int, window time.Duration) *RateLimit {
	return &RateLimit{hits: map[string][]time.Time{}, limit: limit, window: window}
}

func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		if i := indexByte(xff, ','); i >= 0 {
			return xff[:i]
		}
		return xff
	}
	return r.RemoteAddr
}

func indexByte(s string, b byte) int {
	for i := 0; i < len(s); i++ {
		if s[i] == b {
			return i
		}
	}
	return -1
}

func (rl *RateLimit) Wrap(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := clientIP(r)
		now := time.Now()
		rl.mu.Lock()
		cutoff := now.Add(-rl.window)
		kept := rl.hits[ip][:0]
		for _, t := range rl.hits[ip] {
			if t.After(cutoff) {
				kept = append(kept, t)
			}
		}
		if len(kept) >= rl.limit {
			rl.hits[ip] = kept
			rl.mu.Unlock()
			problem(w, http.StatusTooManyRequests, "Слишком часто. Повторите чуть позже")
			return
		}
		rl.hits[ip] = append(kept, now)
		rl.mu.Unlock()
		next.ServeHTTP(w, r)
	})
}

// Idempotency требует заголовок Idempotency-Key на мутациях (ТЗ §4.3), чтобы
// «двойной тап» не создавал две операции. Публичные пути (напр. отправка OTP)
// освобождаются через exempt. Полное хранилище ключей — в Redis на шаге кэша.
func Idempotency(exempt func(path string) bool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			mutating := r.Method == http.MethodPost || r.Method == http.MethodPatch || r.Method == http.MethodPut
			if mutating && !exempt(r.URL.Path) && r.Header.Get("Idempotency-Key") == "" {
				problem(w, http.StatusBadRequest, "Отсутствует Idempotency-Key")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
