// Шлюз Traktor: единая точка входа для клиентов. Проверяет JWT по JWKS
// сервиса identity, ограничивает частоту, требует Idempotency-Key на мутациях,
// проксирует к сервисам. Только стандартная библиотека.
package main

import (
	"log"
	"net/http"
	"strings"

	"traktor/gateway/internal/config"
	"traktor/gateway/internal/jwks"
	"traktor/gateway/internal/middleware"
	"traktor/gateway/internal/proxy"
)

func main() {
	cfg := config.Load()
	cache := jwks.New(cfg.JWKSURL)

	// Публичные пути — без авторизации и без Idempotency-Key.
	public := func(path string) bool {
		return path == "/healthz" ||
			strings.HasPrefix(path, "/v1/auth/") ||
			strings.HasPrefix(path, "/.well-known/")
	}

	// Маршруты к сервисам (по мере появления сервисов список растёт).
	// Наиболее длинный совпадающий префикс выигрывает (см. proxy.Router).
	router, err := proxy.Router([]proxy.Route{
		{Prefix: "/v1/auth/", Upstream: cfg.IdentityURL},
		{Prefix: "/v1/me", Upstream: cfg.IdentityURL},
		{Prefix: "/v1/devices", Upstream: cfg.NotificationsURL},
		{Prefix: "/.well-known/", Upstream: cfg.IdentityURL},
	})
	if err != nil {
		log.Fatalf("proxy: %v", err)
	}

	rl := middleware.NewRateLimit(cfg.RateLimit, cfg.RateWindow)
	idem := middleware.Idempotency(public)
	auth := middleware.Auth(cache, public)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) })
	// Цепочка: rate-limit → auth → idempotency → прокси.
	mux.Handle("/", rl.Wrap(auth(idem(router))))

	addr := ":" + cfg.Port
	log.Printf("gateway: слушаю %s → identity %s", addr, cfg.IdentityURL)
	if err := http.ListenAndServe(addr, cors(cfg.AllowOrigin, mux)); err != nil {
		log.Fatal(err)
	}
}

// cors — минимальный CORS для web-клиента (уточняется на web-этапе).
func cors(origin string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, Idempotency-Key")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, PUT, DELETE, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
