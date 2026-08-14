package jwks

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/lestrrat-go/jwx/v2/jwa"
	"github.com/lestrrat-go/jwx/v2/jwk"
)

// sign выпускает токен ровно так же, как это делает identity (golang-jwt, ES256).
func sign(t *testing.T, priv *ecdsa.PrivateKey, kid string, c Claims) string {
	t.Helper()
	claims := wire{
		Roles:      c.Roles,
		ActiveRole: c.ActiveRole,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   c.Sub,
			ExpiresAt: jwt.NewNumericDate(time.Unix(c.Exp, 0)),
		},
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodES256, claims)
	tok.Header["kid"] = kid
	s, err := tok.SignedString(priv)
	if err != nil {
		t.Fatalf("подпись тестового токена: %v", err)
	}
	return s
}

// jwksServer поднимает эндпоинт JWKS, как у identity.
func jwksServer(t *testing.T, pub *ecdsa.PublicKey, kid string) *httptest.Server {
	t.Helper()
	key, err := jwk.FromRaw(pub)
	if err != nil {
		t.Fatal(err)
	}
	_ = key.Set(jwk.KeyIDKey, kid)
	_ = key.Set(jwk.AlgorithmKey, jwa.ES256)
	_ = key.Set(jwk.KeyUsageKey, "sig")
	set := jwk.NewSet()
	if err := set.AddKey(key); err != nil {
		t.Fatal(err)
	}
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/jwk-set+json")
		_ = json.NewEncoder(w).Encode(set)
	}))
}

func TestVerifyValidAndInvalid(t *testing.T) {
	priv, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	ts := jwksServer(t, &priv.PublicKey, "k1")
	defer ts.Close()
	cache, err := New(ts.URL)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	now := time.Now()

	valid := sign(t, priv, "k1", Claims{Sub: "u1", ActiveRole: "client", Exp: now.Add(time.Minute).Unix()})
	cl, err := cache.Verify(ctx, valid, now)
	if err != nil || cl.Sub != "u1" || cl.ActiveRole != "client" {
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
	if _, err := cache.Verify(ctx, unknown, now); err != ErrNoKey {
		t.Fatalf("неизвестный kid должен дать ErrNoKey, получили %v", err)
	}

	// Мусор вместо токена.
	if _, err := cache.Verify(ctx, "не-токен", now); err != ErrMalformed {
		t.Fatalf("мусор должен дать ErrMalformed, получили %v", err)
	}
}

// Токен, подписанный симметричным ключом с alg=HS256, не должен приниматься,
// даже если злоумышленник подставит в качестве секрета публичный ключ.
func TestRejectsAlgSubstitution(t *testing.T) {
	priv, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	ts := jwksServer(t, &priv.PublicKey, "k1")
	defer ts.Close()
	cache, err := New(ts.URL)
	if err != nil {
		t.Fatal(err)
	}

	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{
		Subject:   "hacker",
		ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Minute)),
	})
	tok.Header["kid"] = "k1"
	forged, ferr := tok.SignedString([]byte("любой-секрет"))
	if ferr != nil {
		t.Fatal(ferr)
	}
	if _, err := cache.Verify(context.Background(), forged, time.Now()); err == nil {
		t.Fatal("токен с подменённым алгоритмом должен отклоняться")
	}
}
