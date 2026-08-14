package push

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type staticToken struct{ t string }

func (s staticToken) Token(context.Context) (string, error) { return s.t, nil }

// Подменяем базовый URL FCM на тестовый сервер через кастомный транспорт.
type rewriteTransport struct {
	base string
	rt   http.RoundTripper
}

func (t rewriteTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	// Перенаправляем fcm.googleapis.com на локальный httptest-сервер.
	u := t.base + r.URL.Path
	nr := r.Clone(r.Context())
	parsed, _ := nr.URL.Parse(u)
	nr.URL = parsed
	nr.Host = parsed.Host
	return t.rt.RoundTrip(nr)
}

func TestFCM_Send_OK(t *testing.T) {
	var gotAuth, gotBody string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		b, _ := io.ReadAll(r.Body)
		gotBody = string(b)
		w.WriteHeader(200)
		_, _ = w.Write([]byte(`{"name":"projects/p/messages/1"}`))
	}))
	defer srv.Close()

	c := NewFCM("proj-1", staticToken{"acc-tok"})
	c.http = &http.Client{Transport: rewriteTransport{base: srv.URL, rt: http.DefaultTransport}}

	err := c.Send(context.Background(), Message{
		Token: "dev-tok", Title: "Задание", Body: "Отклик", Data: map[string]string{"type": "deal.updated"},
	})
	if err != nil {
		t.Fatalf("send: %v", err)
	}
	if gotAuth != "Bearer acc-tok" {
		t.Fatalf("Authorization: %q", gotAuth)
	}
	// Проверяем формат v1: message.token + notification.
	var payload map[string]any
	if err := json.Unmarshal([]byte(gotBody), &payload); err != nil {
		t.Fatalf("тело не JSON: %v", err)
	}
	msg, _ := payload["message"].(map[string]any)
	if msg["token"] != "dev-tok" {
		t.Fatalf("token в теле: %v", msg["token"])
	}
	if !strings.Contains(gotBody, "notification") {
		t.Fatalf("нет notification в теле: %s", gotBody)
	}
}

func TestFCM_Send_InvalidToken(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"error":{"status":"NOT_FOUND"}}`))
	}))
	defer srv.Close()

	c := NewFCM("proj-1", staticToken{"acc-tok"})
	c.http = &http.Client{Transport: rewriteTransport{base: srv.URL, rt: http.DefaultTransport}}

	err := c.Send(context.Background(), Message{Token: "dead", Title: "t", Body: "b"})
	if err != ErrTokenInvalid {
		t.Fatalf("ожидался ErrTokenInvalid, получено %v", err)
	}
}

func TestFCM_Send_InvalidArgumentDetail(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":{"status":"INVALID_ARGUMENT","details":[{"errorCode":"UNREGISTERED"}]}}`))
	}))
	defer srv.Close()

	c := NewFCM("proj-1", staticToken{"acc-tok"})
	c.http = &http.Client{Transport: rewriteTransport{base: srv.URL, rt: http.DefaultTransport}}

	if err := c.Send(context.Background(), Message{Token: "x", Title: "t", Body: "b"}); err != ErrTokenInvalid {
		t.Fatalf("ожидался ErrTokenInvalid, получено %v", err)
	}
}
