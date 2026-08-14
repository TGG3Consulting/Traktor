package proxy

import (
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRouterLongestPrefixWins(t *testing.T) {
	identity := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("identity"))
	}))
	defer identity.Close()
	other := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("other"))
	}))
	defer other.Close()

	h, err := Router([]Route{
		{Prefix: "/v1/", Upstream: other.URL},
		{Prefix: "/v1/auth/", Upstream: identity.URL},
	})
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(h)
	defer ts.Close()

	// /v1/auth/... → identity (более длинный префикс).
	resp, _ := http.Get(ts.URL + "/v1/auth/otp/start")
	b, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if string(b) != "identity" {
		t.Fatalf("ожидали identity, получили %q", b)
	}

	// /v1/jobs → other.
	resp, _ = http.Get(ts.URL + "/v1/jobs")
	b, _ = io.ReadAll(resp.Body)
	resp.Body.Close()
	if string(b) != "other" {
		t.Fatalf("ожидали other, получили %q", b)
	}
}
