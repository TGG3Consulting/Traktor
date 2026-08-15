package httpapi

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"traktor/identity/internal/service"
	"traktor/identity/internal/store"
)

// Проверка человека и бейдж «Проверен» (ТЗ §2.3).

// submitVerification — POST /v1/me/verification
func (s *Server) submitVerification(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DocKind   string   `json:"docKind"`
		Documents []string `json:"documents"`
	}
	if err := decode(r, &body); err != nil {
		problem(w, http.StatusBadRequest, "Неверный запрос")
		return
	}
	claims := claimsFrom(r.Context())
	v, err := s.auth.SubmitVerification(r.Context(), claims.Sub, body.DocKind, body.Documents)
	if err != nil {
		failVerification(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, verificationJSON(*v))
}

// myVerification — GET /v1/me/verification. Состояние проверки для профиля.
func (s *Server) myVerification(w http.ResponseWriter, r *http.Request) {
	claims := claimsFrom(r.Context())
	v, err := s.auth.MyVerification(r.Context(), claims.Sub)
	if err != nil {
		// Заявки нет — это нормальное состояние профиля, а не ошибка экрана.
		writeJSON(w, http.StatusOK, map[string]any{"status": "none"})
		return
	}
	writeJSON(w, http.StatusOK, verificationJSON(*v))
}

// verificationQueue — GET /v1/moderation/verifications
func (s *Server) verificationQueue(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := s.auth.VerificationQueue(r.Context(), limit)
	if err != nil {
		problem(w, http.StatusInternalServerError, "Не удалось получить очередь")
		return
	}
	out := make([]map[string]any, 0, len(items))
	for _, v := range items {
		row := verificationJSON(v)
		// Модератор сверяет документ с профилем, а не с идентификатором.
		row["userId"] = v.UserID
		row["userName"] = v.UserName
		row["userPhone"] = v.UserPhone
		out = append(out, row)
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": out})
}

// reviewVerification — POST /v1/moderation/verifications/{id}/review
func (s *Server) reviewVerification(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Approve bool   `json:"approve"`
		Reason  string `json:"reason"`
	}
	if err := decode(r, &body); err != nil {
		problem(w, http.StatusBadRequest, "Неверный запрос")
		return
	}
	claims := claimsFrom(r.Context())
	v, err := s.auth.ReviewVerification(r.Context(), claims.Sub, chi.URLParam(r, "id"),
		body.Approve, body.Reason)
	if err != nil {
		failVerification(w, err)
		return
	}
	writeJSON(w, http.StatusOK, verificationJSON(*v))
}

func verificationJSON(v store.Verification) map[string]any {
	out := map[string]any{
		"id":        v.ID,
		"docKind":   v.DocKind,
		"documents": v.Documents,
		"status":    v.Status,
		"statusRu":  verifyStatusRU(v.Status),
		"reason":    v.Reason,
		"createdAt": v.CreatedAt.Format(time.RFC3339),
	}
	if v.ReviewedAt != nil {
		out["reviewedAt"] = v.ReviewedAt.Format(time.RFC3339)
	}
	return out
}

func verifyStatusRU(s string) string {
	switch s {
	case store.VerifyPending:
		return "на проверке"
	case store.VerifyApproved:
		return "проверен"
	case store.VerifyRejected:
		return "отклонено"
	default:
		return "не подавалась"
	}
}

func failVerification(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, service.ErrNoDocuments):
		problem(w, http.StatusBadRequest, "Приложите фото документа — модератору нужно что-то смотреть")
	case errors.Is(err, service.ErrManyDocs):
		problem(w, http.StatusBadRequest, "Не больше четырёх снимков")
	case errors.Is(err, service.ErrBadDocKind):
		problem(w, http.StatusBadRequest, "Выберите тип документа")
	case errors.Is(err, service.ErrNeedNameCity):
		problem(w, http.StatusBadRequest, "Сначала заполните имя в профиле — документ не с чем сверить")
	case errors.Is(err, store.ErrVerifyPending):
		problem(w, http.StatusConflict, "Заявка уже на проверке — ответим в течение суток")
	case errors.Is(err, service.ErrVerifyClosed):
		problem(w, http.StatusConflict, "Заявка уже разобрана")
	case errors.Is(err, service.ErrNeedReason):
		problem(w, http.StatusBadRequest,
			"Объясните отказ — без причины человек не поймёт, что переснять")
	case errors.Is(err, store.ErrNotFound):
		problem(w, http.StatusNotFound, "Заявка не найдена")
	default:
		problem(w, http.StatusInternalServerError, "Не удалось выполнить действие")
	}
}
