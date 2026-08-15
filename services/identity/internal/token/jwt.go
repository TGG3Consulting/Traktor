// Package token — выпуск и проверка access-токенов (JWT ES256, ECDSA P-256).
//
// Правило 23: криптография и разбор JWT — только зрелая библиотека
// github.com/golang-jwt/jwt/v5. Своих реализаций подписи здесь нет.
//
// Формат полезной нагрузки не изменился (sub / iat / exp / roles / activeRole /
// typ), поэтому уже выпущенные токены и клиенты остаются совместимыми.
package token

import (
	"crypto/ecdsa"
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var (
	ErrMalformed = errors.New("token: malformed")
	ErrSignature = errors.New("token: bad signature")
	ErrExpired   = errors.New("token: expired")
)

// Alg — единственный разрешённый алгоритм подписи. Явный список защищает от
// подмены алгоритма (alg=none / HS256 с публичным ключом).
const Alg = "ES256"

// Claims — полезная нагрузка access-токена в терминах предметной области.
type Claims struct {
	Sub        string   `json:"sub"`
	Roles      []string `json:"roles"`
	ActiveRole string   `json:"activeRole"`
	// Status — active или frozen. Заморозка запрещает отклики и ставки, но
	// оставляет вход и переписку: человеку нужно закрыть текущие сделки
	// (ТЗ §4.1, п.3). Забаненному токен не выдаётся вовсе.
	Status string `json:"status,omitempty"`
	Typ    string `json:"typ"` // "access"
	Iat    int64  `json:"iat"`
	Exp    int64  `json:"exp"`
}

// wire — представление тех же данных для golang-jwt.
type wire struct {
	Roles      []string `json:"roles,omitempty"`
	ActiveRole string   `json:"activeRole,omitempty"`
	Status     string   `json:"status,omitempty"`
	Typ        string   `json:"typ,omitempty"`
	jwt.RegisteredClaims
}

type Signer struct {
	priv *ecdsa.PrivateKey
	kid  string
}

func NewSigner(priv *ecdsa.PrivateKey, kid string) *Signer { return &Signer{priv: priv, kid: kid} }

// Sign выпускает подписанный компактный JWT с заголовком kid (по нему
// потребитель выбирает ключ из JWKS).
func (s *Signer) Sign(c Claims) (string, error) {
	claims := wire{
		Roles:      c.Roles,
		ActiveRole: c.ActiveRole,
		Status:     c.Status,
		Typ:        c.Typ,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   c.Sub,
			IssuedAt:  jwt.NewNumericDate(time.Unix(c.Iat, 0)),
			ExpiresAt: jwt.NewNumericDate(time.Unix(c.Exp, 0)),
		},
	}
	t := jwt.NewWithClaims(jwt.SigningMethodES256, claims)
	t.Header["kid"] = s.kid
	return t.SignedString(s.priv)
}

// Parse проверяет подпись публичным ключом и срок действия на момент now.
func Parse(tok string, pub *ecdsa.PublicKey, now time.Time) (*Claims, error) {
	parser := jwt.NewParser(
		jwt.WithValidMethods([]string{Alg}),
		jwt.WithExpirationRequired(),
		jwt.WithTimeFunc(func() time.Time { return now }),
	)
	var w wire
	if _, err := parser.ParseWithClaims(tok, &w, func(*jwt.Token) (any, error) { return pub, nil }); err != nil {
		switch {
		case errors.Is(err, jwt.ErrTokenExpired), errors.Is(err, jwt.ErrTokenNotValidYet):
			return nil, ErrExpired
		case errors.Is(err, jwt.ErrTokenSignatureInvalid):
			return nil, ErrSignature
		default:
			return nil, ErrMalformed
		}
	}
	c := &Claims{
		Sub:        w.Subject,
		Roles:      w.Roles,
		ActiveRole: w.ActiveRole,
		Status:     w.Status,
		Typ:        w.Typ,
	}
	if w.IssuedAt != nil {
		c.Iat = w.IssuedAt.Unix()
	}
	if w.ExpiresAt != nil {
		c.Exp = w.ExpiresAt.Unix()
	}
	return c, nil
}
