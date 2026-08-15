// Package httpapi — HTTP-слой notifications. Клиентские эндпоинты идут через
// gateway, который после проверки JWT кладёт проверенный идентификатор в
// заголовок X-User-Id (клиент подменить его не может — gateway перезаписывает).
// Ошибки — problem+json (RFC 9457). Внутренний /internal/notify недоступен
// снаружи (gateway его не проксирует; сеть — приватный VPC).
package httpapi

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
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
	// Центр уведомлений (ТЗ §2.14).
	r.Get("/v1/notifications", s.feed)
	r.Post("/v1/notifications/read", s.markRead)
	r.Get("/v1/notifications/settings", s.prefs)
	r.Put("/v1/notifications/settings", s.savePrefs)
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
		Kind   string            `json:"kind"`
		Title  string            `json:"title"`
		Body   string            `json:"body"`
		Data   map[string]string `json:"data"`
	}
	if err := decode(r, &body); err != nil || body.UserID == "" {
		problem(w, http.StatusBadRequest, "Неверный запрос")
		return
	}
	delivered, err := s.svc.Notify(r.Context(), body.UserID, service.Notification{
		Kind:  body.Kind,
		Title: body.Title,
		Body:  body.Body,
		Data:  body.Data,
	})
	if err != nil {
		slog.Error("рассылка не удалась", "user", body.UserID, "title", body.Title, "err", err)
		problem(w, http.StatusInternalServerError, "Сбой рассылки")
		return
	}
	// Пишем каждую рассылку: без этого невозможно ответить на вопрос «почему
	// исполнителю не пришло уведомление» — то ли не отправляли, то ли у него
	// нет зарегистрированных устройств.
	slog.Info("уведомление отправлено",
		"user", body.UserID, "title", body.Title, "delivered", delivered)
	writeJSON(w, 200, map[string]any{"delivered": delivered})
}

// feed — GET /v1/notifications. Центр уведомлений: лента событий и счётчик
// непрочитанного (ТЗ §2.14). Push мог не дойти — здесь событие есть всегда.
func (s *Server) feed(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-Id")
	if userID == "" {
		problem(w, http.StatusUnauthorized, "Нужен вход")
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	items, unread, err := s.svc.Feed(r.Context(), userID, limit, offset)
	if err != nil {
		slog.Error("центр уведомлений недоступен", "user", userID, "err", err)
		problem(w, http.StatusInternalServerError, "Не удалось загрузить уведомления")
		return
	}

	out := make([]map[string]any, 0, len(items))
	for _, n := range items {
		out = append(out, map[string]any{
			"id":        n.ID,
			"kind":      n.Kind,
			"title":     n.Title,
			"body":      n.Body,
			"data":      n.Data,
			"read":      n.ReadAt != nil,
			"createdAt": n.CreatedAt,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": out, "unread": unread})
}

// markRead — POST /v1/notifications/read. Без списка идентификаторов отмечает
// прочитанным всё: это кнопка «Прочитать все» в шапке центра.
func (s *Server) markRead(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-Id")
	if userID == "" {
		problem(w, http.StatusUnauthorized, "Нужен вход")
		return
	}
	var body struct {
		IDs []string `json:"ids"`
	}
	if r.ContentLength > 0 {
		if err := decode(r, &body); err != nil {
			problem(w, http.StatusBadRequest, "Неверный запрос")
			return
		}
	}
	if err := s.svc.MarkRead(r.Context(), userID, body.IDs); err != nil {
		slog.Error("отметка прочтения не прошла", "user", userID, "err", err)
		problem(w, http.StatusInternalServerError, "Не удалось отметить прочитанным")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

type prefsBody struct {
	Auctions     *bool `json:"auctions"`
	Deals        *bool `json:"deals"`
	Chat         *bool `json:"chat"`
	NewJobs      *bool `json:"newJobs"`
	Marketing    *bool `json:"marketing"`
	QuietHours   *bool `json:"quietHours"`
	QuietFrom    *int  `json:"quietFrom"`
	QuietTo      *int  `json:"quietTo"`
	OutbidAlways *bool `json:"outbidAlways"`
}

func prefsJSON(p store.Prefs) map[string]any {
	return map[string]any{
		"auctions":     p.Auctions,
		"deals":        p.Deals,
		"chat":         p.Chat,
		"newJobs":      p.NewJobs,
		"marketing":    p.Marketing,
		"quietHours":   p.QuietHours,
		"quietFrom":    p.QuietFrom,
		"quietTo":      p.QuietTo,
		"outbidAlways": p.OutbidAlways,
	}
}

// prefs — GET /v1/notifications/settings.
func (s *Server) prefs(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-Id")
	if userID == "" {
		problem(w, http.StatusUnauthorized, "Нужен вход")
		return
	}
	p, err := s.svc.Prefs(r.Context(), userID)
	if err != nil {
		slog.Error("настройки уведомлений недоступны", "user", userID, "err", err)
		problem(w, http.StatusInternalServerError, "Не удалось загрузить настройки")
		return
	}
	writeJSON(w, http.StatusOK, prefsJSON(p))
}

// savePrefs — PUT /v1/notifications/settings. Приходят только изменённые поля:
// экран настроек переключает по одному тумблеру, а не переписывает всё разом.
func (s *Server) savePrefs(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-Id")
	if userID == "" {
		problem(w, http.StatusUnauthorized, "Нужен вход")
		return
	}
	var body prefsBody
	if err := decode(r, &body); err != nil {
		problem(w, http.StatusBadRequest, "Неверный запрос")
		return
	}

	p, err := s.svc.Prefs(r.Context(), userID)
	if err != nil {
		problem(w, http.StatusInternalServerError, "Не удалось загрузить настройки")
		return
	}
	setBool(&p.Auctions, body.Auctions)
	setBool(&p.Deals, body.Deals)
	setBool(&p.Chat, body.Chat)
	setBool(&p.NewJobs, body.NewJobs)
	setBool(&p.Marketing, body.Marketing)
	setBool(&p.QuietHours, body.QuietHours)
	setBool(&p.OutbidAlways, body.OutbidAlways)
	setInt(&p.QuietFrom, body.QuietFrom)
	setInt(&p.QuietTo, body.QuietTo)

	if err := s.svc.SavePrefs(r.Context(), p); err != nil {
		slog.Error("настройки не сохранились", "user", userID, "err", err)
		problem(w, http.StatusInternalServerError, "Не удалось сохранить настройки")
		return
	}
	saved, _ := s.svc.Prefs(r.Context(), userID)
	writeJSON(w, http.StatusOK, prefsJSON(saved))
}

func setBool(dst *bool, v *bool) {
	if v != nil {
		*dst = *v
	}
}

func setInt(dst *int, v *int) {
	if v != nil {
		*dst = *v
	}
}
