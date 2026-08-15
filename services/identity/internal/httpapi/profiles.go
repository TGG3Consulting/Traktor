package httpapi

import (
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
)

// publicProfiles — публичные карточки пользователей для других сервисов
// (ТЗ §2.3 «чужой профиль»): имя, город, рейтинг, «на платформе с».
//
// Телефон здесь не отдаётся никогда: до сделки его не должен видеть никто, а
// в сделке стороны получают его отдельным запросом с проверкой участия. Это
// внутренний маршрут — шлюз его наружу не проксирует.
func (s *Server) publicProfiles(w http.ResponseWriter, r *http.Request) {
	raw := strings.TrimSpace(r.URL.Query().Get("ids"))
	if raw == "" {
		writeJSON(w, http.StatusOK, map[string]any{"items": []any{}})
		return
	}

	ids := strings.Split(raw, ",")
	// Ограничение на размер пачки: список откликов или лента торга — это
	// десятки строк, а не тысячи.
	if len(ids) > 100 {
		ids = ids[:100]
	}

	items := make([]map[string]any, 0, len(ids))
	for _, id := range ids {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		u, err := s.auth.Store().GetUserByID(r.Context(), id)
		if err != nil {
			// Пропавший пользователь не должен ломать весь список: остальные
			// карточки отдаём как есть.
			continue
		}
		items = append(items, map[string]any{
			"id":        u.ID,
			"name":      u.Name,
			"city":      u.City,
			"verified":  u.Verified,
			"createdAt": u.CreatedAt,
			// Рейтинг появится вместе с отзывами (ТЗ §2.13); поле есть сразу,
			// чтобы клиентам не пришлось менять разбор ответа.
			"rating":      0,
			"ratingCount": 0,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

// publicProfile — GET /v1/users/{id}. Чужая карточка целиком (ТЗ §2.3).
//
// Телефона здесь нет и быть не может: до сделки он скрыт, а в сделке стороны
// получают его отдельно, с проверкой участия.
func (s *Server) publicProfile(w http.ResponseWriter, r *http.Request) {
	u, err := s.auth.Store().GetUserByID(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		problem(w, http.StatusNotFound, "Пользователь не найден")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"id":        u.ID,
		"name":      u.Name,
		"city":      u.City,
		"verified":  u.Verified,
		"createdAt": u.CreatedAt,
	})
}
