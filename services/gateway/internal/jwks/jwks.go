// Package jwks — загрузка публичных ключей identity (JWKS) с кэшем и проверка
// access-токенов ES256 локально, без похода в identity на каждый запрос.
package jwks

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"
)

var (
	ErrMalformed = errors.New("jwks: malformed token")
	ErrSignature = errors.New("jwks: bad signature")
	ErrExpired   = errors.New("jwks: token expired")
	ErrNoKey     = errors.New("jwks: key not found")
)

// Claims — минимальный набор для авторизации на шлюзе.
type Claims struct {
	Sub        string   `json:"sub"`
	Roles      []string `json:"roles"`
	ActiveRole string   `json:"activeRole"`
	Exp        int64    `json:"exp"`
}

type Cache struct {
	url    string
	client *http.Client
	ttl    time.Duration

	mu        sync.RWMutex
	keys      map[string]*ecdsa.PublicKey
	fetchedAt time.Time
}

func New(url string) *Cache {
	return &Cache{
		url:    url,
		client: &http.Client{Timeout: 5 * time.Second},
		ttl:    10 * time.Minute,
		keys:   map[string]*ecdsa.PublicKey{},
	}
}

func b64d(s string) ([]byte, error) { return base64.RawURLEncoding.DecodeString(s) }

func (c *Cache) refresh(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.url, nil)
	if err != nil {
		return err
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	var doc struct {
		Keys []struct {
			Kid string `json:"kid"`
			Crv string `json:"crv"`
			X   string `json:"x"`
			Y   string `json:"y"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&doc); err != nil {
		return err
	}
	next := map[string]*ecdsa.PublicKey{}
	for _, k := range doc.Keys {
		if k.Crv != "P-256" {
			continue
		}
		xb, err1 := b64d(k.X)
		yb, err2 := b64d(k.Y)
		if err1 != nil || err2 != nil {
			continue
		}
		next[k.Kid] = &ecdsa.PublicKey{
			Curve: elliptic.P256(),
			X:     new(big.Int).SetBytes(xb),
			Y:     new(big.Int).SetBytes(yb),
		}
	}
	c.mu.Lock()
	c.keys = next
	c.fetchedAt = time.Now()
	c.mu.Unlock()
	return nil
}

func (c *Cache) key(ctx context.Context, kid string) (*ecdsa.PublicKey, error) {
	c.mu.RLock()
	k, ok := c.keys[kid]
	stale := time.Since(c.fetchedAt) > c.ttl
	c.mu.RUnlock()
	if ok && !stale {
		return k, nil
	}
	if err := c.refresh(ctx); err != nil && !ok {
		return nil, err
	}
	c.mu.RLock()
	defer c.mu.RUnlock()
	if k, ok := c.keys[kid]; ok {
		return k, nil
	}
	return nil, ErrNoKey
}

// Verify проверяет подпись и срок действия access-токена.
func (c *Cache) Verify(ctx context.Context, tok string, now time.Time) (*Claims, error) {
	parts := strings.Split(tok, ".")
	if len(parts) != 3 {
		return nil, ErrMalformed
	}
	var hdr struct {
		Alg string `json:"alg"`
		Kid string `json:"kid"`
	}
	hb, err := b64d(parts[0])
	if err != nil || json.Unmarshal(hb, &hdr) != nil || hdr.Alg != "ES256" {
		return nil, ErrMalformed
	}
	pub, err := c.key(ctx, hdr.Kid)
	if err != nil {
		return nil, err
	}
	sig, err := b64d(parts[2])
	if err != nil || len(sig) != 64 {
		return nil, ErrMalformed
	}
	h := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r := new(big.Int).SetBytes(sig[:32])
	s := new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(pub, h[:], r, s) {
		return nil, ErrSignature
	}
	pb, err := b64d(parts[1])
	if err != nil {
		return nil, ErrMalformed
	}
	var cl Claims
	if json.Unmarshal(pb, &cl) != nil {
		return nil, ErrMalformed
	}
	if now.Unix() >= cl.Exp {
		return nil, ErrExpired
	}
	return &cl, nil
}
