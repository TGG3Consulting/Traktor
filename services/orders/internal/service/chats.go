package service

import (
	"context"
	"strings"

	"github.com/google/uuid"

	"traktor/orders/internal/job"
)

// OpenChat — открыть переписку по заданию (ТЗ §2.12).
//
// Чат создаётся между заказчиком и конкретным исполнителем. Заказчик открывает
// его из отклика («задать вопрос»), исполнитель — из деталки задания. Один чат
// на пару: иначе история разъедется по веткам и стороны потеряют контекст.
func (s *Service) OpenChat(ctx context.Context, userID, jobID, otherID string) (*job.Chat, error) {
	j, err := s.st.ByID(ctx, jobID)
	if err != nil {
		return nil, err
	}
	if err := job.CanChat(j); err != nil {
		return nil, err
	}

	clientID, ownerID := j.ClientID, otherID
	if userID != j.ClientID {
		// Пишет исполнитель — второй стороной всегда заказчик.
		clientID, ownerID = j.ClientID, userID
	}
	if ownerID == "" || ownerID == clientID {
		return nil, job.ErrChatForbidden
	}
	if userID != clientID && userID != ownerID {
		return nil, job.ErrChatForbidden
	}

	if existing, err := s.st.ChatByJobOwner(ctx, jobID, ownerID); err == nil {
		return s.withKind(ctx, existing, j)
	}

	now := s.now().UTC()
	chat := &job.Chat{
		ID:        uuid.NewString(),
		JobID:     jobID,
		ClientID:  clientID,
		OwnerID:   ownerID,
		Kind:      job.ChatPreDeal,
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := s.st.CreateChat(ctx, chat); err != nil {
		// Гонка: чат создал кто-то параллельно — берём существующий.
		if existing, e := s.st.ChatByJobOwner(ctx, jobID, ownerID); e == nil {
			return s.withKind(ctx, existing, j)
		}
		return nil, err
	}
	return s.withKind(ctx, chat, j)
}

// withKind переводит чат в режим сделки, когда стороны уже договорились:
// с этого момента контакты не маскируются — они и так известны.
func (s *Service) withKind(ctx context.Context, c *job.Chat, j *job.Job) (*job.Chat, error) {
	if c.Kind == job.ChatDeal {
		return c, nil
	}
	d, err := s.st.DealByJob(ctx, j.ID)
	if err != nil || d.OwnerID != c.OwnerID {
		return c, nil
	}
	c.Kind = job.ChatDeal
	c.UpdatedAt = s.now().UTC()
	if err := s.st.UpdateChat(ctx, c); err != nil {
		return nil, err
	}
	return c, nil
}

// SendMessage отправляет сообщение. До сделки телефоны и ники маскируются
// (ТЗ §2.10): сделки, ушедшие мимо площадки, лишают обе стороны защиты при
// споре. Отправитель получает понятное предупреждение, а не молчаливую правку.
func (s *Service) SendMessage(ctx context.Context, userID, chatID, text string) (*job.Message, bool, error) {
	c, err := s.chatOfMine(ctx, userID, chatID)
	if err != nil {
		return nil, false, err
	}
	if err := job.ValidateMessage(text); err != nil {
		return nil, false, err
	}

	body := strings.TrimSpace(text)
	masked := false
	if c.Kind == job.ChatPreDeal {
		body, masked = job.MaskContacts(body)
	}

	now := s.now().UTC()
	msg := &job.Message{
		ID:        uuid.NewString(),
		ChatID:    chatID,
		SenderID:  &userID,
		Kind:      job.MessageText,
		Text:      body,
		ReadBy:    []string{userID},
		CreatedAt: now,
	}
	if err := s.st.CreateMessage(ctx, msg); err != nil {
		return nil, false, err
	}

	c.LastMessageAt = &now
	c.UpdatedAt = now
	if err := s.st.UpdateChat(ctx, c); err != nil {
		return nil, false, err
	}

	target := c.OwnerID
	if userID == c.OwnerID {
		target = c.ClientID
	}
	s.notify.Send(ctx, target, "Новое сообщение", preview(body),
		map[string]string{"route": "/chats/" + c.ID, "chatId": c.ID})

	return msg, masked, nil
}

// SystemMessage — сообщение от площадки о смене статуса сделки (ТЗ §2.12).
func (s *Service) SystemMessage(ctx context.Context, chatID, text string) error {
	now := s.now().UTC()
	msg := &job.Message{
		ID:        uuid.NewString(),
		ChatID:    chatID,
		Kind:      job.MessageSystem,
		Text:      text,
		ReadBy:    []string{},
		CreatedAt: now,
	}
	return s.st.CreateMessage(ctx, msg)
}

// Messages — история переписки. Заодно отмечает чужие сообщения прочитанными:
// открытый чат и есть прочтение.
func (s *Service) Messages(ctx context.Context, userID, chatID string, limit, offset int) ([]job.Message, error) {
	if _, err := s.chatOfMine(ctx, userID, chatID); err != nil {
		return nil, err
	}
	msgs, err := s.st.Messages(ctx, chatID, clampLimit(limit), max0(offset))
	if err != nil {
		return nil, err
	}
	if err := s.st.MarkRead(ctx, chatID, userID); err != nil {
		return nil, err
	}
	return msgs, nil
}

// MyChats — список чатов пользователя.
func (s *Service) MyChats(ctx context.Context, userID string, limit, offset int) ([]job.Chat, error) {
	return s.st.ChatsByUser(ctx, userID, clampLimit(limit), max0(offset))
}

// Chat отдаёт чат участнику.
func (s *Service) Chat(ctx context.Context, userID, chatID string) (*job.Chat, error) {
	return s.chatOfMine(ctx, userID, chatID)
}

func (s *Service) chatOfMine(ctx context.Context, userID, chatID string) (*job.Chat, error) {
	c, err := s.st.ChatByID(ctx, chatID)
	if err != nil {
		return nil, err
	}
	if c.ClientID != userID && c.OwnerID != userID {
		return nil, job.ErrChatForbidden
	}
	return c, nil
}

// preview — короткий текст для уведомления.
func preview(text string) string {
	const limit = 80
	r := []rune(text)
	if len(r) <= limit {
		return text
	}
	return string(r[:limit]) + "…"
}
