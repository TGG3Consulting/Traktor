// Package store — хранилище заданий.
package store

import (
	"context"
	"time"

	"traktor/orders/internal/job"
)

// Sort — порядок ленты (ТЗ §2.7: новые / ближе / дороже / скоро финиш).
type Sort string

const (
	SortNew    Sort = "new"
	SortNear   Sort = "near"
	SortPrice  Sort = "price"
	SortEnding Sort = "ending"
)

// Filter — параметры ленты исполнителя.
type Filter struct {
	// Точка отсчёта. Без неё сортировка «ближе» и радиус не применяются.
	Lat, Lng *float64
	RadiusM  *float64
	// Пустой список категорий — все категории («Мои категории ✓» клиент
	// разворачивает в конкретный список).
	CategoryIDs []string
	Mode        job.Mode // пусто — оба режима
	Query       string   // поиск по названию и описанию
	Sort        Sort
	Limit       int
	Offset      int
}

// Store — операции над заданиями.
type Store interface {
	Create(ctx context.Context, j *job.Job) error
	Update(ctx context.Context, j *job.Job) error
	ByID(ctx context.Context, id string) (*job.Job, error)
	// ListByClient — «Мои задания» заказчика: вместе с черновиками, свежие сверху.
	ListByClient(ctx context.Context, clientID string, limit, offset int) ([]job.Job, error)
	// Feed — лента исполнителя: только открытые задания.
	Feed(ctx context.Context, f Filter) ([]job.Job, error)
	// AddView отмечает просмотр и возвращает true, если он первый от этого
	// пользователя: счётчик в карточке должен показывать людей, а не обновления
	// экрана.
	AddView(ctx context.Context, jobID, viewerID string) (bool, error)

	// ── отклики (ТЗ §2.10) ───────────────────────────────────────────────────
	CreateOffer(ctx context.Context, o *job.Offer) error
	UpdateOffer(ctx context.Context, o *job.Offer) error
	OfferByID(ctx context.Context, id string) (*job.Offer, error)
	OffersByJob(ctx context.Context, jobID string) ([]job.Offer, error)
	OffersByOwner(ctx context.Context, ownerID string, limit, offset int) ([]job.Offer, error)
	// MyOfferForJob — свой отклик исполнителя: по нему экран задания понимает,
	// показывать кнопку отклика или уже отправленное предложение.
	MyOfferForJob(ctx context.Context, jobID, ownerID string) (*job.Offer, error)

	// ── сделки (ТЗ §2.11) ────────────────────────────────────────────────────
	CreateDeal(ctx context.Context, d *job.Deal) error
	UpdateDeal(ctx context.Context, d *job.Deal) error
	DealByID(ctx context.Context, id string) (*job.Deal, error)
	// DealByJob — сделка по заданию: на задание она одна.
	DealByJob(ctx context.Context, jobID string) (*job.Deal, error)
	DealsByUser(ctx context.Context, userID string, limit, offset int) ([]job.Deal, error)

	// ── CRM исполнителя (ТЗ §3.1) ────────────────────────────────────────────
	// Считаем в базе: тянуть все сделки за год на телефон ради одной суммы
	// бессмысленно.
	IncomeOf(ctx context.Context, ownerID string, from, to time.Time) (int64, int, error)
	FunnelOf(ctx context.Context, ownerID string, from, to time.Time) (job.Funnel, error)
	ClientsOf(ctx context.Context, ownerID string, from, to time.Time, limit int) ([]job.Client, error)

	// CRM заказчика (ТЗ §3.2).
	SpendingOf(ctx context.Context, clientID string, from, to time.Time) (int64, int, error)
	SpendingByCategory(ctx context.Context, clientID string, from, to time.Time) ([]job.CategorySpend, error)
	OwnersOf(ctx context.Context, clientID string, from, to time.Time, limit int) ([]job.Client, error)
	// SavedOnAuctions — разница между стартовой и итоговой ценой по аукционам.
	SavedOnAuctions(ctx context.Context, clientID string, from, to time.Time) (int64, error)

	// ── ставки аукциона (ТЗ §2.9) ────────────────────────────────────────────
	CreateBid(ctx context.Context, b *job.Bid) error
	UpdateBid(ctx context.Context, b *job.Bid) error
	BidByID(ctx context.Context, id string) (*job.Bid, error)
	BidsByJob(ctx context.Context, jobID string) ([]job.Bid, error)
	BidsByOwner(ctx context.Context, ownerID string, limit, offset int) ([]job.Bid, error)
	// BestBid — текущая лучшая (самая низкая) действующая ставка.
	BestBid(ctx context.Context, jobID string) (*job.Bid, error)
	MyBidForJob(ctx context.Context, jobID, ownerID string) (*job.Bid, error)

	// ── чаты (ТЗ §2.12) ──────────────────────────────────────────────────────
	CreateChat(ctx context.Context, c *job.Chat) error
	UpdateChat(ctx context.Context, c *job.Chat) error
	ChatByID(ctx context.Context, id string) (*job.Chat, error)
	// ChatByJobOwner — чат по паре «задание + исполнитель»: он всегда один.
	ChatByJobOwner(ctx context.Context, jobID, ownerID string) (*job.Chat, error)
	ChatsByUser(ctx context.Context, userID string, limit, offset int) ([]job.Chat, error)
	CreateMessage(ctx context.Context, m *job.Message) error
	Messages(ctx context.Context, chatID string, limit, offset int) ([]job.Message, error)
	MarkRead(ctx context.Context, chatID, userID string) error

	// Оценки и отзывы (ТЗ §2.13).
	CreateReview(ctx context.Context, r *job.Review) error
	UpdateReview(ctx context.Context, r *job.Review) error
	ReviewByID(ctx context.Context, id string) (*job.Review, error)
	// Обе оценки по сделке: по ним решается, пора ли публиковать.
	ReviewsByDeal(ctx context.Context, dealID string) ([]job.Review, error)
	ReviewsAbout(ctx context.Context, userID string, limit, offset int) ([]job.Review, error)
	ReviewsByAuthor(ctx context.Context, userID string, limit, offset int) ([]job.Review, error)
	RatingOf(ctx context.Context, userID string, since time.Time) (job.RatingSummary, error)
	// Одинокие оценки, ждущие дольше недели: их пора открыть.
	DueReviews(ctx context.Context, before time.Time) ([]job.Review, error)

	// DueJobs — задания, у которых истёк срок: финиш аукциона, окно решения
	// заказчика или срок приёмки работы. По ним работает фоновый обработчик.
	DueJobs(ctx context.Context, now time.Time) ([]job.Job, error)

	// Идемпотентность мутаций: повтор запроса с тем же ключом возвращает
	// прежнее задание, а не создаёт новое (§2.3.12).
	FindIdempotent(ctx context.Context, key, userID, endpoint string) (string, bool, error)
	SaveIdempotent(ctx context.Context, key, userID, endpoint, jobID string) error
}
