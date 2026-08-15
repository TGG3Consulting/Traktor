package job

import (
	"errors"
	"strings"
	"time"
)

// Complaint — жалоба на задание или человека (ТЗ §4.1, п.6).
//
// Пока пожаловаться некуда, единственная реакция на обман — уйти с площадки.
// Жалоба даёт модерации повод посмотреть и закрывает этот выход.
type Complaint struct {
	ID         string `json:"id"`
	TargetKind string `json:"targetKind"`
	TargetID   string `json:"targetId"`

	AuthorID string `json:"authorId"`
	Reason   string `json:"reason"`

	Status ComplaintStatus `json:"status"`
	Action ComplaintAction `json:"action,omitempty"`
	Note   string          `json:"note,omitempty"`

	ReviewedBy string     `json:"-"`
	ReviewedAt *time.Time `json:"reviewedAt,omitempty"`
	CreatedAt  time.Time  `json:"createdAt"`

	// Подмешивается в очередь модерации.
	TargetTitle string `json:"targetTitle,omitempty"`
	// Sameters — сколько ещё жалоб на этот же объект: одна жалоба может быть
	// сведением счётов, пять — уже сигнал.
	SameTarget int `json:"sameTarget,omitempty"`
}

type ComplaintStatus string

const (
	ComplaintOpen     ComplaintStatus = "open"
	ComplaintReviewed ComplaintStatus = "reviewed"
)

// ComplaintAction — что сделала модерация.
type ComplaintAction string

const (
	// ActionDismissed — жалоба не подтвердилась.
	ActionDismissed ComplaintAction = "dismissed"
	// ActionRemoved — задание снято с площадки.
	ActionRemoved ComplaintAction = "removed"
	// ActionWarned — человеку вынесено предупреждение.
	ActionWarned ComplaintAction = "warned"
)

const (
	TargetJob  = "job"
	TargetUser = "user"
)

var (
	ErrComplaintNotFound = errors.New("complaint: жалоба не найдена")
	ErrComplaintExists   = errors.New("complaint: вы уже жаловались на это")
	ErrComplaintClosed   = errors.New("complaint: жалоба уже разобрана")
	ErrComplaintReason   = errors.New("complaint: опишите, в чём проблема")
	ErrComplaintTarget   = errors.New("complaint: жаловаться можно на задание или человека")
	ErrComplaintSelf     = errors.New("complaint: на себя жаловаться незачем")
	ErrComplaintAction   = errors.New("complaint: выберите, что сделать с жалобой")
)

const (
	minComplaint = 10
	maxComplaint = 500
)

// ValidateComplaint проверяет текст жалобы: десять символов — минимум, на
// котором модератор поймёт, что смотреть.
func ValidateComplaint(reason string) (string, error) {
	reason = strings.TrimSpace(reason)
	if len([]rune(reason)) < minComplaint {
		return "", ErrComplaintReason
	}
	if len([]rune(reason)) > maxComplaint {
		reason = string([]rune(reason)[:maxComplaint])
	}
	return reason, nil
}

// ValidTarget — на что можно жаловаться.
func ValidTarget(kind string) bool { return kind == TargetJob || kind == TargetUser }

// ValidAction — что модерация может сделать.
func ValidAction(a ComplaintAction) bool {
	return a == ActionDismissed || a == ActionRemoved || a == ActionWarned
}

// ActionRU — как решение читается человеку.
func ActionRU(a ComplaintAction) string {
	switch a {
	case ActionDismissed:
		return "жалоба не подтвердилась"
	case ActionRemoved:
		return "контент снят"
	case ActionWarned:
		return "вынесено предупреждение"
	default:
		return ""
	}
}
