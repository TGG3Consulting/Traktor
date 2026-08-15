package httpapi

import (
	"errors"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"traktor/catalog/internal/catalog"
	"traktor/catalog/internal/store"
)

// Правка справочника у модерации (ТЗ §4.1, п.5).
//
// Пока категории живут только в миграции, добавление вида работ требует
// выката: владелец не может отреагировать на спрос, пока не дойдут руки у
// разработчика. Здесь тот же справочник правится на ходу.

type categoryBody struct {
	ParentID *string             `json:"parentId"`
	Kind     string              `json:"kind"`
	Slug     string              `json:"slug"`
	Name     catalog.Name        `json:"name"`
	Icon     string              `json:"icon"`
	Specs    []catalog.SpecField `json:"specTemplate"`
	Sort     int                 `json:"sortOrder"`
}

// allCategories — GET /v1/moderation/categories?kind=
//
// Вместе со скрытыми: модератор должен видеть и то, что убрал, иначе вернуть
// категорию обратно невозможно.
func (s *Server) allCategories(w http.ResponseWriter, r *http.Request) {
	kind := catalog.Kind(strings.TrimSpace(r.URL.Query().Get("kind")))
	if kind != "" && !catalog.ValidKind(kind) {
		problem(w, http.StatusBadRequest, "bad_kind", "ветвь — work или unit")
		return
	}
	items, err := s.st.ListAll(r.Context(), kind)
	if err != nil {
		problem(w, http.StatusInternalServerError, "internal", "не удалось получить справочник")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

// createCategory — POST /v1/moderation/categories
func (s *Server) createCategory(w http.ResponseWriter, r *http.Request) {
	var body categoryBody
	if !decodeBody(w, r, &body) {
		return
	}

	kind := catalog.Kind(strings.TrimSpace(body.Kind))
	if !catalog.ValidKind(kind) {
		failCategory(w, catalog.ErrBadKind)
		return
	}
	slug, err := catalog.ValidateSlug(body.Slug)
	if err != nil {
		failCategory(w, err)
		return
	}
	name, err := catalog.ValidateName(body.Name)
	if err != nil {
		failCategory(w, err)
		return
	}
	specs, err := catalog.ValidateSpec(body.Specs)
	if err != nil {
		failCategory(w, err)
		return
	}
	if taken, err := s.st.SlugTaken(r.Context(), slug, ""); err != nil {
		problem(w, http.StatusInternalServerError, "internal", "не удалось проверить ключ")
		return
	} else if taken {
		failCategory(w, catalog.ErrSlugTaken)
		return
	}
	parent, err := s.checkParent(r, body.ParentID, kind, "")
	if err != nil {
		failCategory(w, err)
		return
	}

	c := catalog.Category{
		ID:           uuid.NewString(),
		ParentID:     parent,
		Kind:         kind,
		Slug:         slug,
		Name:         name,
		Icon:         iconOr(body.Icon),
		SpecTemplate: specs,
		SortOrder:    sortOr(body.Sort),
		Active:       true,
	}
	if err := s.st.CreateCategory(r.Context(), c); err != nil {
		problem(w, http.StatusInternalServerError, "internal", "не удалось создать категорию")
		return
	}
	writeJSON(w, http.StatusCreated, c)
}

// updateCategory — PATCH /v1/moderation/categories/{id}
//
// Ключ и ветвь не меняются: по ключу сходятся отчёты за прошлые месяцы,
// а сменить ветвь значит оторвать категорию от уже созданных заданий.
func (s *Server) updateCategory(w http.ResponseWriter, r *http.Request) {
	var body categoryBody
	if !decodeBody(w, r, &body) {
		return
	}
	id := chi.URLParam(r, "id")

	current, err := s.st.AnyByID(r.Context(), id)
	if err != nil {
		problem(w, http.StatusNotFound, "not_found", "категория не найдена")
		return
	}
	name, err := catalog.ValidateName(body.Name)
	if err != nil {
		failCategory(w, err)
		return
	}
	specs, err := catalog.ValidateSpec(body.Specs)
	if err != nil {
		failCategory(w, err)
		return
	}
	parent, err := s.checkParent(r, body.ParentID, current.Kind, id)
	if err != nil {
		failCategory(w, err)
		return
	}

	current.ParentID = parent
	current.Name = name
	current.Icon = iconOr(body.Icon)
	current.SpecTemplate = specs
	current.SortOrder = sortOr(body.Sort)
	if err := s.st.UpdateCategory(r.Context(), current); err != nil {
		problem(w, http.StatusInternalServerError, "internal", "не удалось сохранить категорию")
		return
	}
	writeJSON(w, http.StatusOK, current)
}

// toggleCategory — POST /v1/moderation/categories/{id}/visibility
//
// Удаления нет: на категорию ссылаются уже созданные задания и техника.
// Скрытая категория исчезает из визарда, но история остаётся читаемой.
func (s *Server) toggleCategory(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Active bool `json:"active"`
	}
	if !decodeBody(w, r, &body) {
		return
	}
	id := chi.URLParam(r, "id")

	if !body.Active {
		// Скрыть родителя, оставив потомков видимыми, — значит показать людям
		// ветку без входа в неё.
		has, err := s.st.HasChildren(r.Context(), id)
		if err != nil {
			problem(w, http.StatusInternalServerError, "internal", "не удалось проверить вложенные")
			return
		}
		if has {
			failCategory(w, catalog.ErrHasChildren)
			return
		}
	}
	if err := s.st.SetCategoryActive(r.Context(), id, body.Active); err != nil {
		problem(w, http.StatusNotFound, "not_found", "категория не найдена")
		return
	}
	c, err := s.st.AnyByID(r.Context(), id)
	if err != nil {
		problem(w, http.StatusNotFound, "not_found", "категория не найдена")
		return
	}
	writeJSON(w, http.StatusOK, c)
}

// checkParent проверяет родителя: он должен существовать, быть из той же
// ветви и не быть самой категорией.
func (s *Server) checkParent(r *http.Request, parentID *string, kind catalog.Kind, selfID string) (*string, error) {
	if parentID == nil || strings.TrimSpace(*parentID) == "" {
		return nil, nil
	}
	id := strings.TrimSpace(*parentID)
	if id == selfID {
		return nil, catalog.ErrOwnParent
	}
	parent, err := s.st.AnyByID(r.Context(), id)
	if err != nil {
		return nil, err
	}
	if parent.Kind != kind {
		return nil, catalog.ErrParentKind
	}
	return &id, nil
}

// iconOr — имя иконки Phosphor. Пустое поле заменяем на нейтральное: пустая
// иконка в списке выглядит как поломка (правило 8).
func iconOr(icon string) string {
	icon = strings.TrimSpace(icon)
	if icon == "" {
		return "wrench"
	}
	return icon
}

// sortOr — место в списке. Ноль означает «не задано»: такие категории должны
// оказаться в конце, а не выше всех.
func sortOr(order int) int {
	if order <= 0 {
		return 100
	}
	return order
}

func failCategory(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, catalog.ErrNoName):
		problem(w, http.StatusBadRequest, "no_name",
			"название нужно на всех трёх языках — пустая строка выглядит как поломка")
	case errors.Is(err, catalog.ErrBadSlug):
		problem(w, http.StatusBadRequest, "bad_slug", "ключ — латиница, цифры и дефис")
	case errors.Is(err, catalog.ErrSlugTaken):
		problem(w, http.StatusConflict, "slug_taken", "такой ключ уже занят")
	case errors.Is(err, catalog.ErrBadKind):
		problem(w, http.StatusBadRequest, "bad_kind", "ветвь — work или unit")
	case errors.Is(err, catalog.ErrBadSpec):
		problem(w, http.StatusBadRequest, "bad_spec",
			"поле характеристик описано неверно — проверьте ключ, тип и подпись")
	case errors.Is(err, catalog.ErrOwnParent):
		problem(w, http.StatusBadRequest, "own_parent", "категория не может быть своим родителем")
	case errors.Is(err, catalog.ErrParentKind):
		problem(w, http.StatusBadRequest, "parent_kind", "родитель из другой ветви дерева")
	case errors.Is(err, catalog.ErrHasChildren):
		problem(w, http.StatusConflict, "has_children",
			"сначала скройте вложенные категории — иначе люди увидят ветку без входа в неё")
	case errors.Is(err, store.ErrNotFound):
		problem(w, http.StatusNotFound, "not_found", "категория не найдена")
	default:
		problem(w, http.StatusInternalServerError, "internal", "не удалось выполнить действие")
	}
}
