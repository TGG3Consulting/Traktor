// Package jwks — проверка access-токенов на шлюзе по публичным ключам
// identity, без похода в identity на каждый запрос.
//
// Правило 23: загрузка и кэш JWKS — lestrrat-go/jwx/v2 (jwk.Cache), разбор и
// проверка подписи — golang-jwt/jwt/v5. Своей криптографии здесь нет.
package jwks

import (
	"context"
	"crypto/ecdsa"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/lestrrat-go/jwx/v2/jwk"
)

var (
	ErrMalformed = errors.New("jwks: malformed token")
	ErrSignature = errors.New("jwks: bad signature")
	ErrExpired   = errors.New("jwks: token expired")
	ErrNoKey     = errors.New("jwks: key not found")
)

// alg — единственный допустимый алгоритм. Явный список закрывает атаку с
// подменой алгоритма (alg=none, HS256 на публичном ключе).
const alg = "ES256"

// Claims — минимальный набор для авторизации на шлюзе.
type Claims struct {
	Sub        string   `json:"sub"`
	Roles      []string `json:"roles"`
	ActiveRole string   `json:"activeRole"`
	Exp        int64    `json:"exp"`
}

// wire — те же данные в терминах golang-jwt (sub/exp — регистрируемые поля).
type wire struct {
	Roles      []string `json:"roles,omitempty"`
	ActiveRole string   `json:"activeRole,omitempty"`
	jwt.RegisteredClaims
}

// Cache держит JWKS в памяти и сам обновляет его в фоне.
type Cache struct {
	url   string
	cache *jwk.Cache
}

// New регистрирует URL набора ключей. Фоновое обновление живёт столько же,
// сколько процесс шлюза. Ошибку регистрации не глушим: без ключей шлюз не
// сможет проверить ни один токен, и об этом надо узнать на старте, а не в
// первом же запросе пользователя.
func New(url string) (*Cache, error) {
	c := jwk.NewCache(context.Background())
	// Только WithMinRefreshInterval: вместе с WithRefreshInterval jwx его не
	// принимает (нижняя граница и жёсткий интервал взаимоисключающи).
	if err := c.Register(url, jwk.WithMinRefreshInterval(5*time.Minute)); err != nil {
		return nil, fmt.Errorf("jwks: регистрация %s: %w", url, err)
	}
	return &Cache{url: url, cache: c}, nil
}

// keyfunc отдаёт публичный ключ по kid из заголовка токена.
func (c *Cache) keyfunc(ctx context.Context) jwt.Keyfunc {
	return func(t *jwt.Token) (any, error) {
		kid, _ := t.Header["kid"].(string)

		set, err := c.cache.Get(ctx, c.url)
		if err != nil {
			return nil, fmt.Errorf("%w: %v", ErrNoKey, err)
		}
		key, ok := set.LookupKeyID(kid)
		if !ok {
			// Ключ мог смениться только что — просим свежий набор и пробуем ещё раз.
			set, err = c.cache.Refresh(ctx, c.url)
			if err != nil {
				return nil, fmt.Errorf("%w: %v", ErrNoKey, err)
			}
			key, ok = set.LookupKeyID(kid)
			if !ok {
				return nil, ErrNoKey
			}
		}
		var pub ecdsa.PublicKey
		if err := key.Raw(&pub); err != nil {
			return nil, fmt.Errorf("%w: %v", ErrNoKey, err)
		}
		return &pub, nil
	}
}

// Verify проверяет подпись и срок действия access-токена на момент now.
func (c *Cache) Verify(ctx context.Context, tok string, now time.Time) (*Claims, error) {
	parser := jwt.NewParser(
		jwt.WithValidMethods([]string{alg}),
		jwt.WithExpirationRequired(),
		jwt.WithTimeFunc(func() time.Time { return now }),
	)
	var w wire
	if _, err := parser.ParseWithClaims(tok, &w, c.keyfunc(ctx)); err != nil {
		switch {
		case errors.Is(err, ErrNoKey):
			return nil, ErrNoKey
		case errors.Is(err, jwt.ErrTokenExpired), errors.Is(err, jwt.ErrTokenNotValidYet):
			return nil, ErrExpired
		case errors.Is(err, jwt.ErrTokenSignatureInvalid):
			return nil, ErrSignature
		default:
			return nil, ErrMalformed
		}
	}
	cl := &Claims{Sub: w.Subject, Roles: w.Roles, ActiveRole: w.ActiveRole}
	if w.ExpiresAt != nil {
		cl.Exp = w.ExpiresAt.Unix()
	}
	return cl, nil
}
