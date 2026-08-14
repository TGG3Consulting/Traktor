module traktor/identity

go 1.25.0

// Зависимости добавляются `go mod tidy` (правило 23 — только зрелые библиотеки):
//   github.com/golang-jwt/jwt/v5      — выпуск и проверка JWT ES256
//   github.com/lestrrat-go/jwx/v2     — JWKS (публикация публичного ключа)
//   github.com/go-chi/chi/v5          — роутер и middleware
//   github.com/jackc/pgx/v5           — Postgres
//   github.com/golang-migrate/migrate/v4 — миграции схемы
//   github.com/google/uuid            — идентификаторы (uuid в БД)

require (
	github.com/go-chi/chi/v5 v5.3.1
	github.com/golang-jwt/jwt/v5 v5.3.1
	github.com/golang-migrate/migrate/v4 v4.19.1
	github.com/google/uuid v1.6.0
	github.com/jackc/pgx/v5 v5.10.0
	github.com/lestrrat-go/jwx/v2 v2.1.7
)

require (
	github.com/decred/dcrd/dcrec/secp256k1/v4 v4.4.1 // indirect
	github.com/goccy/go-json v0.10.6 // indirect
	github.com/jackc/pgerrcode v0.0.0-20220416144525-469b46aa5efa // indirect
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	github.com/jackc/puddle/v2 v2.2.2 // indirect
	github.com/lestrrat-go/blackmagic v1.0.4 // indirect
	github.com/lestrrat-go/httpcc v1.0.1 // indirect
	github.com/lestrrat-go/httprc v1.0.6 // indirect
	github.com/lestrrat-go/iter v1.0.2 // indirect
	github.com/lestrrat-go/option v1.0.1 // indirect
	github.com/segmentio/asm v1.2.1 // indirect
	golang.org/x/crypto v0.53.0 // indirect
	golang.org/x/sync v0.21.0 // indirect
	golang.org/x/sys v0.46.0 // indirect
	golang.org/x/text v0.38.0 // indirect
)
