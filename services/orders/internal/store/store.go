// Package store — хранилище заданий.
package store

import (
	"context"

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

	// Идемпотентность мутаций: повтор запроса с тем же ключом возвращает
	// прежнее задание, а не создаёт новое (§2.3.12).
	FindIdempotent(ctx context.Context, key, userID, endpoint string) (string, bool, error)
	SaveIdempotent(ctx context.Context, key, userID, endpoint, jobID string) error
}
