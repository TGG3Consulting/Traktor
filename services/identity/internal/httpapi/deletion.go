package httpapi

import (
	"errors"
	"net/http"
	"time"

	"traktor/identity/internal/service"
)

// Удаление аккаунта с отсрочкой (ТЗ §2.3, §4.3).

// requestDeletion — DELETE /v1/me.
func (s *Server) requestDeletion(w http.ResponseWriter, r *http.Request) {
	claims := claimsFrom(r.Context())
	until, err := s.auth.RequestDeletion(r.Context(), claims.Sub)
	if err != nil && !errors.Is(err, service.ErrAlreadyDeleting) {
		problem(w, http.StatusInternalServerError, "Не удалось поставить аккаунт на удаление")
		return
	}
	// Повторный запрос — не ошибка: человек мог нажать дважды. Отвечаем тем
	// же сроком, чтобы экран показал одно и то же.
	writeJSON(w, http.StatusOK, map[string]any{
		"deleteAfter": until.Format(time.RFC3339),
		"graceDays":   int(service.DeleteGrace.Hours() / 24),
		"note": "Аккаунт удалится через 30 дней. Войдите в это время — " +
			"и удаление отменится.",
	})
}

// cancelDeletion — POST /v1/me/restore. Явная отмена из профиля: вход её тоже
// отменяет, но человек, уже открывший приложение, должен видеть кнопку.
func (s *Server) cancelDeletion(w http.ResponseWriter, r *http.Request) {
	claims := claimsFrom(r.Context())
	if err := s.auth.CancelDeletion(r.Context(), claims.Sub); err != nil {
		problem(w, http.StatusInternalServerError, "Не удалось отменить удаление")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"deleteAfter": nil})
}
