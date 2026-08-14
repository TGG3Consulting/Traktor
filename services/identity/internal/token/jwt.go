// Package token — выпуск и проверка JWT ES256 (ECDSA P-256 + SHA-256) на
// стандартной библиотеке, без внешних зависимостей. Access-токен короткий
// (15 мин), проверяется всеми сервисами локально по публичному ключу (JWKS).
package token

import (
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math/big"
	"strings"
	"time"
)

var (
	ErrMalformed = errors.New("token: malformed")
	ErrSignature = errors.New("token: bad signature")
	ErrExpired   = errors.New("token: expired")
)

// Claims — полезная нагрузка access-токена.
type Claims struct {
	Sub        string   `json:"sub"`
	Roles      []string `json:"roles"`
	ActiveRole string   `json:"activeRole"`
	Typ        string   `json:"typ"` // "access"
	Iat        int64    `json:"iat"`
	Exp        int64    `json:"exp"`
}

type Signer struct {
	priv *ecdsa.PrivateKey
	kid  string
}

func NewSigner(priv *ecdsa.PrivateKey, kid string) *Signer { return &Signer{priv: priv, kid: kid} }

func b64(b []byte) string           { return base64.RawURLEncoding.EncodeToString(b) }
func ub64(s string) ([]byte, error) { return base64.RawURLEncoding.DecodeString(s) }

// Sign выпускает подписанный компактный JWT.
func (s *Signer) Sign(c Claims) (string, error) {
	header := map[string]string{"alg": "ES256", "typ": "JWT", "kid": s.kid}
	hb, _ := json.Marshal(header)
	pb, err := json.Marshal(c)
	if err != nil {
		return "", err
	}
	signingInput := b64(hb) + "." + b64(pb)
	h := sha256.Sum256([]byte(signingInput))
	r, ss, err := ecdsa.Sign(rand.Reader, s.priv, h[:])
	if err != nil {
		return "", err
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	ss.FillBytes(sig[32:])
	return signingInput + "." + b64(sig), nil
}

// Parse проверяет подпись публичным ключом и срок действия, возвращает Claims.
func Parse(tok string, pub *ecdsa.PublicKey, now time.Time) (*Claims, error) {
	parts := strings.Split(tok, ".")
	if len(parts) != 3 {
		return nil, ErrMalformed
	}
	signingInput := parts[0] + "." + parts[1]
	sig, err := ub64(parts[2])
	if err != nil || len(sig) != 64 {
		return nil, ErrMalformed
	}
	h := sha256.Sum256([]byte(signingInput))
	r := new(big.Int).SetBytes(sig[:32])
	ss := new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(pub, h[:], r, ss) {
		return nil, ErrSignature
	}
	pb, err := ub64(parts[1])
	if err != nil {
		return nil, ErrMalformed
	}
	var c Claims
	if err := json.Unmarshal(pb, &c); err != nil {
		return nil, ErrMalformed
	}
	if now.Unix() >= c.Exp {
		return nil, ErrExpired
	}
	return &c, nil
}
