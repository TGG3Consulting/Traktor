package middleware

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/httprate"
)

// problem — единый формат ошибок шлюза (problem+json, RFC 9457).
func problem(w http.ResponseWriter, status int, detail string) {
	w.Header().Set("Content-Type", "application/problem+json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"status": status, "detail": detail})
}

// RateLimit — ограничение частоты запросов по IP (правило 23: go-chi/httprate,
// не самописный счётчик). На проде дополняется лимитами Cloudflare на границе и
// специфичными лимитами в сервисах (ставки ≤ 1/с).
func RateLimit(limit int, window time.Duration) func(http.Handler) http.Handler {
	return httprate.Limit(
		limit, window,
		httprate.WithKeyFuncs(httprate.KeyByRealIP),
		httprate.WithLimitHandler(func(w http.ResponseWriter, _ *http.Request) {
			problem(w, http.StatusTooManyRequests, "Слишком часто. Повторите чуть позже")
		}),
	)
}

// Idempotency требует заголовок Idempotency-Key на мутациях (ТЗ §4.3), чтобы
// «двойной тап» не создавал две операции. Публичные пути (напр. отправка OTP)
// освобождаются через exempt.
//
// TODO(v1, шаг «кэш»): хранить ключи и ответы в Redis, чтобы повтор запроса
// возвращал первый ответ, а не выполнял операцию заново. Сейчас проверяется
// только наличие заголовка.
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
