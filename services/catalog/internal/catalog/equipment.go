package catalog

import (
	"errors"
	"strings"
	"time"
)

// Status — состояние карточки техники (ТЗ §2.5).
type Status string

const (
	// StatusDraft — визард не закончен, машина видна только владельцу.
	StatusDraft Status = "draft"
	// StatusPending — документы отправлены, модерация смотрит (≤24 часа).
	StatusPending Status = "pending"
	// StatusVerified — бейдж «Проверен ✓».
	StatusVerified Status = "verified"
	// StatusUnverified — опубликована без документов: ставки делать можно,
	// но в скоринге такая техника ниже.
	StatusUnverified Status = "unverified"
	// StatusRejected — модерация отклонила, причина в RejectReason.
	StatusRejected Status = "rejected"
	// StatusArchived — владелец снял машину с площадки.
	StatusArchived Status = "archived"
)

// Equipment — единица техники исполнителя.
type Equipment struct {
	ID         string `json:"id"`
	OwnerID    string `json:"ownerId"`
	CategoryID string `json:"categoryId"`

	Brand string `json:"brand"`
	Model string `json:"model"`
	Year  *int   `json:"year,omitempty"`

	// Specs — значения по specTemplate категории.
	Specs map[string]any `json:"specs,omitempty"`

	// Тарифы аренды: пусто — техника только под задания, не в почасовую аренду.
	PriceHour  *int64 `json:"priceHour,omitempty"`
	PriceShift *int64 `json:"priceShift,omitempty"`
	PriceDay   *int64 `json:"priceDay,omitempty"`
	MinHours   *int   `json:"minHours,omitempty"`
	Delivery   *int64 `json:"delivery,omitempty"`

	CrewSize  int    `json:"crewSize"`
	CrewPrice *int64 `json:"crewPrice,omitempty"`

	Photos []string `json:"photos"`
	// Docs наружу не отдаются: их видит только модерация (ТЗ §2.5).
	Docs []string `json:"-"`

	Status       Status `json:"status"`
	RejectReason string `json:"rejectReason,omitempty"`
	DraftStep    int    `json:"draftStep"`
	Wins         int    `json:"wins"`

	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`

	// Название категории подмешивается для карточки: «Земляные работы».
	CategoryName *Name `json:"categoryName,omitempty"`
}

// Title — как машина называется в списке: «JCB 3CX».
func (e Equipment) Title() string {
	return strings.TrimSpace(strings.TrimSpace(e.Brand) + " " + strings.TrimSpace(e.Model))
}

// Active — участвует ли техника в откликах и ставках.
func (e Equipment) Active() bool {
	return e.Status == StatusVerified || e.Status == StatusUnverified
}

var (
	ErrEquipmentNotFound  = errors.New("equipment: техника не найдена")
	ErrEquipmentForeign   = errors.New("equipment: это чужая техника")
	ErrEquipmentPublished = errors.New("equipment: карточка уже опубликована")
	ErrEquipmentStatus    = errors.New("equipment: действие недоступно в этом состоянии")
)

// ValidationError — что именно не заполнено. Клиент подсвечивает поля, а не
// показывает одну общую ошибку на весь визард.
type ValidationError struct {
	Fields map[string]string
}

func (e *ValidationError) Error() string {
	return "equipment: карточка заполнена не полностью"
}

const (
	minYear      = 1980
	maxBrandLen  = 60
	maxModelLen  = 60
	maxPhotos    = 8
	maxCrewSize  = 20
	maxMinHours  = 24
	maxRateValue = 100_000_000
)

// ValidateForPublish проверяет, можно ли выпускать карточку в свет.
// Марка, модель и год — то, по чему заказчик узнаёт машину; без фото карточка
// в ленте откликов выглядит пустой, поэтому хотя бы одно обязательно.
func ValidateForPublish(e *Equipment, now time.Time) error {
	fields := map[string]string{}

	if strings.TrimSpace(e.CategoryID) == "" {
		fields["categoryId"] = "Выберите категорию техники"
	}
	if strings.TrimSpace(e.Brand) == "" {
		fields["brand"] = "Укажите марку"
	}
	if strings.TrimSpace(e.Model) == "" {
		fields["model"] = "Укажите модель"
	}
	if e.Year == nil {
		fields["year"] = "Укажите год выпуска"
	} else if *e.Year < minYear || *e.Year > now.Year() {
		fields["year"] = "Год должен быть между 1980 и текущим"
	}
	if len(e.Photos) == 0 {
		fields["photos"] = "Добавьте хотя бы одно фото техники"
	}

	if len(fields) > 0 {
		return &ValidationError{Fields: fields}
	}
	return nil
}

// Normalize приводит поля к разумным границам: обрезает длинные строки, гасит
// отрицательные тарифы и лишние фото. Делает это до сохранения, чтобы в базе
// не оседал мусор.
func Normalize(e *Equipment) {
	e.Brand = trimTo(e.Brand, maxBrandLen)
	e.Model = trimTo(e.Model, maxModelLen)

	if len(e.Photos) > maxPhotos {
		e.Photos = e.Photos[:maxPhotos]
	}
	if e.CrewSize < 0 {
		e.CrewSize = 0
	}
	if e.CrewSize > maxCrewSize {
		e.CrewSize = maxCrewSize
	}

	clampMoney(&e.PriceHour)
	clampMoney(&e.PriceShift)
	clampMoney(&e.PriceDay)
	clampMoney(&e.Delivery)
	clampMoney(&e.CrewPrice)

	if e.MinHours != nil {
		if *e.MinHours <= 0 {
			e.MinHours = nil
		} else if *e.MinHours > maxMinHours {
			v := maxMinHours
			e.MinHours = &v
		}
	}
	if e.DraftStep < 1 {
		e.DraftStep = 1
	}
	if e.DraftStep > 4 {
		e.DraftStep = 4
	}
}

// StatusAfterSubmit — куда переходит карточка при отправке. С документами она
// уходит на проверку, без них публикуется сразу, но без бейджа: запрещать
// работу до модерации значило бы держать людей без заказов сутки (ТЗ §2.5).
func StatusAfterSubmit(hasDocs bool) Status {
	if hasDocs {
		return StatusPending
	}
	return StatusUnverified
}

// CanEdit — карточку правит только владелец и только пока она не на проверке.
func CanEdit(e *Equipment, userID string) error {
	if e.OwnerID != userID {
		return ErrEquipmentForeign
	}
	if e.Status == StatusPending {
		return ErrEquipmentStatus
	}
	return nil
}

func trimTo(s string, limit int) string {
	s = strings.TrimSpace(s)
	r := []rune(s)
	if len(r) > limit {
		return string(r[:limit])
	}
	return s
}

func clampMoney(v **int64) {
	if *v == nil {
		return
	}
	if **v <= 0 || **v > maxRateValue {
		*v = nil
	}
}
