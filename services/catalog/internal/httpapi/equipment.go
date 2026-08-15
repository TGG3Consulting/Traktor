package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"traktor/catalog/internal/catalog"
)

// Техника исполнителя (ТЗ §2.5): список «Моя техника» и визард из четырёх
// шагов. Черновик сохраняется на каждом шаге, поэтому визард переживает
// закрытие приложения — человек возвращается туда, где остановился.

const userHeader = "X-User-Id"

type equipmentBody struct {
	CategoryID *string         `json:"categoryId"`
	Brand      *string         `json:"brand"`
	Model      *string         `json:"model"`
	Year       *int            `json:"year"`
	Specs      *map[string]any `json:"specs"`

	PriceHour  *int64 `json:"priceHour"`
	PriceShift *int64 `json:"priceShift"`
	PriceDay   *int64 `json:"priceDay"`
	MinHours   *int   `json:"minHours"`
	Delivery   *int64 `json:"delivery"`

	CrewSize  *int   `json:"crewSize"`
	CrewPrice *int64 `json:"crewPrice"`

	Photos *[]string `json:"photos"`
	Docs   *[]string `json:"docs"`

	DraftStep *int `json:"draftStep"`
}

// myEquipment — GET /v1/equipment/my. Список машин исполнителя.
func (s *Server) myEquipment(w http.ResponseWriter, r *http.Request) {
	owner := r.Header.Get(userHeader)
	if owner == "" {
		problem(w, http.StatusUnauthorized, "unauthorized", "нужен вход")
		return
	}
	items, err := s.st.EquipmentByOwner(r.Context(), owner)
	if err != nil {
		problem(w, http.StatusInternalServerError, "internal", "не удалось прочитать технику")
		return
	}
	s.withCategoryNames(r, items)
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

// createEquipment — POST /v1/equipment/drafts. Начало визарда.
func (s *Server) createEquipment(w http.ResponseWriter, r *http.Request) {
	owner := r.Header.Get(userHeader)
	if owner == "" {
		problem(w, http.StatusUnauthorized, "unauthorized", "нужен вход")
		return
	}
	var body equipmentBody
	if r.ContentLength > 0 && !decodeBody(w, r, &body) {
		return
	}

	now := time.Now().UTC()
	e := &catalog.Equipment{
		ID:        uuid.NewString(),
		OwnerID:   owner,
		Status:    catalog.StatusDraft,
		DraftStep: 1,
		Photos:    []string{},
		Docs:      []string{},
		Specs:     map[string]any{},
		CreatedAt: now,
		UpdatedAt: now,
	}
	apply(e, body)
	catalog.Normalize(e)

	if e.CategoryID != "" {
		if _, err := s.st.ByID(r.Context(), e.CategoryID); err != nil {
			problem(w, http.StatusBadRequest, "unknown_category", "такой категории нет")
			return
		}
	}
	if err := s.st.CreateEquipment(r.Context(), e); err != nil {
		problem(w, http.StatusInternalServerError, "internal", "не удалось сохранить черновик")
		return
	}
	writeJSON(w, http.StatusCreated, e)
}

// patchEquipment — PATCH /v1/equipment/{id}. Шаг визарда или правка карточки.
func (s *Server) patchEquipment(w http.ResponseWriter, r *http.Request) {
	e, ok := s.mine(w, r)
	if !ok {
		return
	}
	var body equipmentBody
	if !decodeBody(w, r, &body) {
		return
	}

	if err := catalog.CanEdit(e, r.Header.Get(userHeader)); err != nil {
		failEquipment(w, err)
		return
	}
	apply(e, body)
	catalog.Normalize(e)
	e.UpdatedAt = time.Now().UTC()

	if e.CategoryID != "" {
		if _, err := s.st.ByID(r.Context(), e.CategoryID); err != nil {
			problem(w, http.StatusBadRequest, "unknown_category", "такой категории нет")
			return
		}
	}
	if err := s.st.UpdateEquipment(r.Context(), e); err != nil {
		failEquipment(w, err)
		return
	}
	writeJSON(w, http.StatusOK, e)
}

// submitEquipment — POST /v1/equipment/{id}/submit. Финал визарда.
//
// С документами карточка уходит на проверку, без них публикуется сразу как
// «Без проверки»: держать исполнителя без заказов сутки ради бейджа неверно,
// а разница в скоринге и так подталкивает документы приложить (ТЗ §2.5).
func (s *Server) submitEquipment(w http.ResponseWriter, r *http.Request) {
	e, ok := s.mine(w, r)
	if !ok {
		return
	}
	if e.Status == catalog.StatusPending {
		problem(w, http.StatusConflict, "already_pending", "карточка уже на проверке")
		return
	}
	if err := catalog.ValidateForPublish(e, time.Now()); err != nil {
		var ve *catalog.ValidationError
		if errors.As(err, &ve) {
			writeJSON(w, http.StatusUnprocessableEntity, map[string]any{
				"code":   "validation",
				"title":  "Карточка заполнена не полностью",
				"fields": ve.Fields,
			})
			return
		}
		failEquipment(w, err)
		return
	}

	e.Status = catalog.StatusAfterSubmit(len(e.Docs) > 0)
	e.RejectReason = ""
	e.DraftStep = 4
	e.UpdatedAt = time.Now().UTC()
	if err := s.st.UpdateEquipment(r.Context(), e); err != nil {
		failEquipment(w, err)
		return
	}
	writeJSON(w, http.StatusOK, e)
}

// archiveEquipment — POST /v1/equipment/{id}/archive. Снять машину.
func (s *Server) archiveEquipment(w http.ResponseWriter, r *http.Request) {
	e, ok := s.mine(w, r)
	if !ok {
		return
	}
	e.Status = catalog.StatusArchived
	e.UpdatedAt = time.Now().UTC()
	if err := s.st.UpdateEquipment(r.Context(), e); err != nil {
		failEquipment(w, err)
		return
	}
	writeJSON(w, http.StatusOK, e)
}

// equipmentByID — GET /v1/equipment/{id}.
func (s *Server) equipmentByID(w http.ResponseWriter, r *http.Request) {
	e, ok := s.mine(w, r)
	if !ok {
		return
	}
	list := []catalog.Equipment{*e}
	s.withCategoryNames(r, list)
	writeJSON(w, http.StatusOK, list[0])
}

// mine достаёт технику и проверяет, что она принадлежит запрашивающему.
func (s *Server) mine(w http.ResponseWriter, r *http.Request) (*catalog.Equipment, bool) {
	owner := r.Header.Get(userHeader)
	if owner == "" {
		problem(w, http.StatusUnauthorized, "unauthorized", "нужен вход")
		return nil, false
	}
	e, err := s.st.EquipmentByID(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		failEquipment(w, err)
		return nil, false
	}
	if e.OwnerID != owner {
		failEquipment(w, catalog.ErrEquipmentForeign)
		return nil, false
	}
	return e, true
}

// withCategoryNames подмешивает названия категорий: в карточке нужно «Земляные
// работы», а не идентификатор.
func (s *Server) withCategoryNames(r *http.Request, items []catalog.Equipment) {
	for i := range items {
		if items[i].CategoryID == "" {
			continue
		}
		c, err := s.st.ByID(r.Context(), items[i].CategoryID)
		if err != nil {
			continue
		}
		name := c.Name
		items[i].CategoryName = &name
	}
}

func apply(e *catalog.Equipment, b equipmentBody) {
	if b.CategoryID != nil {
		e.CategoryID = strings.TrimSpace(*b.CategoryID)
	}
	if b.Brand != nil {
		e.Brand = *b.Brand
	}
	if b.Model != nil {
		e.Model = *b.Model
	}
	if b.Year != nil {
		e.Year = b.Year
	}
	if b.Specs != nil {
		e.Specs = *b.Specs
	}
	if b.PriceHour != nil {
		e.PriceHour = b.PriceHour
	}
	if b.PriceShift != nil {
		e.PriceShift = b.PriceShift
	}
	if b.PriceDay != nil {
		e.PriceDay = b.PriceDay
	}
	if b.MinHours != nil {
		e.MinHours = b.MinHours
	}
	if b.Delivery != nil {
		e.Delivery = b.Delivery
	}
	if b.CrewSize != nil {
		e.CrewSize = *b.CrewSize
	}
	if b.CrewPrice != nil {
		e.CrewPrice = b.CrewPrice
	}
	if b.Photos != nil {
		e.Photos = *b.Photos
	}
	if b.Docs != nil {
		e.Docs = *b.Docs
	}
	if b.DraftStep != nil {
		e.DraftStep = *b.DraftStep
	}
}

func decodeBody(w http.ResponseWriter, r *http.Request, v any) bool {
	defer r.Body.Close()
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		problem(w, http.StatusBadRequest, "bad_request", "не удалось разобрать запрос")
		return false
	}
	return true
}

func failEquipment(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, catalog.ErrEquipmentNotFound):
		problem(w, http.StatusNotFound, "equipment_not_found", "техника не найдена")
	case errors.Is(err, catalog.ErrEquipmentForeign):
		problem(w, http.StatusForbidden, "equipment_forbidden", "это чужая техника")
	case errors.Is(err, catalog.ErrEquipmentStatus):
		problem(w, http.StatusConflict, "equipment_pending",
			"пока карточка на проверке, править её нельзя")
	default:
		problem(w, http.StatusInternalServerError, "internal", "внутренняя ошибка")
	}
}
