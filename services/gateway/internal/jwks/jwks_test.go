package jwks

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// подписываем тестовый токен тем же способом, что и identity (ES256).
func sign(t *testing.T, priv *ecdsa.PrivateKey, kid string, claims Claims) string {
	t.Helper()
	hb, _ := json.Marshal(map[string]string{"alg": "ES256", "typ": "JWT", "kid": kid})
	pb, _ := json.Marshal(claims)
	si := base64.RawURLEncoding.EncodeToString(hb) + "." + base64.RawURLEncoding.EncodeToString(pb)
	h := sha256.Sum256([]byte(si))
	r, s, _ := ecdsa.Sign(rand.Reader, priv, h[:])
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return si + "." + base64.RawURLEncoding.EncodeToString(sig)
}

func jwksServer(t *testing.T, pub *ecdsa.PublicKey, kid string) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"keys": []map[string]any{{
			"kty": "EC", "crv": "P-256", "alg": "ES256", "kid": kid,
			"x": base64.RawURLEncoding.EncodeToString(pub.X.Bytes()),
			"y": base64.RawURLEncoding.EncodeToString(pub.Y.Bytes()),
		}}})
	}))
}

func TestVerifyValidAndInvalid(t *testing.T) {
	priv, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	ts := jwksServer(t, &priv.PublicKey, "k1")
	defer ts.Close()
	cache := New(ts.URL)
	ctx := context.Background()
	now := time.Now()

	valid := sign(t, priv, "k1", Claims{Sub: "u1", ActiveRole: "client", Exp: now.Add(time.Minute).Unix()})
	cl, err := cache.Verify(ctx, valid, now)
	if err != nil || cl.Sub != "u1" {
		t.Fatalf("валидный токен должен пройти: %v %+v", err, cl)
	}

	// Истёкший токен.
	expired := sign(t, priv, "k1", Claims{Sub: "u1", Exp: now.Add(-time.Minute).Unix()})
	if _, err := cache.Verify(ctx, expired, now); err != ErrExpired {
		t.Fatalf("истёкший должен дать ErrExpired, получили %v", err)
	}

	// Токен, подписанный ЧУЖИМ ключом.
	other, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	forged := sign(t, other, "k1", Claims{Sub: "hacker", Exp: now.Add(time.Minute).Unix()})
	if _, err := cache.Verify(ctx, forged, now); err != ErrSignature {
		t.Fatalf("чужая подпись должна дать ErrSignature, получили %v", err)
	}

	// Неизвестный kid.
	unknown := sign(t, priv, "k2", Claims{Sub: "u1", Exp: now.Add(time.Minute).Unix()})
	if _, err := cache.Verify(ctx, unknown, now); err == nil {
		t.Fatal("неизвестный kid должен отклоняться")
	}
}
