package httpapi

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"traktor/identity/internal/service"
	"traktor/identity/internal/sms"
	"traktor/identity/internal/store"
	"traktor/identity/internal/token"
)

func setup(t *testing.T) (*httptest.Server, *sms.Fake) {
	t.Helper()
	priv, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	fake := sms.NewFake()
	auth := service.NewAuth(store.NewMemory(), fake, token.NewSigner(priv, "test"), time.Now)
	srv := New(auth, &priv.PublicKey, "test")
	return httptest.NewServer(srv.Routes()), fake
}

func postJSON(t *testing.T, url string, body any, headers map[string]string) (*http.Response, map[string]any) {
	t.Helper()
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, url, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	data, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	var m map[string]any
	if len(data) > 0 {
		_ = json.Unmarshal(data, &m)
	}
	return resp, m
}

func TestFullHTTPFlow(t *testing.T) {
	ts, fake := setup(t)
	defer ts.Close()
	const phone = "+37491234567"

	// 1. otp/start
	resp, out := postJSON(t, ts.URL+"/v1/auth/otp/start", map[string]string{"phone": phone}, nil)
	if resp.StatusCode != 200 || out["channel"] != "fake" {
		t.Fatalf("otp/start: %d %v", resp.StatusCode, out)
	}
	code := fake.Last(phone)

	// 2. verify неверным кодом → 401
	resp, _ = postJSON(t, ts.URL+"/v1/auth/otp/verify",
		map[string]string{"phone": phone, "code": "000000"}, map[string]string{"Idempotency-Key": "k1"})
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("ожидали 401 на неверный код, получили %d", resp.StatusCode)
	}

	// 3. verify верным кодом → сессия
	resp, out = postJSON(t, ts.URL+"/v1/auth/otp/verify",
		map[string]string{"phone": phone, "code": code}, map[string]string{"Idempotency-Key": "k2"})
	if resp.StatusCode != 200 {
		t.Fatalf("verify: %d %v", resp.StatusCode, out)
	}
	access, _ := out["accessToken"].(string)
	refresh, _ := out["refreshToken"].(string)
	if access == "" || refresh == "" {
		t.Fatalf("пустые токены: %v", out)
	}

	// 4. /me с Bearer → профиль
	req, _ := http.NewRequest(http.MethodGet, ts.URL+"/v1/me", nil)
	req.Header.Set("Authorization", "Bearer "+access)
	meResp, _ := http.DefaultClient.Do(req)
	if meResp.StatusCode != 200 {
		t.Fatalf("/me: %d", meResp.StatusCode)
	}
	meResp.Body.Close()

	// 5. /me без токена → 401
	noAuth, _ := http.Get(ts.URL + "/v1/me")
	if noAuth.StatusCode != http.StatusUnauthorized {
		t.Fatalf("/me без токена: ожидали 401, получили %d", noAuth.StatusCode)
	}
	noAuth.Body.Close()

	// 6. refresh → новая пара
	resp, out = postJSON(t, ts.URL+"/v1/auth/refresh", map[string]string{"refreshToken": refresh}, nil)
	if resp.StatusCode != 200 || out["accessToken"] == "" {
		t.Fatalf("refresh: %d %v", resp.StatusCode, out)
	}
}

func TestUpdateMe(t *testing.T) {
	ts, fake := setup(t)
	defer ts.Close()
	const phone = "+37491888999"

	postJSON(t, ts.URL+"/v1/auth/otp/start", map[string]string{"phone": phone}, nil)
	_, out := postJSON(t, ts.URL+"/v1/auth/otp/verify",
		map[string]string{"phone": phone, "code": fake.Last(phone)}, map[string]string{"Idempotency-Key": "k"})
	access, _ := out["accessToken"].(string)
	if access == "" {
		t.Fatal("нет токена")
	}

	// PATCH /me: имя + активная роль owner.
	body, _ := json.Marshal(map[string]any{"name": "Тигран", "activeRole": "owner"})
	req, _ := http.NewRequest(http.MethodPatch, ts.URL+"/v1/me", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+access)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	data, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("PATCH /me: %d %s", resp.StatusCode, string(data))
	}
	var patched map[string]any
	_ = json.Unmarshal(data, &patched)
	if patched["name"] != "Тигран" || patched["activeRole"] != "owner" || patched["verified"] != true {
		t.Fatalf("профиль не обновился: %v", patched)
	}

	// GET /me отдаёт обновлённый профиль.
	greq, _ := http.NewRequest(http.MethodGet, ts.URL+"/v1/me", nil)
	greq.Header.Set("Authorization", "Bearer "+access)
	gresp, _ := http.DefaultClient.Do(greq)
	gdata, _ := io.ReadAll(gresp.Body)
	gresp.Body.Close()
	var me map[string]any
	_ = json.Unmarshal(gdata, &me)
	if me["name"] != "Тигран" || me["activeRole"] != "owner" {
		t.Fatalf("/me не отражает обновление: %v", me)
	}

	// PATCH без токена → 401.
	nreq, _ := http.NewRequest(http.MethodPatch, ts.URL+"/v1/me", bytes.NewReader([]byte("{}")))
	nreq.Header.Set("Content-Type", "application/json")
	nresp, _ := http.DefaultClient.Do(nreq)
	if nresp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("PATCH без токена: ждали 401, получили %d", nresp.StatusCode)
	}
	nresp.Body.Close()
}
