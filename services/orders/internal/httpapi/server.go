// Package httpapi — HTTP-слой сервиса orders.
//
// Пользователя определяет шлюз: он проверяет JWT и проставляет X-User-Id.
// Сервис доверяет только этому заголовку и никогда — телу запроса.
package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"traktor/orders/internal/job"
	"traktor/orders/internal/service"
	"traktor/orders/internal/store"
)

const userHeader = "X-User-Id"

type Server struct{ svc *service.Service }

func New(svc *service.Service) *Server { return &Server{svc: svc} }

func (s *Server) Routes() http.Handler {
	r := chi.NewRouter()
	r.Use(chimw.RequestID, chimw.RealIP, chimw.Recoverer)

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	r.Route("/v1/jobs", func(r chi.Router) {
		// Лента — единственное место, доступное гостю: «просто посмотреть»
		// из онбординга (ТЗ §2.1) должно работать без входа.
		r.Get("/", s.feed)

		r.Group(func(r chi.Router) {
			r.Use(s.requireUser)
			r.Get("/my", s.myJobs)
			r.Post("/drafts", s.createDraft)
			r.Patch("/drafts/{id}", s.updateDraft)
			r.Post("/{id}/publish", s.publish)
			r.Post("/{id}/cancel", s.cancel)

			// Отклики по заданию (ТЗ §2.10) — именные действия, только с входом.
			r.Post("/{id}/offers", s.makeOffer)
			r.Get("/{id}/offers", s.jobOffers)
			r.Get("/{id}/offers/my", s.myOfferForJob)
		})

		r.Get("/{id}", s.view)
	})

	// Решения по конкретному предложению.
	r.Route("/v1/offers", func(r chi.Router) {
		r.Use(s.requireUser)
		r.Get("/my", s.myOffers)
		r.Post("/{offerId}/withdraw", s.withdrawOffer)
		r.Post("/{offerId}/accept", s.acceptOffer)
		r.Post("/{offerId}/decline", s.declineOffer)
		r.Post("/{offerId}/counter", s.counterOffer)
	})
	return r
}

// requireUser отклоняет запросы без пользователя: шлюз обязан подставить
// X-User-Id, а прямой доступ к сервису в обход шлюза — не наш сценарий.
func (s *Server) requireUser(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.TrimSpace(r.Header.Get(userHeader)) == "" {
			problem(w, http.StatusUnauthorized, "unauthorized", "нужен вход")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) createDraft(w http.ResponseWriter, r *http.Request) {
	user := r.Header.Get(userHeader)
	key := r.Header.Get("Idempotency-Key")
	const endpoint = "POST /v1/jobs/drafts"

	if existing, ok, err := s.svc.Idempotent(r.Context(), key, user, endpoint); err == nil && ok {
		writeJSON(w, http.StatusOK, existing)
		return
	}

	var body draftBody
	if !decode(w, r, &body) {
		return
	}
	in, err := body.toInput()
	if err != nil {
		problem(w, http.StatusBadRequest, "invalid_body", err.Error())
		return
	}

	j, err := s.svc.CreateDraft(r.Context(), user, in)
	if err != nil {
		fail(w, err)
		return
	}
	_ = s.svc.RememberIdempotent(r.Context(), key, user, endpoint, j.ID)
	writeJSON(w, http.StatusCreated, j)
}

func (s *Server) updateDraft(w http.ResponseWriter, r *http.Request) {
	var body draftBody
	if !decode(w, r, &body) {
		return
	}
	in, err := body.toInput()
	if err != nil {
		problem(w, http.StatusBadRequest, "invalid_body", err.Error())
		return
	}

	j, err := s.svc.UpdateDraft(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "id"), in)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, j)
}

func (s *Server) publish(w http.ResponseWriter, r *http.Request) {
	user := r.Header.Get(userHeader)
	id := chi.URLParam(r, "id")
	key := r.Header.Get("Idempotency-Key")
	const endpoint = "POST /v1/jobs/publish"

	if existing, ok, err := s.svc.Idempotent(r.Context(), key, user, endpoint); err == nil && ok {
		writeJSON(w, http.StatusOK, existing)
		return
	}

	j, err := s.svc.Publish(r.Context(), user, id)
	if err != nil {
		fail(w, err)
		return
	}
	_ = s.svc.RememberIdempotent(r.Context(), key, user, endpoint, j.ID)
	writeJSON(w, http.StatusOK, j)
}

func (s *Server) cancel(w http.ResponseWriter, r *http.Request) {
	j, err := s.svc.Cancel(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "id"))
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, j)
}

func (s *Server) myJobs(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	items, err := s.svc.MyJobs(r.Context(), r.Header.Get(userHeader), limit, offset)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) feed(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	f := store.Filter{
		Mode:  job.Mode(q.Get("mode")),
		Query: q.Get("q"),
		Sort:  store.Sort(q.Get("sort")),
	}
	f.Limit, _ = strconv.Atoi(q.Get("limit"))
	f.Offset, _ = strconv.Atoi(q.Get("offset"))

	if lat, err := floatParam(q.Get("lat")); err == nil && lat != nil {
		f.Lat = lat
	}
	if lng, err := floatParam(q.Get("lng")); err == nil && lng != nil {
		f.Lng = lng
	}
	// Радиус приходит в километрах — так его показывают в чипах фильтра.
	if km, err := floatParam(q.Get("radiusKm")); err == nil && km != nil {
		m := *km * 1000
		f.RadiusM = &m
	}
	if cats := strings.TrimSpace(q.Get("categoryIds")); cats != "" {
		f.CategoryIDs = strings.Split(cats, ",")
	}
	if f.Mode != "" && f.Mode != job.ModeFixed && f.Mode != job.ModeAuction {
		problem(w, http.StatusBadRequest, "invalid_mode", "mode может быть fixed или auction")
		return
	}

	items, err := s.svc.Feed(r.Context(), f)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) view(w http.ResponseWriter, r *http.Request) {
	// Гость тоже может открыть деталку — просмотр тогда не считаем.
	viewer := r.Header.Get(userHeader)
	if viewer == "" {
		viewer = "guest"
	}
	j, err := s.svc.View(r.Context(), viewer, chi.URLParam(r, "id"))
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, j)
}

// ── тело запроса ─────────────────────────────────────────────────────────────

// draftBody повторяет поля визарда. Все указатели: отсутствие поля означает
// «не трогать», а не «очистить» — иначе сохранение шага стирало бы соседние.
type draftBody struct {
	OrderType    *string        `json:"orderType"`
	CategoryID   *string        `json:"categoryId"`
	OpenToAny    *bool          `json:"openToAny"`
	Title        *string        `json:"title"`
	Description  *string        `json:"description"`
	Params       map[string]any `json:"params"`
	Photos       []string       `json:"photos"`
	Geo          *job.Geo       `json:"geo"`
	Address      *string        `json:"address"`
	Access       *string        `json:"access"`
	DateMode     *string        `json:"dateMode"`
	DateStart    *string        `json:"dateStart"`
	DateEnd      *string        `json:"dateEnd"`
	BudgetAmount *int64         `json:"budgetAmount"`
	Currency     *string        `json:"currency"`
	Mode         *string        `json:"mode"`
	Auction      *auctionBody   `json:"auction"`
	WorkersCount *int           `json:"workersCount"`
	DraftStep    *int           `json:"draftStep"`
}

type auctionBody struct {
	DurationH       int    `json:"durationH"`
	ReserveAmount   *int64 `json:"reserveAmount"`
	AutoExtend      *bool  `json:"autoExtend"`
	DecisionWindowH int    `json:"decisionWindowH"`
}

func (b draftBody) toInput() (service.DraftInput, error) {
	in := service.DraftInput{
		CategoryID:   b.CategoryID,
		OpenToAny:    b.OpenToAny,
		Title:        b.Title,
		Description:  b.Description,
		Params:       b.Params,
		Photos:       b.Photos,
		Geo:          b.Geo,
		Address:      b.Address,
		BudgetAmount: b.BudgetAmount,
		Currency:     b.Currency,
		WorkersCount: b.WorkersCount,
		DraftStep:    b.DraftStep,
	}

	if b.OrderType != nil {
		t := job.OrderType(*b.OrderType)
		switch t {
		case job.TypeJob, job.TypeRental, job.TypeTransport, job.TypeWorkers:
			in.OrderType = &t
		default:
			return in, errors.New("неизвестный тип заказа")
		}
	}
	if b.Access != nil {
		a := job.Access(*b.Access)
		switch a {
		case job.AccessYes, job.AccessNo, job.AccessUnknown:
			in.Access = &a
		default:
			return in, errors.New("access может быть yes, no или unknown")
		}
	}
	if b.DateMode != nil {
		d := job.DateMode(*b.DateMode)
		switch d {
		case job.DateASAP, job.DateRange, job.DateExact:
			in.DateMode = &d
		default:
			return in, errors.New("dateMode может быть asap, range или exact")
		}
	}
	if b.Mode != nil {
		m := job.Mode(*b.Mode)
		switch m {
		case job.ModeFixed, job.ModeAuction:
			in.Mode = &m
		default:
			return in, errors.New("mode может быть fixed или auction")
		}
	}
	var err error
	if in.DateStart, err = parseTime(b.DateStart); err != nil {
		return in, errors.New("dateStart: ожидается время в формате RFC 3339")
	}
	if in.DateEnd, err = parseTime(b.DateEnd); err != nil {
		return in, errors.New("dateEnd: ожидается время в формате RFC 3339")
	}
	if b.Auction != nil {
		a := job.Auction{
			DurationH:       b.Auction.DurationH,
			ReserveAmount:   b.Auction.ReserveAmount,
			AutoExtend:      true,
			DecisionWindowH: b.Auction.DecisionWindowH,
		}
		if b.Auction.AutoExtend != nil {
			a.AutoExtend = *b.Auction.AutoExtend
		}
		in.Auction = &a
	}
	return in, nil
}

func parseTime(v *string) (*time.Time, error) {
	if v == nil || *v == "" {
		return nil, nil
	}
	t, err := time.Parse(time.RFC3339, *v)
	if err != nil {
		return nil, err
	}
	return &t, nil
}

func floatParam(v string) (*float64, error) {
	if strings.TrimSpace(v) == "" {
		return nil, nil
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil {
		return nil, err
	}
	return &f, nil
}

// ── ответы ───────────────────────────────────────────────────────────────────

func decode(w http.ResponseWriter, r *http.Request, dst any) bool {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		problem(w, http.StatusBadRequest, "invalid_body", "не удалось разобрать запрос: "+err.Error())
		return false
	}
	return true
}

// fail переводит доменные ошибки в коды ответа. Список незаполненных полей
// уходит клиенту целиком — экран подсвечивает их и пишет, чего не хватает.
func fail(w http.ResponseWriter, err error) {
	var ve *job.ValidationError
	switch {
	case errors.As(err, &ve):
		w.Header().Set("Content-Type", "application/problem+json; charset=utf-8")
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"type": "about:blank", "status": http.StatusUnprocessableEntity,
			"code": "validation_failed", "title": "Не хватает данных для публикации",
			"fields": ve.Fields,
		})
	case errors.Is(err, job.ErrNotFound):
		problem(w, http.StatusNotFound, "not_found", "задание не найдено")
	case errors.Is(err, job.ErrForbidden):
		problem(w, http.StatusForbidden, "forbidden", "это задание другого пользователя")
	case errors.Is(err, job.ErrNotDraft):
		problem(w, http.StatusConflict, "not_draft", "менять можно только черновик")
	case errors.Is(err, job.ErrBadTransition):
		problem(w, http.StatusConflict, "bad_transition", "недопустимое действие для текущего статуса")
	default:
		problem(w, http.StatusInternalServerError, "internal", "внутренняя ошибка")
	}
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func problem(w http.ResponseWriter, status int, code, title string) {
	w.Header().Set("Content-Type", "application/problem+json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"type": "about:blank", "status": status, "code": code, "title": title,
	})
}
