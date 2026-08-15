package service

import (
	"context"
	"time"

	"traktor/notifications/internal/store"
)

// Настройки уведомлений и тихие часы (ТЗ §2.14).
//
// Правило простое: центр уведомлений получает всё, а push — только то, что
// человек разрешил и не ночью. Событие не теряется, но и телефон не звенит в
// три часа ночи из-за нового задания в ленте.

// EreванTZ — площадка работает в Армении: тихие часы считаются по местному
// времени, а не по UTC сервера.
var localZone = time.FixedZone("AMT", 4*3600)

// Prefs — настройки пользователя (по умолчанию, если он их не менял).
func (n *Notifier) Prefs(ctx context.Context, userID string) (store.Prefs, error) {
	if userID == "" {
		return store.Prefs{}, ErrInvalidInput
	}
	return n.store.PrefsOf(ctx, userID)
}

// SavePrefs сохраняет настройки.
func (n *Notifier) SavePrefs(ctx context.Context, p store.Prefs) error {
	if p.UserID == "" {
		return ErrInvalidInput
	}
	p.QuietFrom = clampHour(p.QuietFrom, 22)
	p.QuietTo = clampHour(p.QuietTo, 8)
	return n.store.SavePrefs(ctx, p, n.now().UTC())
}

func clampHour(h, fallback int) int {
	if h < 0 || h > 23 {
		return fallback
	}
	return h
}

// group — к какой группе настроек относится событие. Типы приходят из
// push-матрицы, а группы — то, как их видит человек в настройках.
func group(kind string) string {
	switch kind {
	case "auction", "outbid":
		return "auctions"
	case "deal", "offer", "review":
		return "deals"
	case "message":
		return "message"
	case "job":
		return "new_jobs"
	case "marketing":
		return "marketing"
	default:
		return "system"
	}
}

// allowPush решает, стоит ли звонить телефону. Возвращает false, когда группа
// выключена или идут тихие часы.
func allowPush(p store.Prefs, kind string, now time.Time) bool {
	switch group(kind) {
	case "auctions":
		if !p.Auctions {
			return false
		}
	case "deals":
		if !p.Deals {
			return false
		}
	case "message":
		if !p.Chat {
			return false
		}
	case "new_jobs":
		if !p.NewJobs {
			return false
		}
	case "marketing":
		if !p.Marketing {
			return false
		}
	}

	if !p.QuietHours || !inQuietHours(p, now) {
		return true
	}
	// Ночью проходит только то, что человек сам отметил как срочное.
	return kind == "outbid" && p.OutbidAlways
}

// inQuietHours — попадает ли момент в интервал тишины. Интервал обычно
// переходит через полночь (22:00–08:00), поэтому сравнение с разворотом.
func inQuietHours(p store.Prefs, now time.Time) bool {
	h := now.In(localZone).Hour()
	if p.QuietFrom == p.QuietTo {
		return false
	}
	if p.QuietFrom < p.QuietTo {
		return h >= p.QuietFrom && h < p.QuietTo
	}
	return h >= p.QuietFrom || h < p.QuietTo
}
