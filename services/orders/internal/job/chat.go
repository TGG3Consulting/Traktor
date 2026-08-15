package job

import (
	"errors"
	"regexp"
	"strings"
	"time"
)

// ChatKind — до сделки или после.
type ChatKind string

const (
	ChatPreDeal ChatKind = "pre_deal"
	ChatDeal    ChatKind = "deal"
)

// MessageKind — тип сообщения.
type MessageKind string

const (
	MessageText   MessageKind = "text"
	MessagePhoto  MessageKind = "photo"
	MessageSystem MessageKind = "system"
)

// Chat — переписка заказчика и одного исполнителя по заданию.
type Chat struct {
	ID       string   `json:"id"`
	JobID    string   `json:"jobId"`
	ClientID string   `json:"clientId"`
	OwnerID  string   `json:"ownerId"`
	Kind     ChatKind `json:"kind"`

	LastMessageAt *time.Time `json:"lastMessageAt,omitempty"`
	CreatedAt     time.Time  `json:"createdAt"`
	UpdatedAt     time.Time  `json:"updatedAt"`

	// Поля для списка чатов — заполняются при выдаче.
	LastText string `json:"lastText,omitempty"`
	Unread   int    `json:"unread,omitempty"`
	JobTitle string `json:"jobTitle,omitempty"`
}

// Message — сообщение в чате.
type Message struct {
	ID       string      `json:"id"`
	ChatID   string      `json:"chatId"`
	SenderID *string     `json:"senderId,omitempty"`
	Kind     MessageKind `json:"kind"`
	Text     string      `json:"text"`
	MediaURL *string     `json:"mediaUrl,omitempty"`
	ReadBy   []string    `json:"readBy"`

	CreatedAt time.Time `json:"createdAt"`
}

var (
	ErrChatNotFound  = errors.New("chat: чат не найден")
	ErrChatForbidden = errors.New("chat: это чужая переписка")
	ErrChatClosed    = errors.New("chat: переписка по этому заданию закрыта")
	ErrEmptyMessage  = errors.New("chat: пустое сообщение")
)

const maxMessageLen = 2000

// Маскировка контактов до сделки (ТЗ §2.10, §2.12).
//
// Смысл не в том, чтобы «поймать нарушителя», а в том, чтобы сделки не уходили
// мимо площадки в первый же час: там, где ушли контакты, нет ни истории, ни
// защиты сторон при споре. Поэтому телефоны и ники скрываются мягко, а человек
// видит понятное предупреждение.
var (
	phoneRe = regexp.MustCompile(`(?:\+?\d[\s\-()]?){9,15}`)
	// Ники мессенджеров и адреса: @user, t.me/user, wa.me/номер.
	handleRe = regexp.MustCompile(`(?i)(@[a-z0-9_]{4,}|t\.me/\S+|wa\.me/\S+|viber:\S+|telegram\S*)`)
	emailRe  = regexp.MustCompile(`(?i)[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}`)
)

// MaskContacts прячет телефоны и ники в тексте до сделки.
// Возвращает изменённый текст и признак, что что-то было скрыто.
func MaskContacts(text string) (string, bool) {
	masked := text
	masked = emailRe.ReplaceAllString(masked, "[контакт скрыт]")
	masked = handleRe.ReplaceAllString(masked, "[контакт скрыт]")
	masked = phoneRe.ReplaceAllStringFunc(masked, func(m string) string {
		digits := 0
		for _, r := range m {
			if r >= '0' && r <= '9' {
				digits++
			}
		}
		// Короткие числа — это объёмы, метры и цены, а не телефоны.
		if digits < 9 {
			return m
		}
		return "[контакт скрыт]"
	})
	return masked, masked != text
}

// ValidateMessage проверяет текст сообщения.
func ValidateMessage(text string) error {
	t := strings.TrimSpace(text)
	if t == "" {
		return ErrEmptyMessage
	}
	if len([]rune(t)) > maxMessageLen {
		return &ValidationError{
			Fields: map[string]string{"text": "сообщение длиннее 2000 символов"},
		}
	}
	return nil
}

// CanChat — можно ли переписываться по этому заданию.
// Переписка живёт, пока задание не закрыто окончательно: после завершения
// стороны ещё могут договорить о деталях приёмки.
func CanChat(j *Job) error {
	switch j.Status {
	case StatusCancelled, StatusExpired, StatusExpiredNoBids, StatusDeclinedAll:
		return ErrChatClosed
	default:
		return nil
	}
}
