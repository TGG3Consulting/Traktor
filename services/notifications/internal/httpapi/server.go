// Package httpapi — HTTP-слой notifications. Клиентские эндпоинты идут через
// gateway, который после проверки JWT кладёт проверенный идентификатор в
// заголовок X-User-Id (клиент подменить его не может — gateway перезаписывает).
// Ошибки — problem+json (RFC 9457). Внутренний /internal/notify недоступен
// снаружи (gateway его не проксирует; сеть — приватный VPC).
package httpapi

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"traktor/notifications/internal/service"
	"traktor/notifications/internal/store"
)

type Server struct {
	svc *service.Notifier
}

func New(svc *service.Notifier) *Server { return &Server{svc: svc} }

func (s *Server) Routes() http.Handler {
	r := chi.NewRouter()
	r.Use(
		chimw.RequestID,
		chimw.RealIP,
		chimw.Recoverer,
		chimw.Timeout(20*time.Second),
	)

	// Клиентские (через gateway, требуют X-User-Id).
	r.Post("/v1/devices", s.registerDevice)
	r.Delete("/v1/devices/{token}", s.unregisterDevice)
	// Внутренние (сервис-сервис, не проксируются gateway наружу).
	r.Post("/internal/notify", s.notify)
	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	return r
}

// ── helpers ───────────────────────────────────────────────

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func problem(w http.ResponseWriter, status int, detail string) {
	w.Header().Set("Content-Type", "application/problem+json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"status": status, "detail": detail})
}

func decode(r *http.Request, v any) error {
	defer r.Body.Close()
	return json.NewDecoder(r.Body).Decode(v)
}

// ── handlers ──────────────────────────────────────────────

// registerDevice — POST /v1/devices. Тело: {token, platform, locale, appVersion}.
// Пользователь берётся из X-User-Id (проставлен gateway после проверки JWT).
func (s *Server) registerDevice(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-Id")
	if userID == "" {
		problem(w, http.StatusUnauthorized, "Требуется вход")
		return
	}
	var body struct {
		Token      string `json:"token"`
		Platform   string `json:"platform"`
		Locale     string `json:"locale"`
		AppVersion string `json:"appVersion"`
	}
	if err := decode(r, &body); err != nil || body.Token == "" {
		problem(w, http.StatusBadRequest, "Не передан токен устройства")
		return
	}
	err := s.svc.RegisterDevice(r.Context(), service.RegisterInput{
		UserID:     userID,
		Token:      body.Token,
		Platform:   store.Platform(body.Platform),
		Locale:     body.Locale,
		AppVersion: body.AppVersion,
	})
	if err != nil {
		problem(w, http.StatusBadRequest, "Не удалось зарегистрировать устройство")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// unregisterDevice — DELETE /v1/devices/{token}. Снятие регистрации токена.
func (s *Server) unregisterDevice(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("X-User-Id") == "" {
		problem(w, http.StatusUnauthorized, "Требуется вход")
		return
	}
	token := chi.URLParam(r, "token")
	if token == "" {
		problem(w, http.StatusBadRequest, "Не передан токен")
		return
	}
	if err := s.svc.UnregisterDevice(r.Context(), token); err != nil {
		problem(w, http.StatusBadRequest, "Не удалось снять регистрацию")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// notify — POST /internal/notify. Вызывается другими сервисами (позже — через
// консьюмер Pub/Sub из outbox). Тело: {userId, title, body, data}.
func (s *Server) notify(w http.ResponseWriter, r *http.Request) {
	var body struct {
		UserID string            `json:"userId"`
		Title  string            `json:"title"`
		Body   string            `json:"body"`
		Data   map[string]string `json:"data"`
	}
	if err := decode(r, &body); err != nil || body.UserID == "" {
		problem(w, http.StatusBadRequest, "Неверный запрос")
		return
	}
	delivered, err := s.svc.Notify(r.Context(), body.UserID, service.Notification{
		Title: body.Title,
		Body:  body.Body,
		Data:  body.Data,
	})
	if err != nil {
		problem(w, http.StatusInternalServerError, "Сбой рассылки")
		return
	}
	writeJSON(w, 200, map[string]any{"delivered": delivered})
}
