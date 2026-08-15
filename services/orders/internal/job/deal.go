package job

import (
	"errors"
	"time"
)

// DealStatus — шаги сделки (ТЗ §2.11).
type DealStatus string

const (
	DealConfirmed  DealStatus = "confirmed"   // договорились, работа не начата
	DealOnTheWay   DealStatus = "on_the_way"  // исполнитель выехал
	DealInProgress DealStatus = "in_progress" // работа идёт
	DealWorkDone   DealStatus = "work_done"   // исполнитель закончил, ждём приёмки
	DealCompleted  DealStatus = "completed"   // заказчик принял
	DealDisputed   DealStatus = "disputed"    // спор
	DealCancelled  DealStatus = "cancelled"
)

// TimelineEvent — отметка в общей истории сделки. Обе стороны видят одно и то
// же: кто и когда что сделал, поэтому «я выехал час назад» не превращается в
// спор на словах.
type TimelineEvent struct {
	Status DealStatus `json:"status"`
	At     time.Time  `json:"at"`
	ByID   string     `json:"byId"`
	Note   string     `json:"note,omitempty"`
}

// Deal — сделка по заданию.
type Deal struct {
	ID       string  `json:"id"`
	JobID    string  `json:"jobId"`
	OfferID  *string `json:"offerId,omitempty"`
	ClientID string  `json:"clientId"`
	OwnerID  string  `json:"ownerId"`

	Price    int64  `json:"price"`
	Currency string `json:"currency"`

	Status   DealStatus      `json:"status"`
	Timeline []TimelineEvent `json:"timeline"`

	// AcceptanceDeadline — до какого момента заказчик может принять работу;
	// после — автоприёмка (ТЗ §2.11: 48 часов).
	AcceptanceDeadline *time.Time `json:"acceptanceDeadline,omitempty"`
	CancelReason       string     `json:"cancelReason,omitempty"`
	CancelledBy        *string    `json:"cancelledBy,omitempty"`

	CreatedAt time.Time  `json:"createdAt"`
	UpdatedAt time.Time  `json:"updatedAt"`
	ClosedAt  *time.Time `json:"closedAt,omitempty"`

	// JobTitle подмешивается там, где сделку показывают списком: в отчёте
	// «Планировка участка» понятнее, чем идентификатор задания.
	JobTitle string `json:"jobTitle,omitempty"`
}

// AcceptanceWindow — сколько у заказчика есть на приёмку (ТЗ §2.11).
const AcceptanceWindow = 48 * time.Hour

var (
	ErrDealNotFound    = errors.New("deal: сделка не найдена")
	ErrDealNotParty    = errors.New("deal: вы не участник этой сделки")
	ErrDealStep        = errors.New("deal: этот шаг сейчас недоступен")
	ErrDealClosed      = errors.New("deal: сделка уже закрыта")
	ErrDealWrongPerson = errors.New("deal: этот шаг делает другая сторона")
)

// dealFlow — кто и куда может двинуть сделку. Порядок шагов не случайный:
// он повторяет то, как работа идёт в жизни, и не даёт «завершить» то, что не
// начиналось.
type dealStep struct {
	to       DealStatus
	byOwner  bool // шаг делает исполнитель
	byClient bool // шаг делает заказчик
}

var dealFlow = map[DealStatus][]dealStep{
	DealConfirmed: {
		{to: DealOnTheWay, byOwner: true},
		{to: DealInProgress, byOwner: true}, // если выехал молча
		{to: DealCancelled, byOwner: true, byClient: true},
	},
	DealOnTheWay: {
		{to: DealInProgress, byOwner: true},
		{to: DealCancelled, byOwner: true, byClient: true},
	},
	DealInProgress: {
		{to: DealWorkDone, byOwner: true},
		{to: DealDisputed, byOwner: true, byClient: true},
		{to: DealCancelled, byOwner: true, byClient: true},
	},
	DealWorkDone: {
		{to: DealCompleted, byClient: true}, // приёмка заказчиком
		{to: DealDisputed, byClient: true},
	},
	DealDisputed: {
		{to: DealCompleted, byClient: true},
		{to: DealCancelled, byClient: true},
	},
}

// CanAdvance проверяет, можно ли перевести сделку в статус to и вправе ли это
// сделать именно этот человек.
func CanAdvance(d *Deal, to DealStatus, userID string) error {
	if d.Status == DealCompleted || d.Status == DealCancelled {
		return ErrDealClosed
	}
	isOwner := userID == d.OwnerID
	isClient := userID == d.ClientID
	if !isOwner && !isClient {
		return ErrDealNotParty
	}

	for _, step := range dealFlow[d.Status] {
		if step.to != to {
			continue
		}
		if (isOwner && step.byOwner) || (isClient && step.byClient) {
			return nil
		}
		return ErrDealWrongPerson
	}
	return ErrDealStep
}

// JobStatusForDeal — какой статус у задания при таком состоянии сделки.
// Задание и сделка не должны расходиться: в ленте и в CRM человек видит
// именно статус задания.
func JobStatusForDeal(s DealStatus) Status {
	switch s {
	case DealConfirmed:
		return StatusConfirmed
	case DealOnTheWay, DealInProgress:
		return StatusInProgress
	case DealWorkDone:
		return StatusWorkDone
	case DealCompleted:
		return StatusCompleted
	case DealDisputed:
		return StatusDisputed
	default:
		return StatusCancelled
	}
}
