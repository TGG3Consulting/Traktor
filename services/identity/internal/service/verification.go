package service

import (
	"context"
	"errors"
	"strings"

	"github.com/google/uuid"

	"traktor/identity/internal/store"
)

// Проверка человека и бейдж «Проверен» (ТЗ §2.3, §1.4).
//
// Бейдж — главный сигнал доверия в ленте: рядом с ним отклик читается иначе.
// Поэтому он выдаётся не по факту загрузки файла, а после того, как документ
// посмотрел живой модератор.

var (
	ErrNoDocuments  = errors.New("identity: приложите фото документа")
	ErrManyDocs     = errors.New("identity: не больше четырёх снимков")
	ErrBadDocKind   = errors.New("identity: неизвестный тип документа")
	ErrVerifyClosed = errors.New("identity: заявка уже разобрана")
	ErrNeedNameCity = errors.New("identity: сначала заполните имя в профиле")
)

const maxDocuments = 4

var docKinds = map[string]bool{"passport": true, "license": true, "other": true}

// SubmitVerification — подать документ на проверку.
func (a *Auth) SubmitVerification(ctx context.Context, userID, docKind string, docs []string) (*store.Verification, error) {
	u, err := a.store.GetUserByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	// Сверять документ не с чем, если в профиле пусто.
	if strings.TrimSpace(u.Name) == "" {
		return nil, ErrNeedNameCity
	}
	if u.Verified {
		// Повторная проверка уже проверенного — работа модерации впустую.
		return nil, ErrVerifyClosed
	}

	docKind = strings.TrimSpace(docKind)
	if docKind == "" {
		docKind = "passport"
	}
	if !docKinds[docKind] {
		return nil, ErrBadDocKind
	}

	clean := make([]string, 0, len(docs))
	for _, d := range docs {
		if d = strings.TrimSpace(d); d != "" {
			clean = append(clean, d)
		}
	}
	if len(clean) == 0 {
		return nil, ErrNoDocuments
	}
	if len(clean) > maxDocuments {
		return nil, ErrManyDocs
	}

	v := &store.Verification{
		ID:        uuid.NewString(),
		UserID:    userID,
		Documents: clean,
		DocKind:   docKind,
		Status:    store.VerifyPending,
		CreatedAt: a.now(),
	}
	if err := a.store.CreateVerification(ctx, v); err != nil {
		return nil, err
	}
	return v, nil
}

// MyVerification — состояние проверки для экрана профиля.
func (a *Auth) MyVerification(ctx context.Context, userID string) (*store.Verification, error) {
	return a.store.MyVerification(ctx, userID)
}

// VerificationQueue — очередь модерации, старые сверху.
func (a *Auth) VerificationQueue(ctx context.Context, limit int) ([]store.Verification, error) {
	return a.store.PendingVerifications(ctx, limit)
}

// ReviewVerification — решение модератора.
//
// Отказ требует причины: без неё человек не поймёт, что переснять, и либо
// подаст то же самое ещё раз, либо уйдёт.
func (a *Auth) ReviewVerification(ctx context.Context, moderatorID, id string,
	approve bool, reason string) (*store.Verification, error) {
	v, err := a.store.VerificationByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if v.Status != store.VerifyPending {
		return nil, ErrVerifyClosed
	}
	reason = strings.TrimSpace(reason)
	if !approve && len([]rune(reason)) < minReason {
		return nil, ErrNeedReason
	}

	now := a.now()
	v.Status = store.VerifyApproved
	if !approve {
		v.Status = store.VerifyRejected
	}
	v.Reason = reason
	v.ReviewedBy = moderatorID
	v.ReviewedAt = &now
	if err := a.store.UpdateVerification(ctx, v); err != nil {
		return nil, err
	}
	if approve {
		if err := a.store.SetVerified(ctx, v.UserID, true); err != nil {
			return nil, err
		}
	}

	action := "verify:approved"
	if !approve {
		action = "verify:rejected"
	}
	// Журнал (ТЗ §4.1, п.8): решение о доверии тоже должно быть прослеживаемым.
	if err := a.store.LogAdminAction(ctx, store.AdminAction{
		ID:        uuid.NewString(),
		ActorID:   moderatorID,
		Action:    action,
		TargetID:  v.UserID,
		Reason:    reason,
		CreatedAt: now,
	}); err != nil {
		return nil, err
	}
	return v, nil
}
