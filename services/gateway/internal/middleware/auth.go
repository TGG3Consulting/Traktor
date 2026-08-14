// Package middleware — сквозные слои шлюза: авторизация, лимиты, идемпотентность.
package middleware

import (
	"context"
	"net/http"
	"strings"
	"time"

	"traktor/gateway/internal/jwks"
)

type ctxKey int

const claimsKey ctxKey = 0

// ClaimsFrom достаёт проверенные claims из контекста запроса.
func ClaimsFrom(ctx context.Context) (*jwks.Claims, bool) {
	c, ok := ctx.Value(claimsKey).(*jwks.Claims)
	return c, ok
}

// Auth требует валидный Bearer-токен. Публичные пути (передаются в public)
// пропускаются без проверки (эндпоинты входа, health, jwks, гостевая лента).
//
// На публичных путях токен всё равно разбирается, если он есть: гостевая лента
// и деталка задания работают без входа, но вошедшему исполнителю сервис должен
// знать, кто смотрит — иначе просмотры считаются как гостевые, а владелец не
// увидит свою резервную цену.
func Auth(cache *jwks.Cache, public func(path string) bool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Кто пользователь — решает только шлюз. Заголовки из внешнего
			// запроса стираем, иначе их можно было бы подделать и прочитать
			// чужие данные на публичном маршруте.
			r.Header.Del("X-User-Id")
			r.Header.Del("X-User-Role")

			if public(r.URL.Path) {
				if token, ok := bearer(r); ok {
					if claims, err := cache.Verify(r.Context(), token, time.Now()); err == nil {
						r.Header.Set("X-User-Id", claims.Sub)
						r.Header.Set("X-User-Role", claims.ActiveRole)
						next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), claimsKey, claims)))
						return
					}
				}
				next.ServeHTTP(w, r)
				return
			}
			h := r.Header.Get("Authorization")
			if !strings.HasPrefix(h, "Bearer ") {
				problem(w, http.StatusUnauthorized, "Требуется вход")
				return
			}
			claims, err := cache.Verify(r.Context(), strings.TrimPrefix(h, "Bearer "), time.Now())
			if err != nil {
				problem(w, http.StatusUnauthorized, "Сессия недействительна, войдите снова")
				return
			}
			ctx := context.WithValue(r.Context(), claimsKey, claims)
			// Прокидываем проверенный идентификатор пользователя вниз по стеку.
			r.Header.Set("X-User-Id", claims.Sub)
			r.Header.Set("X-User-Role", claims.ActiveRole)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// bearer достаёт токен из заголовка Authorization.
func bearer(r *http.Request) (string, bool) {
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return "", false
	}
	return strings.TrimPrefix(h, "Bearer "), true
}
