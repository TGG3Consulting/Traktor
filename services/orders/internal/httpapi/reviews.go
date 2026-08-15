package httpapi

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"traktor/orders/internal/job"
	"traktor/orders/internal/profiles"
)

type reviewBody struct {
	Stars int      `json:"stars"`
	Tags  []string `json:"tags"`
	Text  string   `json:"text"`
	// Что пошло не так — необязательный ответ при низкой оценке. Публично
	// не показывается, уходит модерации (ТЗ §2.13).
	Issue string `json:"issue"`
}

type replyBody struct {
	Text string `json:"text"`
}

// leaveReview — оценка по завершённой сделке.
func (s *Server) leaveReview(w http.ResponseWriter, r *http.Request) {
	var body reviewBody
	if !decode(w, r, &body) {
		return
	}
	rev, err := s.svc.LeaveReview(r.Context(), r.Header.Get(userHeader),
		chi.URLParam(r, "dealId"), job.Review{
			Stars: body.Stars,
			Tags:  body.Tags,
			Text:  body.Text,
			Issue: body.Issue,
		})
	if err != nil {
		failReview(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"review": rev,
		// Пока вторая сторона молчит, отзыв скрыт: клиент честно говорит об
		// этом, иначе человек решит, что оценка пропала.
		"published":         rev.Published(),
		"asksWhatWentWrong": job.AsksWhatWentWrong(rev.Stars),
	})
}

// myReviewForDeal — моя оценка по сделке (или её отсутствие) плюс подсказка,
// какие отметки показывать: набор зависит от роли в сделке.
func (s *Server) myReviewForDeal(w http.ResponseWriter, r *http.Request) {
	me := r.Header.Get(userHeader)
	dealID := chi.URLParam(r, "dealId")

	d, err := s.svc.Deal(r.Context(), me, dealID)
	if err != nil {
		fail(w, err)
		return
	}
	role := job.RoleOwner
	target := d.ClientID
	if me == d.ClientID {
		role, target = job.RoleClient, d.OwnerID
	}

	out := map[string]any{
		"dealId":      dealID,
		"authorRole":  role,
		"allowedTags": job.AllowedTags(role),
		"canReview":   job.CanReview(d, me) == nil,
	}
	if people := s.svc.Profiles(r.Context(), []string{target}); len(people) > 0 {
		out["targetName"] = profiles.DisplayName(people[target], "Собеседник")
	}
	if mine, err := s.svc.MyReviewForDeal(r.Context(), me, dealID); err == nil {
		out["review"] = mine
	}
	writeJSON(w, http.StatusOK, out)
}

// userReviews — публичная карточка: отзывы о человеке и сводка рейтинга.
func (s *Server) userReviews(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	userID := chi.URLParam(r, "userId")
	items, summary, err := s.svc.ReviewsAbout(r.Context(), userID, limit, offset)
	if err != nil {
		failReview(w, err)
		return
	}

	// Имя автора отзыва: «★5 от Карена» читается, «★5 от 3f2a…» — нет.
	ids := make([]string, 0, len(items))
	for _, it := range items {
		ids = append(ids, it.AuthorID)
	}
	people := s.svc.Profiles(r.Context(), ids)

	out := make([]map[string]any, 0, len(items))
	for _, it := range items {
		row := map[string]any{
			"id":          it.ID,
			"jobId":       it.JobID,
			"stars":       it.Stars,
			"tags":        it.Tags,
			"text":        it.Text,
			"replyText":   it.ReplyText,
			"replyAt":     it.ReplyAt,
			"publishedAt": it.PublishedAt,
			"createdAt":   it.CreatedAt,
			"authorName":  profiles.DisplayName(people[it.AuthorID], "Пользователь"),
		}
		out = append(out, row)
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items":  out,
		"rating": summary.Rating,
		"count":  summary.Count,
	})
}

// replyToReview — публичный ответ на отзыв о себе.
func (s *Server) replyToReview(w http.ResponseWriter, r *http.Request) {
	var body replyBody
	if !decode(w, r, &body) {
		return
	}
	rev, err := s.svc.ReplyToReview(r.Context(), r.Header.Get(userHeader),
		chi.URLParam(r, "reviewId"), body.Text)
	if err != nil {
		failReview(w, err)
		return
	}
	writeJSON(w, http.StatusOK, rev)
}

func failReview(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, job.ErrReviewNotFound):
		problem(w, http.StatusNotFound, "review_not_found", "отзыв не найден")
	case errors.Is(err, job.ErrReviewForbidden), errors.Is(err, job.ErrReplyForeign):
		problem(w, http.StatusForbidden, "review_forbidden", err.Error())
	case errors.Is(err, job.ErrReviewTooEarly):
		problem(w, http.StatusConflict, "review_too_early",
			"оценка доступна после завершения сделки")
	case errors.Is(err, job.ErrReviewFrozen):
		problem(w, http.StatusConflict, "review_frozen",
			"идёт разбор спора — оценки станут доступны после решения")
	case errors.Is(err, job.ErrReviewTwice):
		problem(w, http.StatusConflict, "review_twice", "вы уже оценили эту сделку")
	case errors.Is(err, job.ErrReplyTwice):
		problem(w, http.StatusConflict, "reply_twice", "ответить на отзыв можно один раз")
	case errors.Is(err, job.ErrReviewStars):
		problem(w, http.StatusBadRequest, "review_stars", "поставьте от 1 до 5 звёзд")
	case errors.Is(err, job.ErrReviewTag):
		problem(w, http.StatusBadRequest, "review_tag", "неизвестная отметка")
	case errors.Is(err, job.ErrReviewLong):
		problem(w, http.StatusBadRequest, "review_long", "отзыв длиннее 500 символов")
	default:
		fail(w, err)
	}
}
