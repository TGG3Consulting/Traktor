package job

import (
	"errors"
	"strings"
	"time"
)

// OfferKind — что именно предложил исполнитель.
type OfferKind string

const (
	// OfferAccept — согласен на цену заказчика.
	OfferAccept OfferKind = "accept"
	// OfferCounter — предлагает свою цену.
	OfferCounter OfferKind = "counter"
)

// OfferStatus — состояние отклика.
type OfferStatus string

const (
	OfferActive         OfferStatus = "active"
	OfferWithdrawn      OfferStatus = "withdrawn"
	OfferDeclined       OfferStatus = "declined"
	OfferAccepted       OfferStatus = "accepted"
	OfferCounterOffered OfferStatus = "counter_offered" // заказчик ответил своей ценой
)

// Offer — отклик исполнителя на задание с фиксированной ценой (ТЗ §2.10).
type Offer struct {
	ID       string    `json:"id"`
	JobID    string    `json:"jobId"`
	OwnerID  string    `json:"ownerId"`
	Kind     OfferKind `json:"kind"`
	Price    int64     `json:"price"`
	Currency string    `json:"currency"`
	Comment  string    `json:"comment"`
	ETA      string    `json:"eta"`
	UnitID   *string   `json:"unitId,omitempty"`

	Status        OfferStatus `json:"status"`
	DeclineReason string      `json:"declineReason,omitempty"`

	// Встречная цена заказчика — второй и последний раунд торга.
	ClientCounterPrice *int64     `json:"clientCounterPrice,omitempty"`
	ClientCounterAt    *time.Time `json:"clientCounterAt,omitempty"`

	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

// Ошибки откликов.
var (
	ErrOfferNotFound  = errors.New("offer: отклик не найден")
	ErrJobNotOpen     = errors.New("offer: задание больше не принимает отклики")
	ErrOwnJob         = errors.New("offer: нельзя откликнуться на своё задание")
	ErrOfferExists    = errors.New("offer: вы уже откликнулись на это задание")
	ErrOfferNotActive = errors.New("offer: отклик уже неактивен")
	ErrCounterUsed    = errors.New("offer: встречное предложение уже отправлено")
	// Техника в отклике или ставке (ТЗ §2.5, §2.9).
	ErrUnitForeign  = errors.New("offer: это чужая техника")
	ErrUnitInactive = errors.New("offer: техника не опубликована — закончите её карточку")
	ErrAuctionMode  = errors.New("offer: у задания идёт аукцион — здесь делаются ставки, а не отклики")
)

const (
	maxComment = 200 // ТЗ §2.8: комментарий к предложению ≤200 символов
	// Демпинг ниже трети цены обычно означает недопонимание задачи, а не
	// выгодное предложение: такие отклики отсекаем сразу.
	minPriceShare = 0.3
)

// ValidateOffer проверяет отклик до записи. jobPrice — цена задания.
func ValidateOffer(o *Offer, jobPrice int64) error {
	fields := map[string]string{}

	if o.Price <= 0 {
		fields["price"] = "укажите цену"
	}
	if o.Kind == OfferAccept && jobPrice > 0 && o.Price != jobPrice {
		fields["price"] = "при согласии цена должна совпадать с ценой задания"
	}
	if jobPrice > 0 && o.Price > 0 && float64(o.Price) < float64(jobPrice)*minPriceShare {
		fields["price"] = "слишком низкая цена — уточните задачу с заказчиком"
	}
	if len([]rune(strings.TrimSpace(o.Comment))) > maxComment {
		fields["comment"] = "комментарий не длиннее 200 символов"
	}
	if len(fields) > 0 {
		return &ValidationError{Fields: fields}
	}
	return nil
}

// CanAcceptOffers — задание принимает отклики (только фикс-цена).
func CanAcceptOffers(j *Job) error {
	if j.Mode == ModeAuction {
		return ErrAuctionMode
	}
	if !IsOpen(j.Status) {
		return ErrJobNotOpen
	}
	return nil
}
