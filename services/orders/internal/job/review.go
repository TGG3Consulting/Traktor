package job

import (
	"errors"
	"strings"
	"time"
)

// Review — взаимная оценка после сделки (ТЗ §2.13).
//
// Отзывы обеих сторон публикуются одновременно — либо когда оценили оба, либо
// через неделю. Так никто не подстраивает свою оценку под чужую и не мстит за
// низкую: паттерн, проверенный Airbnb.
type Review struct {
	ID     string `json:"id"`
	DealID string `json:"dealId"`
	JobID  string `json:"jobId"`

	AuthorID string `json:"authorId"`
	TargetID string `json:"targetId"`

	// Кем был автор в этой сделке: заказчик оценивает исполнителя и наоборот.
	AuthorRole string `json:"authorRole"`

	Stars int      `json:"stars"`
	Tags  []string `json:"tags,omitempty"`
	Text  string   `json:"text,omitempty"`

	// Что пошло не так — необязательный ответ при оценке ниже трёх звёзд.
	// Нужен модерации, публично не показывается (ТЗ §2.13).
	Issue string `json:"-"`

	// Ответ на отзыв — один раз, публично.
	ReplyText string     `json:"replyText,omitempty"`
	ReplyAt   *time.Time `json:"replyAt,omitempty"`

	PublishedAt *time.Time `json:"publishedAt,omitempty"`
	CreatedAt   time.Time  `json:"createdAt"`
}

// Published — виден ли отзыв посторонним.
func (r Review) Published() bool { return r.PublishedAt != nil }

// RatingSummary — сводка для карточки профиля: «★4,8 · 36 оценок».
type RatingSummary struct {
	UserID string  `json:"userId"`
	Rating float64 `json:"rating"`
	Count  int     `json:"count"`
}

const (
	// RoleClient — автор был заказчиком, оценивает исполнителя.
	RoleClient = "client"
	// RoleOwner — автор был исполнителем, оценивает заказчика.
	RoleOwner = "owner"

	// HoldPeriod — через сколько отзыв публикуется, даже если вторая сторона
	// промолчала. Иначе односторонние оценки висели бы вечно.
	HoldPeriod = 7 * 24 * time.Hour

	// RatingWindow — рейтинг считается за последний год: свежая работа важнее
	// старых промахов (ТЗ §2.13).
	RatingWindow = 365 * 24 * time.Hour

	maxReviewText = 500
	maxIssueText  = 500
	maxTags       = 6
)

// clientTags — что заказчик отмечает у исполнителя, ownerTags — наоборот.
// Списки закрытые: свободные теги превращаются в мусор и не агрегируются.
var (
	clientTags = map[string]bool{
		"Пунктуально":       true,
		"Аккуратно":         true,
		"Техника в порядке": true,
		"Вежливо":           true,
	}
	ownerTags = map[string]bool{
		"Чёткое ТЗ":         true,
		"Оплата без проблем": true,
		"Подъезд как описан": true,
		"Вежливо":            true,
	}
)

var (
	ErrReviewNotFound  = errors.New("review: отзыв не найден")
	ErrReviewForbidden = errors.New("review: оценивать может только участник сделки")
	ErrReviewTooEarly  = errors.New("review: оценка доступна после завершения сделки")
	ErrReviewTwice     = errors.New("review: вы уже оценили эту сделку")
	ErrReviewStars     = errors.New("review: поставьте от 1 до 5 звёзд")
	ErrReviewTag       = errors.New("review: неизвестная отметка")
	ErrReviewLong      = errors.New("review: отзыв длиннее 500 символов")
	ErrReplyTwice      = errors.New("review: ответить на отзыв можно один раз")
	ErrReplyForeign    = errors.New("review: отвечать может только тот, кого оценили")
)

// AllowedTags — набор отметок для роли автора: клиент экрана показывает
// ровно то, что примет сервер.
func AllowedTags(authorRole string) []string {
	if authorRole == RoleOwner {
		return []string{"Чёткое ТЗ", "Оплата без проблем", "Подъезд как описан", "Вежливо"}
	}
	return []string{"Пунктуально", "Аккуратно", "Техника в порядке", "Вежливо"}
}

// CanReview — можно ли оценивать эту сделку и вправе ли это делать человек.
func CanReview(d *Deal, userID string) error {
	if d.ClientID != userID && d.OwnerID != userID {
		return ErrReviewForbidden
	}
	// Оценку даёт только завершённая работа. По отменённым сделкам оценивать
	// нечего: там нет результата, зато есть эмоции.
	if d.Status != DealCompleted {
		return ErrReviewTooEarly
	}
	return nil
}

// ValidateReview проверяет оценку. Звёзды обязательны, текст — нет: заставлять
// человека писать ради галочки значит получить «нормально» вместо отзыва.
func ValidateReview(r *Review) error {
	if r.Stars < 1 || r.Stars > 5 {
		return ErrReviewStars
	}
	r.Text = strings.TrimSpace(r.Text)
	if len([]rune(r.Text)) > maxReviewText {
		return ErrReviewLong
	}
	r.Issue = strings.TrimSpace(r.Issue)
	if len([]rune(r.Issue)) > maxIssueText {
		r.Issue = string([]rune(r.Issue)[:maxIssueText])
	}
	if len(r.Tags) > maxTags {
		return ErrReviewTag
	}

	allowed := clientTags
	if r.AuthorRole == RoleOwner {
		allowed = ownerTags
	}
	seen := map[string]bool{}
	tags := make([]string, 0, len(r.Tags))
	for _, t := range r.Tags {
		t = strings.TrimSpace(t)
		if t == "" || seen[t] {
			continue
		}
		if !allowed[t] {
			return ErrReviewTag
		}
		seen[t] = true
		tags = append(tags, t)
	}
	r.Tags = tags
	return nil
}

// AsksWhatWentWrong — низкая оценка: спрашиваем, что пошло не так. Вопрос
// необязательный, но именно эти ответы дают модерации материал (ТЗ §2.13).
func AsksWhatWentWrong(stars int) bool { return stars > 0 && stars < 3 }

// ShouldPublish — пора ли открывать отзыв. Обоюдные оценки публикуются сразу,
// одинокая — через неделю ожидания.
func ShouldPublish(mine *Review, theirs *Review, now time.Time) bool {
	if mine == nil || mine.Published() {
		return false
	}
	if theirs != nil {
		return true
	}
	return !now.Before(mine.CreatedAt.Add(HoldPeriod))
}

// CanReply — ответить на отзыв может только тот, о ком он написан, и только
// после публикации: спорить с невидимым текстом бессмысленно.
func CanReply(r *Review, userID string) error {
	if r.TargetID != userID {
		return ErrReplyForeign
	}
	if !r.Published() {
		return ErrReviewTooEarly
	}
	if r.ReplyText != "" {
		return ErrReplyTwice
	}
	return nil
}

// ValidateReply проверяет текст ответа.
func ValidateReply(text string) (string, error) {
	text = strings.TrimSpace(text)
	if text == "" {
		return "", ErrReviewLong
	}
	if len([]rune(text)) > maxReviewText {
		return "", ErrReviewLong
	}
	return text, nil
}

// Rating — средняя оценка по опубликованным отзывам за последний год,
// округлённая до десятых: «4,83» в карточке выглядит машинно.
func Rating(reviews []Review, now time.Time) RatingSummary {
	from := now.Add(-RatingWindow)
	sum, count := 0, 0
	for _, r := range reviews {
		if !r.Published() || r.CreatedAt.Before(from) {
			continue
		}
		sum += r.Stars
		count++
	}
	if count == 0 {
		return RatingSummary{Rating: 0, Count: 0}
	}
	avg := float64(sum) / float64(count)
	return RatingSummary{Rating: float64(int(avg*10+0.5)) / 10, Count: count}
}
