package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"traktor/orders/internal/job"
)

// Postgres — хранилище заданий на pgx + PostGIS.
type Postgres struct{ pool *pgxpool.Pool }

func NewPostgres(pool *pgxpool.Pool) *Postgres { return &Postgres{pool: pool} }

// columns перечисляет поля в фиксированном порядке — тот же порядок читает
// scanJob. Геометрия отдаётся числами: клиенту не нужен WKB.
const columns = `
  id, client_id, order_type, category_id, open_to_any, title, description,
  params, photos,
  ST_Y(geo::geometry), ST_X(geo::geometry), address, access,
  date_mode, date_start, date_end,
  budget_amount, currency, mode,
  auction_duration_h, auction_ends_at, reserve_amount, auto_extend, decision_window_h,
  workers_count, status, draft_step, views_count, offers_count, winner_bid_id,
  published_at, created_at, updated_at`

func (p *Postgres) Create(ctx context.Context, j *job.Job) error {
	params, photos, err := encodeJSON(j)
	if err != nil {
		return err
	}
	const q = `
	INSERT INTO orders.jobs (
	  id, client_id, order_type, category_id, open_to_any, title, description,
	  params, photos, geo, address, access, date_mode, date_start, date_end,
	  budget_amount, currency, mode, auction_duration_h, auction_ends_at,
	  reserve_amount, auto_extend, decision_window_h, workers_count, status,
	  draft_step, published_at, created_at, updated_at)
	VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,
	  CASE WHEN $10::float8 IS NULL THEN NULL
	       ELSE ST_SetSRID(ST_MakePoint($11::float8, $10::float8), 4326)::geography END,
	  $12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$30)`

	lat, lng := geoParts(j.Geo)
	dur, endsAt, reserve, autoExt, decision := auctionParts(j.Auction)

	_, err = p.pool.Exec(ctx, q,
		j.ID, j.ClientID, string(j.OrderType), j.CategoryID, j.OpenToAny, j.Title, j.Description,
		params, photos, lat, lng, j.Address, string(j.Access), string(j.DateMode), j.DateStart, j.DateEnd,
		j.BudgetAmount, j.Currency, string(j.Mode), dur, endsAt, reserve, autoExt, decision,
		j.WorkersCount, string(j.Status), j.DraftStep, j.PublishedAt, j.CreatedAt, j.UpdatedAt)
	if err != nil {
		return fmt.Errorf("orders: вставка задания: %w", err)
	}
	return nil
}

func (p *Postgres) Update(ctx context.Context, j *job.Job) error {
	params, photos, err := encodeJSON(j)
	if err != nil {
		return err
	}
	const q = `
	UPDATE orders.jobs SET
	  order_type=$2, category_id=$3, open_to_any=$4, title=$5, description=$6,
	  params=$7, photos=$8,
	  geo = CASE WHEN $9::float8 IS NULL THEN NULL
	             ELSE ST_SetSRID(ST_MakePoint($10::float8, $9::float8), 4326)::geography END,
	  address=$11, access=$12, date_mode=$13, date_start=$14, date_end=$15,
	  budget_amount=$16, currency=$17, mode=$18, auction_duration_h=$19,
	  auction_ends_at=$20, reserve_amount=$21, auto_extend=$22, decision_window_h=$23,
	  workers_count=$24, status=$25, draft_step=$26, winner_bid_id=$27,
	  published_at=$28, updated_at=$29
	WHERE id=$1`

	lat, lng := geoParts(j.Geo)
	dur, endsAt, reserve, autoExt, decision := auctionParts(j.Auction)

	tag, err := p.pool.Exec(ctx, q,
		j.ID, string(j.OrderType), j.CategoryID, j.OpenToAny, j.Title, j.Description,
		params, photos, lat, lng, j.Address, string(j.Access), string(j.DateMode),
		j.DateStart, j.DateEnd, j.BudgetAmount, j.Currency, string(j.Mode), dur, endsAt,
		reserve, autoExt, decision, j.WorkersCount, string(j.Status), j.DraftStep,
		j.WinnerBidID, j.PublishedAt, j.UpdatedAt)
	if err != nil {
		return fmt.Errorf("orders: обновление задания: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return job.ErrNotFound
	}
	return nil
}

func (p *Postgres) ByID(ctx context.Context, id string) (*job.Job, error) {
	rows, err := p.pool.Query(ctx, `SELECT`+columns+` FROM orders.jobs WHERE id=$1`, id)
	if err != nil {
		return nil, fmt.Errorf("orders: выборка задания: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return nil, job.ErrNotFound
	}
	return scanJob(rows)
}

func (p *Postgres) ListByClient(ctx context.Context, clientID string, limit, offset int) ([]job.Job, error) {
	q := `SELECT` + columns + `
	      FROM orders.jobs WHERE client_id=$1
	      ORDER BY updated_at DESC LIMIT $2 OFFSET $3`
	rows, err := p.pool.Query(ctx, q, clientID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("orders: список заданий заказчика: %w", err)
	}
	defer rows.Close()
	return collect(rows)
}

func (p *Postgres) Feed(ctx context.Context, f Filter) ([]job.Job, error) {
	var (
		where = []string{`status IN ('published','collecting_offers','bidding')`}
		args  []any
	)
	add := func(v any) string {
		args = append(args, v)
		return fmt.Sprintf("$%d", len(args))
	}

	// Расстояние считаем один раз и переиспользуем: в фильтре, сортировке и
	// выдаче. Без точки поиска колонка равна NULL — клиент просто не покажет км.
	distance := "NULL::float8"
	if f.Lat != nil && f.Lng != nil {
		latP, lngP := add(*f.Lat), add(*f.Lng)
		distance = fmt.Sprintf(
			"ST_Distance(geo, ST_SetSRID(ST_MakePoint(%s::float8, %s::float8),4326)::geography)", lngP, latP)
		if f.RadiusM != nil {
			// ST_DWithin бьёт по gist-индексу, в отличие от сравнения ST_Distance.
			where = append(where, fmt.Sprintf(
				"geo IS NOT NULL AND ST_DWithin(geo, ST_SetSRID(ST_MakePoint(%s::float8, %s::float8),4326)::geography, %s::float8)",
				lngP, latP, add(*f.RadiusM)))
		}
	}
	if len(f.CategoryIDs) > 0 {
		where = append(where, "category_id = ANY("+add(f.CategoryIDs)+"::uuid[])")
	}
	if f.Mode != "" {
		where = append(where, "mode = "+add(string(f.Mode)))
	}
	if text := strings.TrimSpace(f.Query); text != "" {
		// Поиск по подстроке достаточен для старта; полнотекст и Typesense —
		// отдельной задачей, когда объявлений станет много.
		pattern := add("%" + strings.ToLower(text) + "%")
		where = append(where, "(lower(title) LIKE "+pattern+" OR lower(description) LIKE "+pattern+")")
	}

	order := "published_at DESC NULLS LAST"
	switch f.Sort {
	case SortNear:
		if f.Lat != nil && f.Lng != nil {
			order = "distance_m ASC NULLS LAST"
		}
	case SortPrice:
		order = "budget_amount DESC NULLS LAST"
	case SortEnding:
		// «Скоро финиш аукциона»: сначала те, что вот-вот закроются.
		order = "auction_ends_at ASC NULLS LAST"
	}

	limit, offset := add(f.Limit), add(f.Offset)
	q := fmt.Sprintf(`SELECT %s, %s AS distance_m FROM orders.jobs WHERE %s ORDER BY %s LIMIT %s OFFSET %s`,
		strings.TrimSpace(columns), distance, strings.Join(where, " AND "), order, limit, offset)

	rows, err := p.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("orders: лента: %w", err)
	}
	defer rows.Close()
	return collectWithDistance(rows)
}

func (p *Postgres) AddView(ctx context.Context, jobID, viewerID string) (bool, error) {
	const q = `
	INSERT INTO orders.job_views (job_id, viewer_id) VALUES ($1,$2)
	ON CONFLICT DO NOTHING`
	tag, err := p.pool.Exec(ctx, q, jobID, viewerID)
	if err != nil {
		return false, fmt.Errorf("orders: отметка просмотра: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return false, nil
	}
	if _, err := p.pool.Exec(ctx,
		`UPDATE orders.jobs SET views_count = views_count + 1 WHERE id=$1`, jobID); err != nil {
		return false, fmt.Errorf("orders: счётчик просмотров: %w", err)
	}
	return true, nil
}

func (p *Postgres) FindIdempotent(ctx context.Context, key, userID, endpoint string) (string, bool, error) {
	const q = `SELECT job_id FROM orders.idempotency WHERE key=$1 AND user_id=$2 AND endpoint=$3`
	var id *string
	err := p.pool.QueryRow(ctx, q, key, userID, endpoint).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("orders: поиск ключа идемпотентности: %w", err)
	}
	if id == nil {
		return "", true, nil
	}
	return *id, true, nil
}

func (p *Postgres) SaveIdempotent(ctx context.Context, key, userID, endpoint, jobID string) error {
	const q = `
	INSERT INTO orders.idempotency (key, user_id, endpoint, job_id)
	VALUES ($1,$2,$3,$4) ON CONFLICT (key) DO NOTHING`
	if _, err := p.pool.Exec(ctx, q, key, userID, endpoint, jobID); err != nil {
		return fmt.Errorf("orders: сохранение ключа идемпотентности: %w", err)
	}
	return nil
}

// ── вспомогательное ──────────────────────────────────────────────────────────

func encodeJSON(j *job.Job) (params, photos []byte, err error) {
	if j.Params == nil {
		j.Params = map[string]any{}
	}
	if j.Photos == nil {
		j.Photos = []string{}
	}
	if params, err = json.Marshal(j.Params); err != nil {
		return nil, nil, fmt.Errorf("orders: сериализация params: %w", err)
	}
	if photos, err = json.Marshal(j.Photos); err != nil {
		return nil, nil, fmt.Errorf("orders: сериализация photos: %w", err)
	}
	return params, photos, nil
}

func geoParts(g *job.Geo) (lat, lng *float64) {
	if g == nil {
		return nil, nil
	}
	return &g.Lat, &g.Lng
}

func auctionParts(a *job.Auction) (dur *int, endsAt *time.Time, reserve *int64, autoExtend bool, decision int) {
	if a == nil {
		// Значения по умолчанию совпадают с ТЗ §2.6 шаг 4: автопродление
		// включено, окно решения 12 часов.
		return nil, nil, nil, true, 12
	}
	d := a.DurationH
	return &d, a.EndsAt, a.ReserveAmount, a.AutoExtend, a.DecisionWindowH
}

func collect(rows pgx.Rows) ([]job.Job, error) {
	out := []job.Job{}
	for rows.Next() {
		j, err := scanJob(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *j)
	}
	return out, rows.Err()
}

func collectWithDistance(rows pgx.Rows) ([]job.Job, error) {
	out := []job.Job{}
	for rows.Next() {
		j, err := scanJobWithDistance(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *j)
	}
	return out, rows.Err()
}

func scanJob(rows pgx.Rows) (*job.Job, error) { return scan(rows, false) }

func scanJobWithDistance(rows pgx.Rows) (*job.Job, error) { return scan(rows, true) }

func scan(rows pgx.Rows, withDistance bool) (*job.Job, error) {
	var (
		j        job.Job
		params   []byte
		photos   []byte
		lat, lng *float64
		distance *float64
		// Поля аукциона читаются по отдельности — из них собирается Auction.
		dur        *int
		endsAt     *time.Time
		reserve    *int64
		autoExtend bool
		decision   int
	)
	dst := []any{
		&j.ID, &j.ClientID, &j.OrderType, &j.CategoryID, &j.OpenToAny, &j.Title, &j.Description,
		&params, &photos, &lat, &lng, &j.Address, &j.Access,
		&j.DateMode, &j.DateStart, &j.DateEnd,
		&j.BudgetAmount, &j.Currency, &j.Mode,
		&dur, &endsAt, &reserve, &autoExtend, &decision,
		&j.WorkersCount, &j.Status, &j.DraftStep, &j.ViewsCount, &j.OffersCount, &j.WinnerBidID,
		&j.PublishedAt, &j.CreatedAt, &j.UpdatedAt,
	}

	if withDistance {
		dst = append(dst, &distance)
	}
	if err := rows.Scan(dst...); err != nil {
		return nil, fmt.Errorf("orders: чтение задания: %w", err)
	}

	if len(params) > 0 {
		if err := json.Unmarshal(params, &j.Params); err != nil {
			return nil, fmt.Errorf("orders: разбор params: %w", err)
		}
	}
	if j.Params == nil {
		j.Params = map[string]any{}
	}
	if len(photos) > 0 {
		if err := json.Unmarshal(photos, &j.Photos); err != nil {
			return nil, fmt.Errorf("orders: разбор photos: %w", err)
		}
	}
	if j.Photos == nil {
		j.Photos = []string{}
	}
	if lat != nil && lng != nil {
		j.Geo = &job.Geo{Lat: *lat, Lng: *lng}
	}
	// Блок аукциона отдаём только когда он реально настроен: у фикс-цены поля
	// пустые, и присылать клиенту пустой объект — вводить его в заблуждение.
	if dur != nil || reserve != nil || endsAt != nil {
		a := job.Auction{
			AutoExtend:      autoExtend,
			DecisionWindowH: decision,
			ReserveAmount:   reserve,
			EndsAt:          endsAt,
		}
		if dur != nil {
			a.DurationH = *dur
		}
		j.Auction = &a
	}
	j.DistanceM = distance
	return &j, nil
}
