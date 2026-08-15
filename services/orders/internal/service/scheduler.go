package service

import (
	"context"
	"log/slog"
	"time"

	"traktor/orders/internal/job"
)

// Scheduler доводит до конца то, что зависит от времени, а не от действий
// людей (ТЗ §2.9, §2.11):
//   - финиш аукциона, когда истекло время торга;
//   - закрытие задания, если заказчик промолчал всё окно решения;
//   - автоприёмка работы через 48 часов молчания заказчика;
//   - публикация одиноких оценок через неделю ожидания (ТЗ §2.13).
//
// Без него аукцион, у которого вышло время, так и висел бы «идёт торг», а
// исполнитель ждал бы оплаты, пока заказчик не вспомнит нажать кнопку.
type Scheduler struct {
	svc  *Service
	log  *slog.Logger
	tick time.Duration
}

func NewScheduler(svc *Service, log *slog.Logger, tick time.Duration) *Scheduler {
	if tick <= 0 {
		tick = time.Minute
	}
	return &Scheduler{svc: svc, log: log, tick: tick}
}

// Run работает до отмены контекста.
func (s *Scheduler) Run(ctx context.Context) {
	t := time.NewTicker(s.tick)
	defer t.Stop()

	// Первый проход сразу: после перезапуска сервиса могли накопиться
	// просроченные аукционы, ждать целый интервал незачем.
	s.RunOnce(ctx)

	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			s.RunOnce(ctx)
		}
	}
}

// RunOnce — один проход. Вынесен отдельно, чтобы его можно было вызвать из
// теста, не запуская таймеров.
func (s *Scheduler) RunOnce(ctx context.Context) {
	now := s.svc.now().UTC()

	// Одинокие оценки открываются по сроку независимо от заданий: человек,
	// оценивший честно, не должен ждать вечно молчания второй стороны.
	if err := s.svc.publishDueReviews(ctx); err != nil {
		s.log.Warn("публикация отзывов по сроку не прошла", "err", err)
	}

	due, err := s.svc.st.DueJobs(ctx, now)
	if err != nil {
		s.log.Warn("не удалось получить задания по времени", "err", err)
		return
	}

	for i := range due {
		j := due[i]
		switch j.Status {
		case job.StatusBidding:
			if _, err := s.svc.FinishAuction(ctx, j.ID); err != nil {
				s.log.Warn("финиш аукциона не прошёл", "job", j.ID, "err", err)
				continue
			}
			s.log.Info("аукцион завершён по времени", "job", j.ID)

		case job.StatusDeciding:
			if _, err := s.svc.ExpireDecision(ctx, j.ID); err != nil {
				s.log.Warn("закрытие по окну решения не прошло", "job", j.ID, "err", err)
				continue
			}
			s.log.Info("окно решения истекло", "job", j.ID)

		case job.StatusWorkDone:
			if err := s.autoAccept(ctx, j.ID); err != nil {
				s.log.Warn("автоприёмка не прошла", "job", j.ID, "err", err)
				continue
			}
			s.log.Info("работа принята автоматически", "job", j.ID)
		}
	}
}

// autoAccept закрывает сделку от имени заказчика, когда истекли 48 часов на
// приёмку. Обе стороны предупреждены заранее — это заявленное поведение,
// а не сюрприз (ТЗ §2.11).
func (s *Scheduler) autoAccept(ctx context.Context, jobID string) error {
	d, err := s.svc.st.DealByJob(ctx, jobID)
	if err != nil {
		return err
	}
	if d.Status != job.DealWorkDone {
		return nil
	}
	_, err = s.svc.AdvanceDeal(ctx, d.ClientID, d.ID, job.DealCompleted,
		"принято автоматически: истёк срок приёмки")
	return err
}
