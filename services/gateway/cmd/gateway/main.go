// Шлюз Traktor: единая точка входа для клиентов. Проверяет JWT по JWKS
// сервиса identity, ограничивает частоту, требует Idempotency-Key на мутациях,
// проксирует к сервисам.
//
// Правило 23: роутер и middleware — chi, лимиты — httprate, CORS — go-chi/cors,
// проверка токенов — jwx + golang-jwt (см. internal/jwks).
package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/golang-jwt/jwt/v5"

	"traktor/gateway/internal/config"
	"traktor/gateway/internal/jwks"
	"traktor/gateway/internal/middleware"
	"traktor/gateway/internal/proxy"
)

// realtimeToken подписывает билет на подключение к Centrifugo.
//
// Билет живёт час: дольше держать смысла нет, клиент переподключается сам, а
// короткий срок ограничивает ущерб от утечки.
func realtimeToken(secret string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := r.Header.Get("X-User-Id")
		if userID == "" || secret == "" {
			w.Header().Set("Content-Type", "application/problem+json")
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"status":503,"detail":"живые обновления недоступны"}`))
			return
		}

		exp := time.Now().Add(time.Hour)
		token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
			"sub": userID,
			"exp": exp.Unix(),
			"iat": time.Now().Unix(),
		})
		signed, err := token.SignedString([]byte(secret))
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"token":     signed,
			"expiresAt": exp.UTC(),
		})
	}
}

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(log)

	if err := run(log); err != nil {
		log.Error("gateway остановлен с ошибкой", "err", err)
		os.Exit(1)
	}
}

// accessLog пишет каждый входящий запрос: метод, путь, код ответа, время и
// источник. Без этого невозможно отличить «сервис сломался» от «запрос до
// сервиса вообще не дошёл» — а это самая частая причина «у меня не работает».
func accessLog(log *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			ww := chimw.NewWrapResponseWriter(w, r.ProtoMajor)
			next.ServeHTTP(ww, r)
			log.Info("запрос",
				"method", r.Method,
				"path", r.URL.Path,
				"status", ww.Status(),
				"ms", time.Since(start).Milliseconds(),
				"origin", r.Header.Get("Origin"),
				"ip", r.RemoteAddr,
			)
		})
	}
}

func run(log *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg := config.Load()
	cache, err := jwks.New(cfg.JWKSURL)
	if err != nil {
		return err
	}

	// Публичные пути — без авторизации и без Idempotency-Key.
	public := func(path string) bool {
		return path == "/healthz" ||
			strings.HasPrefix(path, "/v1/auth/") ||
			strings.HasPrefix(path, "/.well-known/") ||
			// Справочник и лента заданий открыты гостю: «просто посмотреть»
			// из онбординга работает без входа (ТЗ §2.1, §4.2 web-паритет).
			// Личные разделы (/v1/jobs/my, черновики) остаются под токеном:
			// их сервис отдаёт только при заголовке X-User-Id от шлюза.
			strings.HasPrefix(path, "/v1/categories") ||
			strings.HasPrefix(path, "/v1/users/") ||
			// Техника в чужой карточке: её видно по ссылке без входа.
			strings.HasPrefix(path, "/v1/equipment/users/") ||
			publicJobsPath(path)
	}

	// Маршруты к сервисам (по мере появления сервисов список растёт).
	// Наиболее длинный совпадающий префикс выигрывает (см. proxy.Router).
	router, err := proxy.Router([]proxy.Route{
		{Prefix: "/v1/auth/", Upstream: cfg.IdentityURL},
		{Prefix: "/v1/me", Upstream: cfg.IdentityURL},
		{Prefix: "/v1/users", Upstream: cfg.IdentityURL},
		{Prefix: "/v1/devices", Upstream: cfg.NotificationsURL},
		{Prefix: "/v1/notifications", Upstream: cfg.NotificationsURL},
		{Prefix: "/v1/categories", Upstream: cfg.CatalogURL},
		{Prefix: "/v1/equipment", Upstream: cfg.CatalogURL},
		// Разделы модерации живут в разных сервисах: техника — в каталоге,
		// споры — в заказах. Роутер выбирает самый длинный совпавший префикс.
		{Prefix: "/v1/moderation/equipment", Upstream: cfg.CatalogURL},
		{Prefix: "/v1/moderation/categories", Upstream: cfg.CatalogURL},
		{Prefix: "/v1/moderation/users", Upstream: cfg.IdentityURL},
		{Prefix: "/v1/moderation/verifications", Upstream: cfg.IdentityURL},
		{Prefix: "/v1/moderation/disputes", Upstream: cfg.OrdersURL},
		{Prefix: "/v1/moderation/complaints", Upstream: cfg.OrdersURL},
		{Prefix: "/v1/moderation/dashboard", Upstream: cfg.OrdersURL},
		{Prefix: "/v1/media", Upstream: cfg.MediaURL},
		{Prefix: "/v1/jobs", Upstream: cfg.OrdersURL},
		{Prefix: "/v1/offers", Upstream: cfg.OrdersURL},
		{Prefix: "/v1/deals", Upstream: cfg.OrdersURL},
		{Prefix: "/v1/bids", Upstream: cfg.OrdersURL},
		{Prefix: "/v1/chats", Upstream: cfg.OrdersURL},
		{Prefix: "/v1/crm", Upstream: cfg.OrdersURL},
		{Prefix: "/v1/reviews", Upstream: cfg.OrdersURL},
		{Prefix: "/v1/complaints", Upstream: cfg.OrdersURL},
		{Prefix: "/.well-known/", Upstream: cfg.IdentityURL},
	})
	if err != nil {
		return err
	}

	r := chi.NewRouter()
	r.Use(
		chimw.RequestID,
		chimw.RealIP,
		accessLog(log),
		chimw.Recoverer,
		chimw.Timeout(30*time.Second),
		cors.Handler(cors.Options{
			AllowedOrigins:   strings.Split(cfg.AllowOrigin, ","),
			AllowedMethods:   []string{"GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"},
			AllowedHeaders:   []string{"Authorization", "Content-Type", "Idempotency-Key"},
			AllowCredentials: false,
			MaxAge:           300,
		}),
		middleware.RateLimit(cfg.RateLimit, cfg.RateWindow),
	)

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })

	// Всё остальное: авторизация → идемпотентность → прокси к сервисам.
	r.Group(func(r chi.Router) {
		r.Use(middleware.Auth(cache, public), middleware.Idempotency(public))

		// Токен подключения к Centrifugo (ADR-6). Выдаётся здесь, а не в
		// отдельном сервисе: шлюз уже проверил access-токен и знает, кто
		// пришёл, — остаётся подписать короткоживущий билет.
		r.Get("/v1/realtime/token", realtimeToken(cfg.CentrifugoSecret))

		r.Handle("/*", router)
	})

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           r,
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("gateway слушает", "addr", srv.Addr,
			"identity", cfg.IdentityURL, "notifications", cfg.NotificationsURL,
			"catalog", cfg.CatalogURL, "orders", cfg.OrdersURL)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		log.Info("получен сигнал остановки, завершаем текущие запросы")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		return srv.Shutdown(shutdownCtx)
	}
}

// publicJobsPath — какие пути заданий открыты без входа.
//
// Открыты только чтение ленты и деталка: гость из «просто посмотреть» видит,
// что происходит на площадке. Личные разделы (/v1/jobs/my, черновики) и любые
// изменения — под токеном. Метод здесь не проверяется намеренно: у сервиса
// orders изменяющие маршруты сами требуют X-User-Id, который без валидного
// токена шлюз не поставит, так что POST без входа получит 401 от сервиса.
func publicJobsPath(path string) bool {
	if !strings.HasPrefix(path, "/v1/jobs") {
		return false
	}
	rest := strings.TrimPrefix(path, "/v1/jobs")
	switch {
	case rest == "" || rest == "/":
		return true // лента
	case strings.HasPrefix(rest, "/my"):
		return false // мои задания и черновики
	case strings.HasPrefix(rest, "/drafts"):
		return false
	case strings.HasSuffix(rest, "/bids"):
		return true // лента торга: цены видны всем, имена участников скрыты
	case strings.Contains(strings.TrimPrefix(rest, "/"), "/"):
		return false // действия вида /{id}/publish
	default:
		return true // деталка /{id}
	}
}
