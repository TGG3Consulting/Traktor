package httpapi

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"traktor/catalog/internal/catalog"
)

// Очередь проверки техники (ТЗ §4.1, п.2).
//
// Карточка с документами ждёт модератора не дольше суток — это обещание,
// данное исполнителю на последнем шаге визарда. Поэтому очередь отсортирована
// по возрасту: первым разбирается то, что висит дольше всех.

const rolesHeader = "X-User-Roles"

// requireModerator пускает дальше только модератора. Роли приходят от шлюза,
// который их проверил по подписи токена; подделать заголовок снаружи нельзя —
// шлюз стирает его на входе.
func (s *Server) requireModerator(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		roles := strings.Split(r.Header.Get(rolesHeader), ",")
		for _, role := range roles {
			if strings.TrimSpace(role) == "moderator" || strings.TrimSpace(role) == "admin" {
				next.ServeHTTP(w, r)
				return
			}
		}
		problem(w, http.StatusForbidden, "not_moderator", "раздел доступен модерации")
	})
}

// pendingEquipment — GET /v1/moderation/equipment. Очередь на проверку.
func (s *Server) pendingEquipment(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	items, err := s.st.PendingEquipment(r.Context(), limit)
	if err != nil {
		problem(w, http.StatusInternalServerError, "internal", "не удалось прочитать очередь")
		return
	}
	s.withCategoryNames(r, items)

	now := time.Now()
	out := make([]map[string]any, 0, len(items))
	for _, e := range items {
		out = append(out, map[string]any{
			"id":      e.ID,
			"ownerId": e.OwnerID,
			"title":   e.Title(),
			"year":    e.Year,
			"specs":   e.Specs,
			"photos":  e.Photos,
			// Документы видит только модерация — здесь они и нужны.
			"docs":         e.Docs,
			"categoryName": e.CategoryName,
			"createdAt":    e.CreatedAt,
			"updatedAt":    e.UpdatedAt,
			// Сколько часов карточка ждёт: обещали проверить за сутки.
			"waitingHours": int(now.Sub(e.UpdatedAt).Hours()),
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": out})
}

type moderationBody struct {
	// Reason обязателен при отказе: «отклонено» без причины человек не сможет
	// исправить, и он просто уйдёт с площадки.
	Reason string `json:"reason"`
}

// approveEquipment — POST /v1/moderation/equipment/{id}/approve.
func (s *Server) approveEquipment(w http.ResponseWriter, r *http.Request) {
	e, ok := s.pending(w, r)
	if !ok {
		return
	}

	e.Status = catalog.StatusVerified
	e.RejectReason = ""
	e.UpdatedAt = time.Now().UTC()
	if err := s.st.UpdateEquipment(r.Context(), e); err != nil {
		failEquipment(w, err)
		return
	}

	s.notifyOwner(r, e, "Техника одобрена",
		e.Title()+" прошла проверку — теперь у карточки бейдж «Проверен»")
	writeJSON(w, http.StatusOK, e)
}

// rejectEquipment — POST /v1/moderation/equipment/{id}/reject.
func (s *Server) rejectEquipment(w http.ResponseWriter, r *http.Request) {
	e, ok := s.pending(w, r)
	if !ok {
		return
	}
	var body moderationBody
	if r.ContentLength > 0 && !decodeBody(w, r, &body) {
		return
	}
	reason := strings.TrimSpace(body.Reason)
	if reason == "" {
		problem(w, http.StatusBadRequest, "reason_required",
			"укажите причину — без неё человек не поймёт, что исправить")
		return
	}

	e.Status = catalog.StatusRejected
	e.RejectReason = reason
	e.UpdatedAt = time.Now().UTC()
	if err := s.st.UpdateEquipment(r.Context(), e); err != nil {
		failEquipment(w, err)
		return
	}

	s.notifyOwner(r, e, "Техника отклонена", reason)
	writeJSON(w, http.StatusOK, e)
}

// pending достаёт карточку и убеждается, что она действительно ждёт проверки:
// одобрять уже одобренное или чужой черновик модератору незачем.
func (s *Server) pending(w http.ResponseWriter, r *http.Request) (*catalog.Equipment, bool) {
	e, err := s.st.EquipmentByID(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		failEquipment(w, err)
		return nil, false
	}
	if e.Status != catalog.StatusPending {
		problem(w, http.StatusConflict, "not_pending", "карточка не ждёт проверки")
		return nil, false
	}
	return e, true
}

func (s *Server) notifyOwner(r *http.Request, e *catalog.Equipment, title, body string) {
	s.notify.Send(r.Context(), e.OwnerID, title, body, map[string]string{
		"kind":        "equipment",
		"route":       "/equipment",
		"equipmentId": e.ID,
	})
}
