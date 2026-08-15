// Package service — сценарии работы с заданиями: черновик визарда,
// публикация, лента, деталка (ТЗ §2.6–2.8).
//
// Здесь живут решения, которые нельзя доверить клиенту: кто владелец, что
// считается заполненным, когда закончится аукцион, кому видно резервную цену.
package service

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"

	"traktor/orders/internal/job"
	"traktor/orders/internal/notify"
	"traktor/orders/internal/profiles"
	"traktor/orders/internal/units"
	"traktor/orders/internal/store"
)

type Service struct {
	// Планировщик в этом же пакете обращается к хранилищу напрямую: ему нужны
	// выборки по времени, которые незачем выносить в публичный API сервиса.
	st       store.Store
	now      func() time.Time
	notify   notify.Notifier
	profiles profiles.Client
	// units — техника исполнителя из catalog: ставку принимаем только своей
	// активной машиной (ТЗ §2.9).
	units units.Client
}

func New(st store.Store, now func() time.Time) *Service {
	return NewWithNotifier(st, now, notify.Noop{})
}

// NewWithNotifier — то же самое, но с уведомлениями о событиях заданий.
func NewWithNotifier(st store.Store, now func() time.Time, n notify.Notifier) *Service {
	return NewFull(st, now, n, profiles.Noop{})
}

// NewFull — сервис со всеми зависимостями: хранилище, часы, уведомления и
// карточки пользователей из identity.
func NewFull(st store.Store, now func() time.Time, n notify.Notifier, p profiles.Client) *Service {
	return NewWithUnits(st, now, n, p, units.Noop{})
}

// NewWithUnits — полный набор зависимостей, включая справку по технике.
func NewWithUnits(st store.Store, now func() time.Time, n notify.Notifier,
	p profiles.Client, u units.Client) *Service {
	if now == nil {
		now = time.Now
	}
	if n == nil {
		n = notify.Noop{}
	}
	if p == nil {
		p = profiles.Noop{}
	}
	if u == nil {
		u = units.Noop{}
	}
	return &Service{st: st, now: now, notify: n, profiles: p, units: u}
}

// checkUnit проверяет технику, которой откликаются или делают ставку.
//
// Пустой идентификатор допустим: часть заданий «исполнитель предложит технику»,
// да и каталог может быть недоступен — тогда мы не мешаем работать. Но если
// техника указана, она должна быть своей и активной, иначе ставка выглядит
// подтверждённой машиной, которой у человека нет (ТЗ §2.5, §2.9).
func (s *Service) checkUnit(ctx context.Context, ownerID string, unitID *string) error {
	if unitID == nil || *unitID == "" {
		return nil
	}
	u, ok := s.units.ByID(ctx, *unitID)
	if !ok {
		return nil
	}
	if u.OwnerID != ownerID {
		return job.ErrUnitForeign
	}
	if !u.Active {
		return job.ErrUnitInactive
	}
	return nil
}

// Profiles отдаёт карточки участников по идентификаторам — HTTP-слой
// подмешивает их в списки откликов, ставок и сделок.
func (s *Service) Profiles(ctx context.Context, ids []string) map[string]profiles.Profile {
	return s.profiles.ByIDs(ctx, ids)
}

// DraftInput — поля визарда. Все указатели: nil означает «шаг не трогали»,
// поэтому сохранение шага 3 не затирает цену, введённую на шаге 4.
type DraftInput struct {
	OrderType    *job.OrderType
	CategoryID   *string
	OpenToAny    *bool
	Title        *string
	Description  *string
	Params       map[string]any
	Photos       []string
	Geo          *job.Geo
	Address      *string
	Access       *job.Access
	DateMode     *job.DateMode
	DateStart    *time.Time
	DateEnd      *time.Time
	BudgetAmount *int64
	Currency     *string
	Mode         *job.Mode
	Auction      *job.Auction
	WorkersCount *int
	DraftStep    *int
}

// CreateDraft заводит черновик. Черновик появляется с первого шага визарда:
// по ТЗ §2.6 он автосохраняется и виден на главной заказчика.
func (s *Service) CreateDraft(ctx context.Context, clientID string, in DraftInput) (*job.Job, error) {
	now := s.now().UTC()
	j := &job.Job{
		ID:        uuid.NewString(),
		ClientID:  clientID,
		OrderType: job.TypeJob,
		Currency:  "AMD",
		Mode:      job.ModeFixed,
		Access:    job.AccessUnknown,
		DateMode:  job.DateASAP,
		Status:    job.StatusDraft,
		DraftStep: 1,
		Params:    map[string]any{},
		Photos:    []string{},
		CreatedAt: now,
		UpdatedAt: now,
	}
	apply(j, in)
	if err := s.st.Create(ctx, j); err != nil {
		return nil, err
	}
	return j, nil
}

// UpdateDraft сохраняет очередной шаг визарда. Менять можно только свой
// черновик: опубликованное задание правится отдельными сценариями, иначе
// исполнители видели бы условия, которые меняются под ними.
func (s *Service) UpdateDraft(ctx context.Context, clientID, id string, in DraftInput) (*job.Job, error) {
	j, err := s.own(ctx, clientID, id)
	if err != nil {
		return nil, err
	}
	if j.Status != job.StatusDraft {
		return nil, job.ErrNotDraft
	}
	apply(j, in)
	j.UpdatedAt = s.now().UTC()
	if err := s.st.Update(ctx, j); err != nil {
		return nil, err
	}
	return j, nil
}

// Publish публикует черновик: проверяет полноту, ставит статус по режиму и,
// для аукциона, считает время финиша на сервере (правило 9 — время серверное).
func (s *Service) Publish(ctx context.Context, clientID, id string) (*job.Job, error) {
	j, err := s.own(ctx, clientID, id)
	if err != nil {
		return nil, err
	}
	if j.Status != job.StatusDraft {
		return nil, job.ErrNotDraft
	}
	if err := j.ValidateForPublish(); err != nil {
		return nil, err
	}

	now := s.now().UTC()
	next := job.StatusAfterPublish(j.Mode)
	if !job.CanTransition(j.Status, next) {
		return nil, job.ErrBadTransition
	}
	if j.Mode == job.ModeAuction && j.Auction != nil {
		ends := now.Add(time.Duration(j.Auction.DurationH) * time.Hour)
		j.Auction.EndsAt = &ends
	}
	j.Status = next
	j.DraftStep = 5
	j.PublishedAt = &now
	j.UpdatedAt = now

	if err := s.st.Update(ctx, j); err != nil {
		return nil, err
	}
	return j, nil
}

// Cancel снимает задание. Отменить может только заказчик и только пока не
// начата работа — иначе это уже спор, а не отмена.
func (s *Service) Cancel(ctx context.Context, clientID, id string) (*job.Job, error) {
	j, err := s.own(ctx, clientID, id)
	if err != nil {
		return nil, err
	}
	if !job.CanTransition(j.Status, job.StatusCancelled) {
		return nil, job.ErrBadTransition
	}
	j.Status = job.StatusCancelled
	j.UpdatedAt = s.now().UTC()
	if err := s.st.Update(ctx, j); err != nil {
		return nil, err
	}
	return j, nil
}

// MyJobs — главная заказчика: его задания и черновики.
func (s *Service) MyJobs(ctx context.Context, clientID string, limit, offset int) ([]job.Job, error) {
	return s.st.ListByClient(ctx, clientID, clampLimit(limit), max0(offset))
}

// Feed — лента исполнителя.
func (s *Service) Feed(ctx context.Context, f store.Filter) ([]job.Job, error) {
	f.Limit = clampLimit(f.Limit)
	f.Offset = max0(f.Offset)
	return s.st.Feed(ctx, f)
}

// View отдаёт деталку и отмечает просмотр. Свой просмотр не считаем: иначе
// счётчик показывал бы активность заказчика, а не интерес исполнителей.
func (s *Service) View(ctx context.Context, viewerID, id string) (*job.Job, error) {
	j, err := s.st.ByID(ctx, id)
	if err != nil {
		return nil, err
	}
	// Пустой viewerID — гость: показываем задание, но просмотр не считаем.
	if viewerID != "" && j.ClientID != viewerID && job.IsOpen(j.Status) {
		if _, err := s.st.AddView(ctx, id, viewerID); err != nil {
			return nil, err
		}
		// Перечитываем, чтобы вернуть уже увеличенный счётчик.
		if j, err = s.st.ByID(ctx, id); err != nil {
			return nil, err
		}
	}
	// Резервная цена скрыта от исполнителей (ТЗ §2.6 шаг 4).
	if j.ClientID != viewerID && j.Auction != nil {
		clone := *j
		a := *j.Auction
		a.ReserveAmount = nil
		clone.Auction = &a
		return &clone, nil
	}
	return j, nil
}

// Idempotent возвращает задание по ключу идемпотентности, если такой запрос
// уже выполнялся.
func (s *Service) Idempotent(ctx context.Context, key, userID, endpoint string) (*job.Job, bool, error) {
	if key == "" {
		return nil, false, nil
	}
	id, ok, err := s.st.FindIdempotent(ctx, key, userID, endpoint)
	if err != nil || !ok || id == "" {
		return nil, ok, err
	}
	j, err := s.st.ByID(ctx, id)
	if errors.Is(err, job.ErrNotFound) {
		return nil, false, nil
	}
	return j, err == nil, err
}

// RememberIdempotent запоминает результат мутации под ключом клиента.
func (s *Service) RememberIdempotent(ctx context.Context, key, userID, endpoint, jobID string) error {
	if key == "" {
		return nil
	}
	return s.st.SaveIdempotent(ctx, key, userID, endpoint, jobID)
}

// own достаёт задание и проверяет, что оно принадлежит этому пользователю.
func (s *Service) own(ctx context.Context, clientID, id string) (*job.Job, error) {
	j, err := s.st.ByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if j.ClientID != clientID {
		return nil, job.ErrForbidden
	}
	return j, nil
}

func apply(j *job.Job, in DraftInput) {
	if in.OrderType != nil {
		j.OrderType = *in.OrderType
	}
	if in.CategoryID != nil {
		if *in.CategoryID == "" {
			j.CategoryID = nil
		} else {
			v := *in.CategoryID
			j.CategoryID = &v
		}
	}
	if in.OpenToAny != nil {
		j.OpenToAny = *in.OpenToAny
	}
	if in.Title != nil {
		j.Title = strings.TrimSpace(*in.Title)
	}
	if in.Description != nil {
		j.Description = strings.TrimSpace(*in.Description)
	}
	if in.Params != nil {
		j.Params = in.Params
	}
	if in.Photos != nil {
		j.Photos = in.Photos
	}
	if in.Geo != nil {
		g := *in.Geo
		j.Geo = &g
	}
	if in.Address != nil {
		j.Address = strings.TrimSpace(*in.Address)
	}
	if in.Access != nil {
		j.Access = *in.Access
	}
	if in.DateMode != nil {
		j.DateMode = *in.DateMode
		// «Как можно скорее» не хранит дат: иначе после смены режима в базе
		// останутся старые значения и попадут в карточку.
		if j.DateMode == job.DateASAP {
			j.DateStart, j.DateEnd = nil, nil
		}
	}
	if in.DateStart != nil {
		v := in.DateStart.UTC()
		j.DateStart = &v
	}
	if in.DateEnd != nil {
		v := in.DateEnd.UTC()
		j.DateEnd = &v
	}
	if in.BudgetAmount != nil {
		v := *in.BudgetAmount
		j.BudgetAmount = &v
	}
	if in.Currency != nil && *in.Currency != "" {
		j.Currency = *in.Currency
	}
	if in.Mode != nil {
		j.Mode = *in.Mode
		if j.Mode == job.ModeFixed {
			j.Auction = nil
		} else if j.Auction == nil {
			// Значения по умолчанию из ТЗ §2.6 шаг 4.
			j.Auction = &job.Auction{DurationH: 24, AutoExtend: true, DecisionWindowH: 12}
		}
	}
	if in.Auction != nil {
		a := *in.Auction
		if a.DurationH == 0 {
			a.DurationH = 24
		}
		if a.DecisionWindowH == 0 {
			a.DecisionWindowH = 12
		}
		j.Auction = &a
		j.Mode = job.ModeAuction
	}
	if in.WorkersCount != nil && *in.WorkersCount >= 0 {
		j.WorkersCount = *in.WorkersCount
	}
	if in.DraftStep != nil && *in.DraftStep >= 1 && *in.DraftStep <= 5 {
		// Шаг только растёт: возврат назад по визарду не должен «откатывать»
		// прогресс, который заказчик уже прошёл.
		if *in.DraftStep > j.DraftStep {
			j.DraftStep = *in.DraftStep
		}
	}
}

const (
	defaultLimit = 20 // ТЗ §2.7: бесконечная подгрузка по 20
	maxLimit     = 50
)

func clampLimit(l int) int {
	if l <= 0 {
		return defaultLimit
	}
	if l > maxLimit {
		return maxLimit
	}
	return l
}

func max0(v int) int {
	if v < 0 {
		return 0
	}
	return v
}
