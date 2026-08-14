package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"traktor/orders/internal/job"
	"traktor/orders/internal/service"
	"traktor/orders/internal/store"
)

const (
	client = "11111111-1111-1111-1111-111111111111"
	owner  = "22222222-2222-2222-2222-222222222222"
	catID  = "c02b2502-1789-5217-be9f-d5fc04fe1cae"
)

func newAPI() http.Handler {
	fixed := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
	return New(service.New(store.NewMemory(), func() time.Time { return fixed })).Routes()
}

func do(t *testing.T, h http.Handler, method, path, user, body string) *httptest.ResponseRecorder {
	t.Helper()
	var r *http.Request
	if body == "" {
		r = httptest.NewRequest(method, path, nil)
	} else {
		r = httptest.NewRequest(method, path, bytes.NewBufferString(body))
		r.Header.Set("Content-Type", "application/json")
	}
	if user != "" {
		r.Header.Set("X-User-Id", user)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	return rec
}

func decodeJob(t *testing.T, rec *httptest.ResponseRecorder) job.Job {
	t.Helper()
	var j job.Job
	if err := json.Unmarshal(rec.Body.Bytes(), &j); err != nil {
		t.Fatalf("ответ не разобрался: %v (%s)", err, rec.Body.String())
	}
	return j
}

const fullDraftBody = `{
  "categoryId": "` + catID + `",
  "title": "Выкопать траншею 40 м под водопровод",
  "description": "Траншея вдоль забора, глубина 1,2 м, грунт мягкий, подъезд есть.",
  "geo": {"lat": 40.1872, "lng": 44.5152},
  "address": "Ереван, Аван",
  "budgetAmount": 120000,
  "draftStep": 4
}`

func TestПолныйПутьВизардаОтЧерновикаДоПубликации(t *testing.T) {
	h := newAPI()

	created := do(t, h, http.MethodPost, "/v1/jobs/drafts", client, fullDraftBody)
	if created.Code != http.StatusCreated {
		t.Fatalf("создание черновика: ожидали 201, получили %d (%s)", created.Code, created.Body)
	}
	draft := decodeJob(t, created)
	if draft.Status != job.StatusDraft {
		t.Fatalf("новое задание должно быть черновиком, получили %s", draft.Status)
	}

	// Черновик виден на главной заказчика вместе с остальными заданиями.
	my := do(t, h, http.MethodGet, "/v1/jobs/my", client, "")
	if my.Code != http.StatusOK {
		t.Fatalf("мои задания: %d", my.Code)
	}

	published := do(t, h, http.MethodPost, "/v1/jobs/"+draft.ID+"/publish", client, "")
	if published.Code != http.StatusOK {
		t.Fatalf("публикация: ожидали 200, получили %d (%s)", published.Code, published.Body)
	}
	if decodeJob(t, published).Status != job.StatusCollectingOffers {
		t.Fatal("после публикации фикс-цена собирает отклики")
	}

	// Опубликованное появилось в ленте.
	feed := do(t, h, http.MethodGet, "/v1/jobs?lat=40.18&lng=44.51&radiusKm=25&sort=near", owner, "")
	var list struct {
		Items []job.Job `json:"items"`
	}
	_ = json.Unmarshal(feed.Body.Bytes(), &list)
	if len(list.Items) != 1 {
		t.Fatalf("в ленте должно быть одно задание, получили %d", len(list.Items))
	}
	if list.Items[0].DistanceM == nil {
		t.Fatal("лента должна отдавать расстояние до задания")
	}
}

func TestНезаполненныйЧерновикВозвращаетСписокПолей(t *testing.T) {
	h := newAPI()
	created := do(t, h, http.MethodPost, "/v1/jobs/drafts", client, `{"title":"Что-то"}`)
	draft := decodeJob(t, created)

	rec := do(t, h, http.MethodPost, "/v1/jobs/"+draft.ID+"/publish", client, "")

	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("ожидали 422, получили %d", rec.Code)
	}
	var body struct {
		Code   string            `json:"code"`
		Fields map[string]string `json:"fields"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body.Code != "validation_failed" || body.Fields["description"] == "" {
		t.Fatalf("клиенту нужен разбор по полям: %s", rec.Body.String())
	}
}

func TestБезВходаЧерновикиНедоступны(t *testing.T) {
	h := newAPI()

	rec := do(t, h, http.MethodPost, "/v1/jobs/drafts", "", fullDraftBody)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("ожидали 401, получили %d", rec.Code)
	}
}

func TestЛентаОткрытаГостю(t *testing.T) {
	h := newAPI()

	rec := do(t, h, http.MethodGet, "/v1/jobs", "", "")

	if rec.Code != http.StatusOK {
		t.Fatalf("гостевая лента должна работать без входа, получили %d", rec.Code)
	}
}

func TestЧужойЧерновикНеРедактируется(t *testing.T) {
	h := newAPI()
	draft := decodeJob(t, do(t, h, http.MethodPost, "/v1/jobs/drafts", client, fullDraftBody))

	rec := do(t, h, http.MethodPatch, "/v1/jobs/drafts/"+draft.ID, owner, `{"title":"подмена"}`)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("ожидали 403, получили %d", rec.Code)
	}
}

func TestПовторнаяПубликацияДаётКонфликт(t *testing.T) {
	h := newAPI()
	draft := decodeJob(t, do(t, h, http.MethodPost, "/v1/jobs/drafts", client, fullDraftBody))
	_ = do(t, h, http.MethodPost, "/v1/jobs/"+draft.ID+"/publish", client, "")

	rec := do(t, h, http.MethodPost, "/v1/jobs/"+draft.ID+"/publish", client, "")

	if rec.Code != http.StatusConflict {
		t.Fatalf("ожидали 409, получили %d (%s)", rec.Code, rec.Body)
	}
}

// Повтор запроса с тем же Idempotency-Key не должен плодить черновики:
// в мобильной сети клиент часто повторяет отправку.
func TestКлючИдемпотентностиНеСоздаётВторойЧерновик(t *testing.T) {
	h := newAPI()

	first := httptest.NewRequest(http.MethodPost, "/v1/jobs/drafts", bytes.NewBufferString(fullDraftBody))
	first.Header.Set("X-User-Id", client)
	first.Header.Set("Idempotency-Key", "abc")
	rec1 := httptest.NewRecorder()
	h.ServeHTTP(rec1, first)

	second := httptest.NewRequest(http.MethodPost, "/v1/jobs/drafts", bytes.NewBufferString(fullDraftBody))
	second.Header.Set("X-User-Id", client)
	second.Header.Set("Idempotency-Key", "abc")
	rec2 := httptest.NewRecorder()
	h.ServeHTTP(rec2, second)

	if decodeJob(t, rec1).ID != decodeJob(t, rec2).ID {
		t.Fatal("повтор с тем же ключом должен вернуть то же задание")
	}
	my := do(t, h, http.MethodGet, "/v1/jobs/my", client, "")
	var list struct {
		Items []job.Job `json:"items"`
	}
	_ = json.Unmarshal(my.Body.Bytes(), &list)
	if len(list.Items) != 1 {
		t.Fatalf("черновик должен быть один, получили %d", len(list.Items))
	}
}

func TestНеизвестноеПолеВТелеОтклоняется(t *testing.T) {
	h := newAPI()

	rec := do(t, h, http.MethodPost, "/v1/jobs/drafts", client, `{"title":"ок","цена":100}`)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("опечатка в имени поля должна быть видна сразу, получили %d", rec.Code)
	}
}

func TestДеталкаСкрываетРезервОтИсполнителя(t *testing.T) {
	h := newAPI()
	draft := decodeJob(t, do(t, h, http.MethodPost, "/v1/jobs/drafts", client, fullDraftBody))
	_ = do(t, h, http.MethodPatch, "/v1/jobs/drafts/"+draft.ID, client,
		`{"mode":"auction","auction":{"durationH":24,"decisionWindowH":12,"reserveAmount":70000}}`)
	_ = do(t, h, http.MethodPost, "/v1/jobs/"+draft.ID+"/publish", client, "")

	forOwner := decodeJob(t, do(t, h, http.MethodGet, "/v1/jobs/"+draft.ID, owner, ""))
	forClient := decodeJob(t, do(t, h, http.MethodGet, "/v1/jobs/"+draft.ID, client, ""))

	if forOwner.Auction == nil || forOwner.Auction.ReserveAmount != nil {
		t.Fatal("исполнителю нельзя показывать минимальную цену")
	}
	if forOwner.Auction.EndsAt == nil {
		t.Fatal("время финиша исполнителю нужно — по нему идёт таймер")
	}
	if forClient.Auction.ReserveAmount == nil {
		t.Fatal("заказчик свою минимальную цену видеть должен")
	}
}

func TestНесуществующееЗаданиеДаёт404(t *testing.T) {
	h := newAPI()

	rec := do(t, h, http.MethodGet, "/v1/jobs/00000000-0000-0000-0000-000000000000", owner, "")

	if rec.Code != http.StatusNotFound {
		t.Fatalf("ожидали 404, получили %d", rec.Code)
	}
}
