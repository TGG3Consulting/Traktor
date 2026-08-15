// Package httpapi — HTTP-слой сервиса media: выдача ссылок на загрузку.
//
// Пользователь приходит через gateway, поэтому идентификатор берётся из
// проверенного заголовка X-User-Id — по нему файлы раскладываются по папкам.
package httpapi

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"traktor/media/internal/storage"
)

type Server struct{ store *storage.S3 }

func New(store *storage.S3) *Server { return &Server{store: store} }

func (s *Server) Routes() http.Handler {
	r := chi.NewRouter()
	r.Use(chimw.RequestID, chimw.RealIP, chimw.Recoverer, chimw.Timeout(15*time.Second))

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	r.Post("/v1/media/uploads", s.createUpload)
	return r
}

type uploadBody struct {
	// ContentType — тип файла: по нему выбирается расширение и отсекается
	// всё, что не картинка и не документ.
	ContentType string `json:"contentType"`
	// Folder — для чего файл: equipment, jobs, docs.
	Folder string `json:"folder"`
	// Count — сколько ссылок нужно разом: галерея грузится пачкой.
	Count int `json:"count"`
}

func (s *Server) createUpload(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-Id")
	if userID == "" {
		problem(w, http.StatusUnauthorized, "нужен вход")
		return
	}

	var body uploadBody
	defer r.Body.Close()
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		problem(w, http.StatusBadRequest, "неверный запрос")
		return
	}
	if body.Count <= 0 {
		body.Count = 1
	}
	if body.Count > 8 {
		body.Count = 8
	}

	links := make([]*storage.UploadLink, 0, body.Count)
	for i := 0; i < body.Count; i++ {
		link, err := s.store.Link(r.Context(), userID, body.Folder, body.ContentType)
		if err != nil {
			if errors.Is(err, storage.ErrUnsupportedType) {
				problem(w, http.StatusUnsupportedMediaType,
					"принимаем фотографии JPEG, PNG, WebP, HEIC и документы PDF")
				return
			}
			slog.Error("ссылка на загрузку не выдана", "user", userID, "err", err)
			problem(w, http.StatusInternalServerError, "хранилище недоступно")
			return
		}
		links = append(links, link)
	}

	writeJSON(w, http.StatusOK, map[string]any{"items": links})
}

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
