package httpapi

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/golang-jwt/jwt/v5"

	"traktor/orders/internal/job"
	"traktor/orders/internal/profiles"
)

type openChatBody struct {
	// С кем открыть переписку. Заказчик указывает исполнителя; исполнитель
	// поле не заполняет — второй стороной всегда заказчик.
	OwnerID string `json:"ownerId"`
}

type messageBody struct {
	Text string `json:"text"`
}

func (s *Server) openChat(w http.ResponseWriter, r *http.Request) {
	var body openChatBody
	if r.ContentLength > 0 && !decode(w, r, &body) {
		return
	}
	chat, err := s.svc.OpenChat(r.Context(), r.Header.Get(userHeader),
		chi.URLParam(r, "id"), body.OwnerID)
	if err != nil {
		failChat(w, err)
		return
	}
	writeJSON(w, http.StatusOK, chat)
}

func (s *Server) myChats(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	me := r.Header.Get(userHeader)

	items, err := s.svc.MyChats(r.Context(), me, limit, offset)
	if err != nil {
		failChat(w, err)
		return
	}

	// Имя собеседника — то, по чему список чатов вообще читается.
	ids := make([]string, 0, len(items))
	for _, c := range items {
		ids = append(ids, other(c, me))
	}
	people := s.svc.Profiles(r.Context(), ids)

	out := make([]map[string]any, 0, len(items))
	for _, c := range items {
		row := map[string]any{
			"id":            c.ID,
			"jobId":         c.JobID,
			"jobTitle":      c.JobTitle,
			"kind":          c.Kind,
			"lastText":      c.LastText,
			"lastMessageAt": c.LastMessageAt,
			"unread":        c.Unread,
			"createdAt":     c.CreatedAt,
		}
		if p, ok := people[other(c, me)]; ok {
			row["peerName"] = profiles.DisplayName(p, "Собеседник")
		} else {
			row["peerName"] = "Собеседник"
		}
		out = append(out, row)
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": out})
}

func (s *Server) chat(w http.ResponseWriter, r *http.Request) {
	c, err := s.svc.Chat(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "chatId"))
	if err != nil {
		failChat(w, err)
		return
	}
	me := r.Header.Get(userHeader)
	people := s.svc.Profiles(r.Context(), []string{other(*c, me)})

	writeJSON(w, http.StatusOK, map[string]any{
		"id":       c.ID,
		"jobId":    c.JobID,
		"kind":     c.Kind,
		"peerName": profiles.DisplayName(people[other(*c, me)], "Собеседник"),
	})
}

func (s *Server) messages(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	msgs, err := s.svc.Messages(r.Context(), r.Header.Get(userHeader),
		chi.URLParam(r, "chatId"), limit, offset)
	if err != nil {
		failChat(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": msgs})
}

func (s *Server) sendMessage(w http.ResponseWriter, r *http.Request) {
	var body messageBody
	if !decode(w, r, &body) {
		return
	}
	msg, masked, err := s.svc.SendMessage(r.Context(), r.Header.Get(userHeader),
		chi.URLParam(r, "chatId"), body.Text)
	if err != nil {
		failChat(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"message": msg,
		// Клиент показывает мягкое предупреждение: человек должен понимать,
		// почему его номер в сообщении заменился.
		"contactsMasked": masked,
	})
}

// chatRealtimeToken — токен подписки на канал переписки (ADR-6).
//
// Канал чата закрыт: Centrifugo пускает в него только по токену, а выдать его
// может лишь тот, кто знает участников, — то есть этот сервис.
func (s *Server) chatRealtimeToken(w http.ResponseWriter, r *http.Request) {
	chatID := chi.URLParam(r, "chatId")
	c, err := s.svc.Chat(r.Context(), r.Header.Get(userHeader), chatID)
	if err != nil {
		failChat(w, err)
		return
	}
	if s.realtimeSecret == "" {
		problem(w, http.StatusServiceUnavailable, "realtime_off",
			"живые обновления выключены на этом стенде")
		return
	}

	exp := time.Now().Add(time.Hour)
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":     r.Header.Get(userHeader),
		"channel": "chat:" + c.ID,
		"exp":     exp.Unix(),
	})
	signed, err := token.SignedString([]byte(s.realtimeSecret))
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"token":     signed,
		"channel":   "chat:" + c.ID,
		"expiresAt": exp.UTC(),
	})
}

func other(c job.Chat, me string) string {
	if c.ClientID == me {
		return c.OwnerID
	}
	return c.ClientID
}

func failChat(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, job.ErrChatNotFound):
		problem(w, http.StatusNotFound, "chat_not_found", "переписка не найдена")
	case errors.Is(err, job.ErrChatForbidden):
		problem(w, http.StatusForbidden, "chat_forbidden", "это чужая переписка")
	case errors.Is(err, job.ErrChatClosed):
		problem(w, http.StatusConflict, "chat_closed", "переписка по этому заданию закрыта")
	case errors.Is(err, job.ErrEmptyMessage):
		problem(w, http.StatusBadRequest, "empty_message", "сообщение пустое")
	default:
		fail(w, err)
	}
}
