package store

import (
	"context"
	"sort"

	"traktor/orders/internal/job"
)

// Чаты в памяти: та же семантика, что в Postgres — один чат на пару
// «задание + исполнитель», непрочитанным считается чужое сообщение.

func (m *Memory) CreateChat(_ context.Context, c *job.Chat) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, ex := range m.chats {
		if ex.JobID == c.JobID && ex.OwnerID == c.OwnerID {
			return job.ErrChatNotFound
		}
	}
	if m.chats == nil {
		m.chats = map[string]job.Chat{}
	}
	m.chats[c.ID] = *c
	return nil
}

func (m *Memory) ChatByID(_ context.Context, id string) (*job.Chat, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	c, ok := m.chats[id]
	if !ok {
		return nil, job.ErrChatNotFound
	}
	return &c, nil
}

func (m *Memory) ChatByJobOwner(_ context.Context, jobID, ownerID string) (*job.Chat, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	for _, c := range m.chats {
		if c.JobID == jobID && c.OwnerID == ownerID {
			copy := c
			return &copy, nil
		}
	}
	return nil, job.ErrChatNotFound
}

func (m *Memory) ChatsByUser(_ context.Context, userID string, limit, offset int) ([]job.Chat, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.Chat{}
	for _, c := range m.chats {
		if c.ClientID != userID && c.OwnerID != userID {
			continue
		}
		chat := c
		if j, ok := m.jobs[c.JobID]; ok {
			chat.JobTitle = j.Title
		}
		var last *job.Message
		unread := 0
		for i := range m.messages {
			msg := m.messages[i]
			if msg.ChatID != c.ID {
				continue
			}
			if last == nil || msg.CreatedAt.After(last.CreatedAt) {
				copy := msg
				last = &copy
			}
			if !readBy(msg, userID) && (msg.SenderID == nil || *msg.SenderID != userID) {
				unread++
			}
		}
		if last != nil {
			chat.LastText = last.Text
		}
		chat.Unread = unread
		out = append(out, chat)
	}

	sort.Slice(out, func(i, k int) bool {
		if out[i].LastMessageAt == nil || out[k].LastMessageAt == nil {
			return out[k].LastMessageAt == nil && out[i].LastMessageAt != nil
		}
		return out[i].LastMessageAt.After(*out[k].LastMessageAt)
	})
	if offset >= len(out) {
		return []job.Chat{}, nil
	}
	out = out[offset:]
	if limit > 0 && limit < len(out) {
		out = out[:limit]
	}
	return out, nil
}

func (m *Memory) UpdateChat(_ context.Context, c *job.Chat) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.chats[c.ID]; !ok {
		return job.ErrChatNotFound
	}
	m.chats[c.ID] = *c
	return nil
}

func (m *Memory) CreateMessage(_ context.Context, msg *job.Message) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.messages == nil {
		m.messages = map[string]job.Message{}
	}
	m.messages[msg.ID] = *msg
	return nil
}

func (m *Memory) Messages(_ context.Context, chatID string, limit, offset int) ([]job.Message, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := []job.Message{}
	for _, msg := range m.messages {
		if msg.ChatID == chatID {
			out = append(out, msg)
		}
	}
	sort.Slice(out, func(i, k int) bool { return out[i].CreatedAt.After(out[k].CreatedAt) })
	if offset >= len(out) {
		return []job.Message{}, nil
	}
	out = out[offset:]
	if limit > 0 && limit < len(out) {
		out = out[:limit]
	}
	return out, nil
}

func (m *Memory) MarkRead(_ context.Context, chatID, userID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for id, msg := range m.messages {
		if msg.ChatID != chatID || readBy(msg, userID) {
			continue
		}
		if msg.SenderID != nil && *msg.SenderID == userID {
			continue
		}
		msg.ReadBy = append(msg.ReadBy, userID)
		m.messages[id] = msg
	}
	return nil
}

func readBy(m job.Message, userID string) bool {
	for _, id := range m.ReadBy {
		if id == userID {
			return true
		}
	}
	return false
}
