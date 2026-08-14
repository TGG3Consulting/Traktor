package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"traktor/notifications/internal/push"
	"traktor/notifications/internal/service"
	"traktor/notifications/internal/store"
)

func newServer() (*Server, *push.Fake) {
	st := store.NewMemory()
	fake := push.NewFake()
	svc := service.New(st, fake, time.Now)
	return New(svc), fake
}

// Полный флоу: регистрация устройства → внутренняя рассылка доставляет пуш.
func TestFlow_RegisterThenNotify(t *testing.T) {
	srv, fake := newServer()
	h := srv.Routes()

	// 1) Регистрация без X-User-Id → 401.
	rec := do(h, "POST", "/v1/devices", `{"token":"tok-a","platform":"android"}`, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("без X-User-Id ожидался 401, получен %d", rec.Code)
	}

	// 2) Регистрация с X-User-Id → 204.
	rec = do(h, "POST", "/v1/devices", `{"token":"tok-a","platform":"android","locale":"ru"}`,
		map[string]string{"X-User-Id": "u1"})
	if rec.Code != http.StatusNoContent {
		t.Fatalf("регистрация: ожидался 204, получен %d (%s)", rec.Code, rec.Body.String())
	}

	// 3) Внутренняя рассылка → 200, delivered=1.
	rec = do(h, "POST", "/internal/notify", `{"userId":"u1","title":"Задание","body":"Новый отклик"}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("notify: ожидался 200, получен %d", rec.Code)
	}
	var out struct {
		Delivered int `json:"delivered"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if out.Delivered != 1 {
		t.Fatalf("ожидалась 1 доставка, получено %d", out.Delivered)
	}
	if fake.Count() != 1 {
		t.Fatalf("fake получил %d, ожидалось 1", fake.Count())
	}

	// 4) Снятие регистрации → 204, после — рассылка никому не уходит.
	rec = do(h, "DELETE", "/v1/devices/tok-a", "", map[string]string{"X-User-Id": "u1"})
	if rec.Code != http.StatusNoContent {
		t.Fatalf("unregister: ожидался 204, получен %d", rec.Code)
	}
	rec = do(h, "POST", "/internal/notify", `{"userId":"u1","title":"t","body":"b"}`, nil)
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if out.Delivered != 0 {
		t.Fatalf("после снятия ожидалось 0 доставок, получено %d", out.Delivered)
	}
}

func TestRegister_BadBody(t *testing.T) {
	srv, _ := newServer()
	rec := do(srv.Routes(), "POST", "/v1/devices", `{"platform":"android"}`,
		map[string]string{"X-User-Id": "u1"})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("без токена ожидался 400, получен %d", rec.Code)
	}
}

func TestHealthz(t *testing.T) {
	srv, _ := newServer()
	rec := do(srv.Routes(), "GET", "/healthz", "", nil)
	if rec.Code != 200 {
		t.Fatalf("healthz: %d", rec.Code)
	}
}

func do(h http.Handler, method, path, body string, headers map[string]string) *httptest.ResponseRecorder {
	var r *http.Request
	if body == "" {
		r = httptest.NewRequestWithContext(context.Background(), method, path, nil)
	} else {
		r = httptest.NewRequestWithContext(context.Background(), method, path, strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
	}
	for k, v := range headers {
		r.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	return rec
}
