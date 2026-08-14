// Package httpapi — HTTP-слой identity, реализует контракт contracts/openapi.
// Ошибки — в формате problem+json (RFC 9457) с человекочитаемым detail.
package httpapi

import (
	"crypto/ecdsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"traktor/identity/internal/service"
	"traktor/identity/internal/token"
)

type Server struct {
	auth *service.Auth
	pub  *ecdsa.PublicKey
	kid  string
	now  func() time.Time
}

func New(auth *service.Auth, pub *ecdsa.PublicKey, kid string) *Server {
	return &Server{auth: auth, pub: pub, kid: kid, now: time.Now}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/auth/otp/start", s.otpStart)
	mux.HandleFunc("POST /v1/auth/otp/verify", s.otpVerify)
	mux.HandleFunc("POST /v1/auth/refresh", s.refresh)
	mux.HandleFunc("GET /v1/me", s.me)
	mux.HandleFunc("GET /.well-known/jwks.json", s.jwks)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) })
	return mux
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
	writeJSON(w, 200, map[string]any{"retryAfterSec": retry, "channel": channel})
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
	writeJSON(w, 200, sessionJSON(sess))
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
	writeJSON(w, 200, sessionJSON(sess))
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	claims, err := s.bearer(r)
	if err != nil {
		problem(w, http.StatusUnauthorized, "Требуется вход")
		return
	}
	writeJSON(w, 200, map[string]any{
		"id":         claims.Sub,
		"roles":      claims.Roles,
		"activeRole": claims.ActiveRole,
	})
}

func (s *Server) bearer(r *http.Request) (*token.Claims, error) {
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return nil, errors.New("no bearer")
	}
	return token.Parse(strings.TrimPrefix(h, "Bearer "), s.pub, s.now())
}

// jwks отдаёт публичный ключ, чтобы другие сервисы проверяли токен локально.
func (s *Server) jwks(w http.ResponseWriter, _ *http.Request) {
	x := base64.RawURLEncoding.EncodeToString(s.pub.X.Bytes())
	y := base64.RawURLEncoding.EncodeToString(s.pub.Y.Bytes())
	writeJSON(w, 200, map[string]any{
		"keys": []map[string]any{{
			"kty": "EC", "crv": "P-256", "use": "sig", "alg": "ES256",
			"kid": s.kid, "x": x, "y": y,
		}},
	})
}

func sessionJSON(sess *service.Session) map[string]any {
	return map[string]any{
		"accessToken":  sess.AccessToken,
		"refreshToken": sess.RefreshToken,
		"expiresInSec": sess.ExpiresInSec,
		"user": map[string]any{
			"id":         sess.User.ID,
			"phone":      sess.User.Phone,
			"name":       sess.User.Name,
			"roles":      sess.User.Roles,
			"activeRole": sess.User.ActiveRole,
			"verified":   sess.User.Verified,
		},
	}
}
