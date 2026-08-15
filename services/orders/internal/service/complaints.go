package service

import (
	"context"
	"time"

	"github.com/google/uuid"

	"traktor/orders/internal/job"
)

// Жалобы и сводка площадки (ТЗ §4.1, п.1 и 6).
//
// Пока пожаловаться некуда, единственная реакция на обман — уйти. А пока у
// владельца нет сводки, он узнаёт о проблеме от тех, кто уже ушёл.

// Complain — пожаловаться на задание или человека.
func (s *Service) Complain(ctx context.Context, authorID, targetKind, targetID, reason string) (*job.Complaint, error) {
	if !job.ValidTarget(targetKind) {
		return nil, job.ErrComplaintTarget
	}
	if targetID == "" {
		return nil, job.ErrComplaintTarget
	}
	if targetKind == job.TargetUser && targetID == authorID {
		return nil, job.ErrComplaintSelf
	}
	text, err := job.ValidateComplaint(reason)
	if err != nil {
		return nil, err
	}
	// Жалоба на несуществующее задание только засоряет очередь.
	if targetKind == job.TargetJob {
		j, err := s.st.ByID(ctx, targetID)
		if err != nil {
			return nil, err
		}
		if j.ClientID == authorID {
			return nil, job.ErrComplaintSelf
		}
	}

	c := &job.Complaint{
		ID:         uuid.NewString(),
		TargetKind: targetKind,
		TargetID:   targetID,
		AuthorID:   authorID,
		Reason:     text,
		Status:     job.ComplaintOpen,
		CreatedAt:  s.now().UTC(),
	}
	if err := s.st.CreateComplaint(ctx, c); err != nil {
		return nil, err
	}
	return c, nil
}

// ComplaintQueue — очередь модерации, старые сверху.
func (s *Service) ComplaintQueue(ctx context.Context, limit int) ([]job.Complaint, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	return s.st.OpenComplaints(ctx, limit)
}

// ReviewComplaint — решение модератора по жалобе.
//
// Снятие контента отменяет задание: оставлять его в ленте после решения
// «снять» — значит показать людям, что жалоба ничего не меняет.
func (s *Service) ReviewComplaint(ctx context.Context, moderatorID, complaintID string,
	action job.ComplaintAction, note string) (*job.Complaint, error) {
	c, err := s.st.ComplaintByID(ctx, complaintID)
	if err != nil {
		return nil, err
	}
	if c.Status != job.ComplaintOpen {
		return nil, job.ErrComplaintClosed
	}
	if !job.ValidAction(action) {
		return nil, job.ErrComplaintAction
	}

	now := s.now().UTC()
	c.Status = job.ComplaintReviewed
	c.Action = action
	c.Note = note
	c.ReviewedBy = moderatorID
	c.ReviewedAt = &now
	if err := s.st.UpdateComplaint(ctx, c); err != nil {
		return nil, err
	}

	if action == job.ActionRemoved && c.TargetKind == job.TargetJob {
		if j, err := s.st.ByID(ctx, c.TargetID); err == nil &&
			job.CanTransition(j.Status, job.StatusCancelled) {
			j.Status = job.StatusCancelled
			j.UpdatedAt = now
			_ = s.st.Update(ctx, j)
			// Автор задания должен понимать, почему оно исчезло: молчание он
			// прочитает как поломку и опубликует то же самое заново.
			s.notify.Send(ctx, j.ClientID, "Задание снято модерацией", preview(note),
				map[string]string{"kind": "job", "route": "/jobs/" + j.ID, "jobId": j.ID})
		}
	}
	if action == job.ActionWarned && c.TargetKind == job.TargetUser {
		s.notify.Send(ctx, c.TargetID, "Предупреждение модерации", preview(note),
			map[string]string{"kind": "system", "route": "/notifications"})
	}

	// Пожаловавшийся видит, что его услышали, — иначе в следующий раз он не
	// пожалуется, а уйдёт.
	s.notify.Send(ctx, c.AuthorID, "Жалоба рассмотрена: "+job.ActionRU(action), preview(note),
		map[string]string{"kind": "system", "route": "/notifications"})

	return c, nil
}

// PlatformStats — сводка площадки за период. Регистрации живут в identity,
// поэтому спрашиваются отдельно (правило 12: cross-schema JOIN запрещён).
func (s *Service) PlatformStats(ctx context.Context, from, to time.Time) (job.PlatformStats, error) {
	stats, err := s.st.PlatformStats(ctx, from.UTC(), to.UTC())
	if err != nil {
		return stats, err
	}
	stats.From, stats.To = from, to
	if counter, ok := s.profiles.(interface {
		CountUsers(ctx context.Context, from, to time.Time) int
	}); ok {
		stats.Users = counter.CountUsers(ctx, from, to)
	}
	return stats, nil
}
