// Package httpapi — HTTP-слой сервиса catalog.
//
// Справочник читают все: и заказчик в визарде задания, и исполнитель в визарде
// техники. Данные публичные (никаких PII), поэтому авторизация здесь не нужна —
// доступ снаружи ограничивает шлюз.
package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"traktor/catalog/internal/catalog"
	"traktor/catalog/internal/store"
)

type Server struct{ st store.Store }

func New(st store.Store) *Server { return &Server{st: st} }

func (s *Server) Routes() http.Handler {
	r := chi.NewRouter()
	r.Use(chimw.RequestID, chimw.RealIP, chimw.Recoverer)

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	r.Route("/v1/categories", func(r chi.Router) {
		r.Get("/", s.list)
		r.Get("/{id}", s.byID)
	})

	// Внутренний доступ для других сервисов: orders проверяет, что ставка
	// сделана своей активной техникой (ТЗ §2.9). Наружу gateway этот путь не
	// проксирует — сеть между сервисами приватная.
	r.Get("/internal/equipment/{id}", s.internalEquipment)

	// Техника исполнителя (ТЗ §2.5).
	r.Route("/v1/equipment", func(r chi.Router) {
		r.Get("/my", s.myEquipment)
		r.Post("/drafts", s.createEquipment)
		r.Get("/{id}", s.equipmentByID)
		r.Patch("/{id}", s.patchEquipment)
		r.Post("/{id}/submit", s.submitEquipment)
		r.Post("/{id}/archive", s.archiveEquipment)
	})
	return r
}

// list отдаёт дерево категорий. ?kind=work|unit сужает ветвь,
// ?flat=1 отдаёт плоский список (нужен экранам поиска по названию).
func (s *Server) list(w http.ResponseWriter, r *http.Request) {
	kind := catalog.Kind(r.URL.Query().Get("kind"))
	if kind != "" && kind != catalog.KindWork && kind != catalog.KindUnit {
		problem(w, http.StatusBadRequest, "invalid_kind", "kind может быть work или unit")
		return
	}

	items, err := s.st.List(r.Context(), kind)
	if err != nil {
		problem(w, http.StatusInternalServerError, "internal", "не удалось прочитать справочник")
		return
	}
	if items == nil {
		items = []catalog.Category{}
	}

	if r.URL.Query().Get("flat") == "1" {
		writeJSON(w, http.StatusOK, map[string]any{"items": items})
		return
	}
	tree := catalog.BuildTree(items)
	if tree == nil {
		tree = []catalog.Category{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": tree})
}

func (s *Server) byID(w http.ResponseWriter, r *http.Request) {
	c, err := s.st.ByID(r.Context(), chi.URLParam(r, "id"))
	if errors.Is(err, store.ErrNotFound) {
		problem(w, http.StatusNotFound, "not_found", "категория не найдена")
		return
	}
	if err != nil {
		problem(w, http.StatusInternalServerError, "internal", "не удалось прочитать категорию")
		return
	}
	writeJSON(w, http.StatusOK, c)
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

// problem — ошибка в формате problem+json, как у остальных сервисов: клиент
// показывает title человеку, code разбирает кодом.
func problem(w http.ResponseWriter, status int, code, title string) {
	w.Header().Set("Content-Type", "application/problem+json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"type": "about:blank", "status": status, "code": code, "title": title,
	})
}
