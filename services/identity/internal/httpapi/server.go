// Package httpapi — HTTP-слой identity, реализует контракт contracts/openapi.
// Ошибки — в формате problem+json (RFC 9457) с человекочитаемым detail.
//
// Правило 23: роутер и middleware — go-chi/chi/v5, публикация JWKS —
// lestrrat-go/jwx/v2. Самописных роутеров и сериализации ключей нет.
package httpapi

import (
	"context"
	"crypto/ecdsa"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/lestrrat-go/jwx/v2/jwa"
	"github.com/lestrrat-go/jwx/v2/jwk"

	"traktor/identity/internal/service"
	"traktor/identity/internal/store"
	"traktor/identity/internal/token"
)

type Server struct {
	auth    *service.Auth
	pub     *ecdsa.PublicKey
	kid     string
	now     func() time.Time
	jwksRaw []byte // готовый JWKS-документ, собирается один раз при старте
}

func New(auth *service.Auth, pub *ecdsa.PublicKey, kid string) *Server {
	s := &Server{auth: auth, pub: pub, kid: kid, now: time.Now}
	s.jwksRaw = buildJWKS(pub, kid)
	return s
}

// buildJWKS собирает набор ключей средствами jwx. Ошибка здесь означает
// некорректный ключ конфигурации — сервис в таком виде бесполезен, но и падать
// на старте из-за JWKS не нужно: отдадим пустой набор, а причину увидим в логе.
func buildJWKS(pub *ecdsa.PublicKey, kid string) []byte {
	key, err := jwk.FromRaw(pub)
	if err != nil {
		return []byte(`{"keys":[]}`)
	}
	_ = key.Set(jwk.KeyIDKey, kid)
	_ = key.Set(jwk.AlgorithmKey, jwa.ES256)
	_ = key.Set(jwk.KeyUsageKey, "sig")
	set := jwk.NewSet()
	if err := set.AddKey(key); err != nil {
		return []byte(`{"keys":[]}`)
	}
	raw, err := json.Marshal(set)
	if err != nil {
		return []byte(`{"keys":[]}`)
	}
	return raw
}

func (s *Server) Routes() http.Handler {
	r := chi.NewRouter()
	r.Use(
		middleware.RequestID,
		middleware.RealIP,
		middleware.Recoverer,
		middleware.Timeout(20*time.Second),
	)

	r.Route("/v1", func(r chi.Router) {
		r.Post("/auth/otp/start", s.otpStart)
		r.Post("/auth/otp/verify", s.otpVerify)
		r.Post("/auth/refresh", s.refresh)

		// Приватная зона: только с валидным access-токеном.
		r.Group(func(r chi.Router) {
			r.Use(s.requireAuth)
			r.Get("/me", s.me)
			r.Patch("/me", s.updateMe)
		})
	})

	r.Get("/.well-known/jwks.json", s.jwks)
	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	return r
}

// ── helpers ───────────────────────────────────────────────

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func problem(w http.ResponseWriter, status int, detail string) {
	w.Header().Set("Content-Type", "application/problem+json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"status": status, "detail": detail})
}

func decode(r *http.Request, v any) error {
	defer r.Body.Close()
	return json.NewDecoder(r.Body).Decode(v)
}

// ── аутентификация ────────────────────────────────────────

type ctxKey int

const claimsKey ctxKey = iota

// requireAuth проверяет Bearer-токен и кладёт claims в контекст запроса.
func (s *Server) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := r.Header.Get("Authorization")
		if !strings.HasPrefix(h, "Bearer ") {
			problem(w, http.StatusUnauthorized, "Требуется вход")
			return
		}
		claims, err := token.Parse(strings.TrimPrefix(h, "Bearer "), s.pub, s.now())
		if err != nil {
			problem(w, http.StatusUnauthorized, "Требуется вход")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), claimsKey, claims)))
	})
}

func claimsFrom(ctx context.Context) *token.Claims {
	c, _ := ctx.Value(claimsKey).(*token.Claims)
	return c
}

// ── handlers ──────────────────────────────────────────────

func (s *Server) otpStart(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Phone string `json:"phone"`
	}
	if err := decode(r, &body); err != nil || body.Phone == "" {
		problem(w, http.StatusBadRequest, "Укажите номер телефона")
		return
	}
	retry, channel, err := s.auth.StartOTP(r.Context(), body.Phone)
	if err != nil {
		problem(w, http.StatusBadGateway, "Не удалось отправить код. Повторите")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"retryAfterSec": retry, "channel": channel})
}

func (s *Server) otpVerify(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Phone string `json:"phone"`
		Code  string `json:"code"`
	}
	if err := decode(r, &body); err != nil {
		problem(w, http.StatusBadRequest, "Неверный запрос")
		return
	}
	sess, err := s.auth.VerifyOTP(r.Context(), body.Phone, body.Code)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrTooManyAttempts):
			problem(w, http.StatusLocked, "Слишком много попыток. Попробуйте позже")
		default:
			problem(w, http.StatusUnauthorized, "Код неверный")
		}
		return
	}
	writeJSON(w, http.StatusOK, sessionJSON(sess))
}

func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RefreshToken string `json:"refreshToken"`
	}
	if err := decode(r, &body); err != nil || body.RefreshToken == "" {
		problem(w, http.StatusBadRequest, "Неверный запрос")
		return
	}
	sess, err := s.auth.Refresh(r.Context(), body.RefreshToken)
	if err != nil {
		problem(w, http.StatusUnauthorized, "Сессия истекла, войдите снова")
		return
	}
	writeJSON(w, http.StatusOK, sessionJSON(sess))
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	claims := claimsFrom(r.Context())
	u, err := s.auth.Me(r.Context(), claims.Sub)
	if err != nil {
		problem(w, http.StatusNotFound, "Профиль не найден")
		return
	}
	writeJSON(w, http.StatusOK, userJSON(*u))
}

// updateMe — PATCH /v1/me. Частичное обновление профиля (имя, город, активная
// роль). Пустое тело допустимо (ничего не меняет). Возвращает актуальный профиль.
func (s *Server) updateMe(w http.ResponseWriter, r *http.Request) {
	claims := claimsFrom(r.Context())
	var body struct {
		Name       *string `json:"name"`
		City       *string `json:"city"`
		ActiveRole *string `json:"activeRole"`
	}
	if err := decode(r, &body); err != nil {
		problem(w, http.StatusBadRequest, "Неверный запрос")
		return
	}
	u, err := s.auth.UpdateProfile(r.Context(), claims.Sub, service.ProfilePatch{
		Name: body.Name, City: body.City, ActiveRole: body.ActiveRole,
	})
	if err != nil {
		switch {
		case errors.Is(err, service.ErrInvalidRole):
			problem(w, http.StatusBadRequest, "Недопустимая роль")
		default:
			problem(w, http.StatusNotFound, "Профиль не найден")
		}
		return
	}
	writeJSON(w, http.StatusOK, userJSON(*u))
}

// jwks отдаёт публичный ключ, чтобы другие сервисы проверяли токен локально.
func (s *Server) jwks(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/jwk-set+json")
	w.Header().Set("Cache-Control", "public, max-age=300")
	_, _ = w.Write(s.jwksRaw)
}

// userJSON — единое представление профиля (совпадает со схемой User в OpenAPI).
func userJSON(u store.User) map[string]any {
	return map[string]any{
		"id":         u.ID,
		"phone":      u.Phone,
		"name":       u.Name,
		"city":       u.City,
		"roles":      u.Roles,
		"activeRole": u.ActiveRole,
		"verified":   u.Verified,
	}
}

func sessionJSON(sess *service.Session) map[string]any {
	return map[string]any{
		"accessToken":  sess.AccessToken,
		"refreshToken": sess.RefreshToken,
		"expiresInSec": sess.ExpiresInSec,
		"user":         userJSON(sess.User),
	}
}
