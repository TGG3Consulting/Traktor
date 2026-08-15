package job

import (
	"errors"
	"strings"
	"time"
)

// Dispute — спор по сделке (ТЗ §4.1, п.4).
//
// Спор не отменяет сделку и не замораживает деньги: он даёт сторонам арбитра
// вместо ссоры в переписке. Пока идёт разбор, оценки не выставляются — иначе
// отзыв становится оружием в конфликте.
type Dispute struct {
	ID     string `json:"id"`
	DealID string `json:"dealId"`
	JobID  string `json:"jobId"`

	OpenedBy string `json:"openedBy"`
	ClientID string `json:"clientId"`
	OwnerID  string `json:"ownerId"`

	Reason string   `json:"reason"`
	Photos []string `json:"photos,omitempty"`

	Status  DisputeStatus  `json:"status"`
	Outcome DisputeOutcome `json:"outcome,omitempty"`
	// Resolution — обоснование решения, его видят обе стороны.
	Resolution string     `json:"resolution,omitempty"`
	ResolvedBy string     `json:"-"`
	ResolvedAt *time.Time `json:"resolvedAt,omitempty"`

	CreatedAt time.Time `json:"createdAt"`

	// Подмешивается для очереди модерации.
	JobTitle string `json:"jobTitle,omitempty"`
}

type DisputeStatus string

const (
	DisputeOpen     DisputeStatus = "open"
	DisputeResolved DisputeStatus = "resolved"
)

// DisputeOutcome — в чью пользу решён спор.
type DisputeOutcome string

const (
	// OutcomeClient — прав заказчик.
	OutcomeClient DisputeOutcome = "client"
	// OutcomeOwner — прав исполнитель.
	OutcomeOwner DisputeOutcome = "owner"
	// OutcomeCompromise — обе стороны частично правы: самый частый исход
	// в спорах о качестве работы.
	OutcomeCompromise DisputeOutcome = "compromise"
)

var (
	ErrDisputeNotFound   = errors.New("dispute: спор не найден")
	ErrDisputeForbidden  = errors.New("dispute: это чужой спор")
	ErrDisputeExists     = errors.New("dispute: спор по этой сделке уже открыт")
	ErrDisputeClosed     = errors.New("dispute: спор уже разобран")
	ErrDisputeReason     = errors.New("dispute: опишите, что пошло не так")
	ErrDisputeOutcome    = errors.New("dispute: выберите, в чью пользу решение")
	ErrDisputeResolution = errors.New("dispute: решение нужно обосновать")
	ErrDisputeStage      = errors.New("dispute: спор открывается по начатой работе")
)

const (
	minReason     = 20
	maxReason     = 1000
	minResolution = 20
	maxResolution = 1000
)

// CanOpenDispute — спор открывает участник сделки и только тогда, когда работа
// уже началась: до выезда исполнителя спорить не о чем, сделку просто отменяют.
func CanOpenDispute(d *Deal, userID string) error {
	if d.ClientID != userID && d.OwnerID != userID {
		return ErrDealNotParty
	}
	switch d.Status {
	case DealInProgress, DealWorkDone, DealCompleted, DealDisputed:
		return nil
	default:
		return ErrDisputeStage
	}
}

// ValidateReason проверяет описание проблемы. Двадцать символов — это минимум,
// на котором модератор хоть что-то поймёт: «плохо» разобрать нельзя.
func ValidateReason(reason string) (string, error) {
	reason = strings.TrimSpace(reason)
	if len([]rune(reason)) < minReason {
		return "", ErrDisputeReason
	}
	if len([]rune(reason)) > maxReason {
		reason = string([]rune(reason)[:maxReason])
	}
	return reason, nil
}

// ValidateResolution проверяет обоснование решения модератора.
func ValidateResolution(text string) (string, error) {
	text = strings.TrimSpace(text)
	if len([]rune(text)) < minResolution {
		return "", ErrDisputeResolution
	}
	if len([]rune(text)) > maxResolution {
		text = string([]rune(text)[:maxResolution])
	}
	return text, nil
}

// ValidOutcome — исход из закрытого списка.
func ValidOutcome(o DisputeOutcome) bool {
	return o == OutcomeClient || o == OutcomeOwner || o == OutcomeCompromise
}

// OutcomeRU — как исход читается человеку.
func OutcomeRU(o DisputeOutcome) string {
	switch o {
	case OutcomeClient:
		return "в пользу заказчика"
	case OutcomeOwner:
		return "в пользу исполнителя"
	case OutcomeCompromise:
		return "компромисс"
	default:
		return ""
	}
}
