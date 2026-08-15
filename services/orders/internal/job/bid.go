package job

import (
	"errors"
	"fmt"
	"sort"
	"time"
)

// BidStatus — состояние ставки (ТЗ §2.9).
type BidStatus string

const (
	BidActive    BidStatus = "active"
	BidWithdrawn BidStatus = "withdrawn"
	BidOutbid    BidStatus = "outbid" // перебита другой ставкой
	BidWon       BidStatus = "won"
	BidLost      BidStatus = "lost"
	BidExpired   BidStatus = "expired"
)

// Bid — ставка в обратном аукционе.
type Bid struct {
	ID       string    `json:"id"`
	JobID    string    `json:"jobId"`
	OwnerID  string    `json:"ownerId"`
	UnitID   *string   `json:"unitId,omitempty"`
	Price    int64     `json:"price"`
	Currency string    `json:"currency"`
	Comment  string    `json:"comment"`
	Status   BidStatus `json:"status"`

	// Score считается на финише; до него null.
	Score     *float64  `json:"score,omitempty"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`

	// Rank — место в ленте по цене (1 — лучшая). Заполняется при выдаче.
	Rank int `json:"rank,omitempty"`
}

var (
	ErrBidNotFound   = errors.New("bid: ставка не найдена")
	ErrNotAuction    = errors.New("bid: у задания не аукцион — здесь делают отклики")
	ErrAuctionClosed = errors.New("bid: торг завершён")
	ErrBidTooLate    = errors.New("bid: отозвать ставку можно не позднее чем за 2 часа до финиша")
	ErrBidNotActive  = errors.New("bid: ставка уже неактивна")
)

const (
	// Ставка ниже трети стартовой цены — почти всегда недопонимание задачи.
	// Предохранитель от демпинга (ТЗ §2.9).
	minBidShare = 0.3
	// Антиснайпинг: ставка в последние 5 минут продлевает торг на 10 минут,
	// чтобы аукцион нельзя было выиграть последней секундой (ТЗ §2.9).
	SnipeWindow = 5 * time.Minute
	ExtendBy    = 10 * time.Minute
	// Отозвать ставку можно не позднее чем за 2 часа до финиша.
	WithdrawLimit = 2 * time.Hour
)

// ValidateBid проверяет ставку до записи. best — текущая лучшая цена (0, если
// ставок ещё нет), start — стартовая цена задания.
func ValidateBid(price, best, start int64) error {
	fields := map[string]string{}

	switch {
	case price <= 0:
		fields["price"] = "укажите цену"
	case best > 0 && price >= best:
		// Обратный аукцион: каждая следующая ставка ниже предыдущей, иначе
		// торга не происходит.
		fields["price"] = fmt.Sprintf("ставка должна быть ниже текущей лучшей (%d)", best)
	case start > 0 && float64(price) < float64(start)*minBidShare:
		fields["price"] = "слишком низкая цена — уточните задачу с заказчиком"
	}

	if len(fields) > 0 {
		return &ValidationError{Fields: fields}
	}
	return nil
}

// CanBid — можно ли сейчас ставить: у задания аукцион и он ещё идёт.
func CanBid(j *Job, now time.Time) error {
	if j.Mode != ModeAuction {
		return ErrNotAuction
	}
	if j.Status != StatusBidding {
		return ErrAuctionClosed
	}
	if j.Auction != nil && j.Auction.EndsAt != nil && !now.Before(*j.Auction.EndsAt) {
		return ErrAuctionClosed
	}
	return nil
}

// ShouldExtend — нужно ли продлить торг: ставка пришла в последние минуты.
func ShouldExtend(j *Job, now time.Time) bool {
	if j.Auction == nil || !j.Auction.AutoExtend || j.Auction.EndsAt == nil {
		return false
	}
	left := j.Auction.EndsAt.Sub(now)
	return left > 0 && left <= SnipeWindow
}

// CanWithdrawBid — ставку нельзя снять на финишной прямой: иначе исполнитель
// «придержал» бы цену и снял её в последний момент.
func CanWithdrawBid(j *Job, now time.Time) error {
	if j.Auction == nil || j.Auction.EndsAt == nil {
		return nil
	}
	if j.Auction.EndsAt.Sub(now) < WithdrawLimit {
		return ErrBidTooLate
	}
	return nil
}

// BidScore — исполнитель со своими данными для скоринга.
type BidScore struct {
	Bid       Bid
	Rating    float64 // 0..5
	DistanceM float64 // до места работы; отрицательное — неизвестно
	UnitMatch bool    // техника подходит по категории
}

// Score — вес ставки при выборе победителя (ТЗ §2.9):
// 0.6·цена + 0.25·рейтинг + 0.15·(близость и соответствие техники).
//
// Цена нормализуется внутри набора ставок: важно не «дёшево вообще», а
// «дешевле остальных в этом торге». Одна ставка получает по цене максимум —
// сравнивать её не с чем.
func Score(items []BidScore, reserve *int64) []BidScore {
	if len(items) == 0 {
		return items
	}

	minPrice, maxPrice := items[0].Bid.Price, items[0].Bid.Price
	maxDist := 0.0
	for _, it := range items {
		if it.Bid.Price < minPrice {
			minPrice = it.Bid.Price
		}
		if it.Bid.Price > maxPrice {
			maxPrice = it.Bid.Price
		}
		if it.DistanceM > maxDist {
			maxDist = it.DistanceM
		}
	}

	out := make([]BidScore, 0, len(items))
	for _, it := range items {
		// Ставки ниже резерва в расчёте не участвуют (ТЗ §2.9).
		if reserve != nil && it.Bid.Price < *reserve {
			continue
		}

		priceScore := 1.0
		if maxPrice > minPrice {
			priceScore = float64(maxPrice-it.Bid.Price) / float64(maxPrice-minPrice)
		}
		ratingScore := it.Rating / 5.0
		if ratingScore < 0 {
			ratingScore = 0
		}
		fitScore := 0.0
		if it.UnitMatch {
			fitScore += 0.5
		}
		if it.DistanceM >= 0 && maxDist > 0 {
			fitScore += 0.5 * (1 - it.DistanceM/maxDist)
		} else if it.DistanceM >= 0 {
			fitScore += 0.5
		}

		score := 0.6*priceScore + 0.25*ratingScore + 0.15*fitScore
		it.Bid.Score = &score
		out = append(out, it)
	}

	// Лучший — первым: заказчик видит рекомендацию сверху.
	sort.SliceStable(out, func(i, k int) bool {
		return *out[i].Bid.Score > *out[k].Bid.Score
	})
	return out
}
