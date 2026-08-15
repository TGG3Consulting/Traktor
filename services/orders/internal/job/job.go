// Package job — доменная модель задания: поля визарда, статусы и правила
// перехода между ними (ТЗ §1.12, §2.6, §4.4).
//
// Модель ничего не знает про HTTP и базу: сюда вынесены решения, которые
// должны совпадать в любом слое — что считается заполненным, кому можно менять
// задание и какой статус наступает после публикации.
package job

import (
	"errors"
	"fmt"
	"strings"
	"time"
)

// OrderType — тип заказа (ТЗ §5.1).
type OrderType string

const (
	TypeJob       OrderType = "job"       // задание с описанием
	TypeRental    OrderType = "rental"    // аренда техники
	TypeTransport OrderType = "transport" // перевозка А→Б
	TypeWorkers   OrderType = "workers"   // разнорабочие
)

// Mode — ценообразование задания (ТЗ §2.6 шаг 4).
type Mode string

const (
	ModeFixed   Mode = "fixed"
	ModeAuction Mode = "auction"
)

// Status — статус задания (ТЗ §4.4). Значения совпадают с CHECK в схеме.
type Status string

const (
	StatusDraft            Status = "draft"
	StatusPublished        Status = "published"
	StatusCollectingOffers Status = "collecting_offers"
	StatusBidding          Status = "bidding"
	StatusDealPending      Status = "deal_pending"
	StatusDeciding         Status = "deciding"
	StatusConfirmed        Status = "confirmed"
	StatusInProgress       Status = "in_progress"
	StatusWorkDone         Status = "work_done"
	StatusCompleted        Status = "completed"
	StatusDisputed         Status = "disputed"
	StatusCancelled        Status = "cancelled"
	StatusDeclinedAll      Status = "declined_all"
	StatusExpired          Status = "expired"
	StatusExpiredNoBids    Status = "expired_no_bids"
)

// DateMode — когда нужна работа (ТЗ §2.6 шаг 3).
type DateMode string

const (
	DateASAP  DateMode = "asap"
	DateRange DateMode = "range"
	DateExact DateMode = "exact"
)

// Access — есть ли подъезд для техники.
type Access string

const (
	AccessYes     Access = "yes"
	AccessNo      Access = "no"
	AccessUnknown Access = "unknown"
)

// Geo — точка на карте. Долгота первой не ставим: в API порядок lat/lng,
// как его читают люди; в SQL порядок меняется на lng/lat явно.
type Geo struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

// Auction — настройки обратного аукциона. Reserve отдаётся только владельцу.
type Auction struct {
	DurationH       int        `json:"durationH"`
	EndsAt          *time.Time `json:"endsAt,omitempty"`
	ReserveAmount   *int64     `json:"reserveAmount,omitempty"`
	AutoExtend      bool       `json:"autoExtend"`
	DecisionWindowH int        `json:"decisionWindowH"`
}

// Job — задание целиком, как оно живёт в базе и уходит владельцу.
type Job struct {
	ID          string         `json:"id"`
	ClientID    string         `json:"clientId"`
	OrderType   OrderType      `json:"orderType"`
	CategoryID  *string        `json:"categoryId,omitempty"`
	OpenToAny   bool           `json:"openToAny"`
	Title       string         `json:"title"`
	Description string         `json:"description"`
	Params      map[string]any `json:"params"`
	Photos      []string       `json:"photos"`

	Geo       *Geo       `json:"geo,omitempty"`
	Address   string     `json:"address"`
	Access    Access     `json:"access"`
	DateMode  DateMode   `json:"dateMode"`
	DateStart *time.Time `json:"dateStart,omitempty"`
	DateEnd   *time.Time `json:"dateEnd,omitempty"`

	BudgetAmount *int64   `json:"budgetAmount,omitempty"`
	Currency     string   `json:"currency"`
	Mode         Mode     `json:"mode"`
	Auction      *Auction `json:"auction,omitempty"`
	WorkersCount int      `json:"workersCount"`

	Status      Status  `json:"status"`
	DraftStep   int     `json:"draftStep"`
	ViewsCount  int     `json:"viewsCount"`
	OffersCount int     `json:"offersCount"`
	WinnerBidID *string `json:"winnerBidId,omitempty"`
	// DecisionDeadline — до какого момента заказчик выбирает победителя
	// аукциона; молчание закрывает задание (ТЗ §2.9).
	DecisionDeadline *time.Time `json:"decisionDeadline,omitempty"`
	PublishedAt      *time.Time `json:"publishedAt,omitempty"`
	CreatedAt        time.Time  `json:"createdAt"`
	UpdatedAt        time.Time  `json:"updatedAt"`

	// DistanceM заполняется только в ленте: расстояние от точки поиска.
	DistanceM *float64 `json:"distanceM,omitempty"`
}

// Ошибки домена. Сервис переводит их в коды problem+json.
var (
	ErrNotFound      = errors.New("job: задание не найдено")
	ErrForbidden     = errors.New("job: задание принадлежит другому пользователю")
	ErrNotDraft      = errors.New("job: менять можно только черновик")
	ErrValidation    = errors.New("job: не хватает данных")
	ErrBadTransition = errors.New("job: недопустимый переход статуса")
)

// ValidationError перечисляет незаполненные поля — клиент подсвечивает их и
// пишет человеку, чего именно не хватает (ТЗ §2.6: «кнопка Далее неактивна с
// подсказкой чего не хватает»).
type ValidationError struct{ Fields map[string]string }

func (e *ValidationError) Error() string {
	parts := make([]string, 0, len(e.Fields))
	for k, v := range e.Fields {
		parts = append(parts, k+": "+v)
	}
	return "job: не хватает данных — " + strings.Join(parts, "; ")
}
func (e *ValidationError) Is(target error) bool { return target == ErrValidation }

const (
	minDescription = 20 // ТЗ §2.6 шаг 2
	maxTitle       = 80 // ТЗ §2.6 шаг 2
	maxPhotos      = 6  // ТЗ §2.6 шаг 2: фото места 0–6
	maxAuctionDays = 7  // ТЗ §2.6 шаг 4: своя длительность, максимум 7 дней
)

// ValidateForPublish проверяет задание перед публикацией. Возвращает
// ValidationError с картой «поле → что не так», иначе nil.
//
// Проверка живёт на сервере, потому что сервер — источник истины (правило 9):
// клиент может отстать от версии правил или быть подменён.
func (j *Job) ValidateForPublish() error {
	fields := map[string]string{}

	if j.CategoryID == nil && !j.OpenToAny {
		fields["categoryId"] = "выберите категорию работ или включите «пусть предложат сами»"
	}
	title := strings.TrimSpace(j.Title)
	switch {
	case title == "":
		fields["title"] = "название обязательно"
	case len([]rune(title)) > maxTitle:
		fields["title"] = fmt.Sprintf("не длиннее %d символов", maxTitle)
	}
	if len([]rune(strings.TrimSpace(j.Description))) < minDescription {
		fields["description"] = fmt.Sprintf("опишите задачу подробнее — минимум %d символов", minDescription)
	}
	if len(j.Photos) > maxPhotos {
		fields["photos"] = fmt.Sprintf("не больше %d фотографий", maxPhotos)
	}
	if j.Geo == nil {
		fields["geo"] = "укажите место на карте"
	} else if j.Geo.Lat < -90 || j.Geo.Lat > 90 || j.Geo.Lng < -180 || j.Geo.Lng > 180 {
		fields["geo"] = "координаты вне допустимого диапазона"
	}
	if j.DateMode == DateRange && (j.DateStart == nil || j.DateEnd == nil) {
		fields["dates"] = "укажите начало и конец диапазона"
	}
	if j.DateMode == DateRange && j.DateStart != nil && j.DateEnd != nil && j.DateEnd.Before(*j.DateStart) {
		fields["dates"] = "конец диапазона раньше начала"
	}
	if j.DateMode == DateExact && j.DateStart == nil {
		fields["dates"] = "укажите дату и время начала"
	}
	if j.BudgetAmount == nil || *j.BudgetAmount <= 0 {
		fields["budgetAmount"] = "укажите цену"
	}
	if j.Currency == "" {
		fields["currency"] = "не указана валюта"
	}

	if j.Mode == ModeAuction {
		switch {
		case j.Auction == nil:
			fields["auction"] = "не заданы параметры аукциона"
		default:
			if j.Auction.DurationH < 1 || j.Auction.DurationH > maxAuctionDays*24 {
				fields["auction.durationH"] = fmt.Sprintf("длительность от 1 часа до %d дней", maxAuctionDays)
			}
			if j.Auction.DecisionWindowH < 1 || j.Auction.DecisionWindowH > 72 {
				fields["auction.decisionWindowH"] = "окно решения от 1 до 72 часов"
			}
			// Reserve выше стартовой цены обессмысливает торг: ни одна ставка
			// не пройдёт, и заказчик получит «нет подходящих ставок».
			if j.Auction.ReserveAmount != nil && j.BudgetAmount != nil && *j.Auction.ReserveAmount > *j.BudgetAmount {
				fields["auction.reserveAmount"] = "минимальная цена выше стартовой — торг невозможен"
			}
		}
	}

	if len(fields) > 0 {
		return &ValidationError{Fields: fields}
	}
	return nil
}

// StatusAfterPublish — статус сразу после публикации: фикс-цена ждёт откликов,
// аукцион сразу переходит в торги (ТЗ §4.4).
func StatusAfterPublish(mode Mode) Status {
	if mode == ModeAuction {
		return StatusBidding
	}
	return StatusCollectingOffers
}

// allowed — матрица переходов ТЗ §4.4. Ключ — откуда, значение — куда можно.
var allowed = map[Status][]Status{
	StatusDraft:            {StatusPublished, StatusCollectingOffers, StatusBidding, StatusCancelled},
	StatusPublished:        {StatusCollectingOffers, StatusBidding, StatusCancelled},
	StatusCollectingOffers: {StatusDealPending, StatusCancelled, StatusExpired},
	StatusBidding:          {StatusDeciding, StatusExpiredNoBids, StatusCancelled},
	StatusDealPending:      {StatusConfirmed, StatusCancelled},
	StatusDeciding:         {StatusConfirmed, StatusDeclinedAll, StatusExpired, StatusCancelled},
	StatusConfirmed:        {StatusInProgress, StatusCancelled},
	StatusInProgress:       {StatusWorkDone, StatusDisputed, StatusCancelled},
	StatusWorkDone:         {StatusCompleted, StatusDisputed},
	StatusDisputed:         {StatusCompleted, StatusCancelled},
}

// CanTransition отвечает, разрешён ли переход. Решение принимает сервер:
// клиент присылает намерение, а не новый статус (ТЗ §4.4).
func CanTransition(from, to Status) bool {
	for _, s := range allowed[from] {
		if s == to {
			return true
		}
	}
	return false
}

// IsOpen — задание видно в ленте и принимает отклики/ставки.
func IsOpen(s Status) bool {
	return s == StatusPublished || s == StatusCollectingOffers || s == StatusBidding
}
