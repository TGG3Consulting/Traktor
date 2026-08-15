package service

import (
	"context"
	"errors"
	"log/slog"
	"time"
)

// Удаление аккаунта с отсрочкой (ТЗ §2.3, §4.3).
//
// Уйти с площадки человек должен мочь. Но удаление без отсрочки — необратимая
// кнопка рядом с обычными настройками: нажимают в сердцах, а возвращаются
// через день. Поэтому запрос ставится в очередь, и вход в течение срока его
// отменяет.
//
// По истечении срока профиль обезличивается, а не стирается: на сделки
// ссылаются отзывы и рейтинг второй стороны, и вычистить их значило бы
// наказать того, кто остался.

// DeleteGrace — сколько человек может передумать.
const DeleteGrace = 30 * 24 * time.Hour

var ErrAlreadyDeleting = errors.New("identity: удаление уже запрошено")

// RequestDeletion — поставить аккаунт в очередь на удаление.
func (a *Auth) RequestDeletion(ctx context.Context, userID string) (time.Time, error) {
	u, err := a.store.GetUserByID(ctx, userID)
	if err != nil {
		return time.Time{}, err
	}
	if u.DeleteAfter != nil {
		return *u.DeleteAfter, ErrAlreadyDeleting
	}

	now := a.now()
	until := now.Add(DeleteGrace)
	if err := a.store.RequestDeletion(ctx, userID, now, until); err != nil {
		return time.Time{}, err
	}
	return until, nil
}

// CancelDeletion — человек передумал.
func (a *Auth) CancelDeletion(ctx context.Context, userID string) error {
	return a.store.CancelDeletion(ctx, userID)
}

// RunDeletions обезличивает тех, у кого отсрочка истекла. Вызывается фоновым
// обработчиком: удаление должно происходить само, без похода в поддержку.
func (a *Auth) RunDeletions(ctx context.Context) (int, error) {
	due, err := a.store.DueDeletions(ctx, a.now(), 100)
	if err != nil {
		return 0, err
	}
	done := 0
	for _, u := range due {
		if err := a.store.Anonymize(ctx, u.ID, a.now()); err != nil {
			// Одна неудача не должна останавливать очередь: остальные
			// подождавшие тридцать дней имеют право уйти сегодня.
			slog.Error("identity: обезличивание не удалось", "user", u.ID, "err", err)
			continue
		}
		done++
	}
	return done, nil
}

// StartDeletionWorker запускает обработчик отсроченных удалений.
func (a *Auth) StartDeletionWorker(ctx context.Context, every time.Duration) {
	if every <= 0 {
		every = time.Hour
	}
	go func() {
		t := time.NewTicker(every)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				if n, err := a.RunDeletions(ctx); err != nil {
					slog.Error("identity: обработчик удалений", "err", err)
				} else if n > 0 {
					slog.Info("identity: аккаунты обезличены", "count", n)
				}
			}
		}
	}()
}
