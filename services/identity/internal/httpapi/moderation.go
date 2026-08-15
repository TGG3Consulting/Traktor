package httpapi

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"traktor/identity/internal/service"
	"traktor/identity/internal/store"
)

// Управление пользователями у модерации (ТЗ §4.1, п.3 и 8).
//
// Телефон здесь виден — модератор разбирает жалобы и должен связаться с
// человеком. Это единственное место, где номер отдаётся не участнику сделки,
// и доступ к нему закрыт ролью.

// searchUsers — GET /v1/moderation/users?q=
func (s *Server) searchUsers(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	users, err := s.auth.SearchUsers(r.Context(), r.URL.Query().Get("q"), limit)
	if err != nil {
		// Без записи в журнал такая ошибка видна только как 500 на экране,
		// и причину приходится угадывать.
		slog.Error("identity: поиск пользователей", "err", err)
		problem(w, http.StatusInternalServerError, "Не удалось выполнить поиск")
		return
	}
	items := make([]map[string]any, 0, len(users))
	for _, u := range users {
		items = append(items, userAdminJSON(u))
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

// userCard — GET /v1/moderation/users/{id}
func (s *Server) userCard(w http.ResponseWriter, r *http.Request) {
	card, err := s.auth.UserCard(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		problem(w, http.StatusNotFound, "Пользователь не найден")
		return
	}
	history := make([]map[string]any, 0, len(card.History))
	for _, a := range card.History {
		history = append(history, map[string]any{
			"id":        a.ID,
			"action":    a.Action,
			"actionRu":  actionRU(a.Action),
			"reason":    a.Reason,
			"actorId":   a.ActorID,
			"createdAt": a.CreatedAt.Format(time.RFC3339),
		})
	}
	out := userAdminJSON(card.User)
	out["history"] = history
	writeJSON(w, http.StatusOK, out)
}

// setUserStatus — POST /v1/moderation/users/{id}/status
func (s *Server) setUserStatus(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Status string `json:"status"`
		Reason string `json:"reason"`
	}
	if err := decode(r, &body); err != nil {
		problem(w, http.StatusBadRequest, "Неверный запрос")
		return
	}
	claims := claimsFrom(r.Context())
	if claims == nil {
		problem(w, http.StatusUnauthorized, "Требуется вход")
		return
	}

	u, err := s.auth.SetStatus(r.Context(), claims.Sub, chi.URLParam(r, "id"),
		strings.TrimSpace(body.Status), body.Reason)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrBadStatus):
			problem(w, http.StatusBadRequest, "Неизвестное состояние")
		case errors.Is(err, service.ErrNeedReason):
			problem(w, http.StatusBadRequest,
				"Опишите причину — её увидит и человек, и следующий модератор")
		case errors.Is(err, service.ErrSelfSanction):
			problem(w, http.StatusBadRequest, "Нельзя применить к себе")
		case errors.Is(err, store.ErrNotFound):
			problem(w, http.StatusNotFound, "Пользователь не найден")
		default:
			problem(w, http.StatusInternalServerError, "Не удалось изменить состояние")
		}
		return
	}
	writeJSON(w, http.StatusOK, userAdminJSON(*u))
}

// requireModerator — раздел доступен только модерации. Роли приходят от шлюза,
// который проверил подпись токена.
func (s *Server) requireModerator(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims := claimsFrom(r.Context())
		if claims == nil {
			problem(w, http.StatusUnauthorized, "Требуется вход")
			return
		}
		for _, role := range claims.Roles {
			if role == "moderator" || role == "admin" {
				next.ServeHTTP(w, r)
				return
			}
		}
		problem(w, http.StatusForbidden, "Раздел доступен модерации")
	})
}

func userAdminJSON(u store.User) map[string]any {
	status := u.Status
	if status == "" {
		status = store.StatusActive
	}
	out := map[string]any{
		"id":        u.ID,
		"phone":     u.Phone,
		"name":      u.Name,
		"city":      u.City,
		"roles":     u.Roles,
		"verified":  u.Verified,
		"status":    status,
		"statusRu":  statusRU(status),
		"reason":    u.StatusReason,
		"createdAt": u.CreatedAt.Format(time.RFC3339),
	}
	if u.StatusAt != nil {
		out["statusAt"] = u.StatusAt.Format(time.RFC3339)
	}
	return out
}

func statusRU(s string) string {
	switch s {
	case store.StatusFrozen:
		return "ставки и отклики заморожены"
	case store.StatusBanned:
		return "доступ закрыт"
	default:
		return "работает"
	}
}

func actionRU(a string) string {
	switch a {
	case "status:active":
		return "ограничения сняты"
	case "status:frozen":
		return "заморожены ставки и отклики"
	case "status:banned":
		return "доступ закрыт"
	default:
		return a
	}
}
