package sms

import (
	"context"
	"log/slog"
	"sync"
)

// Fake — провайдер для разработки и тестов: не шлёт SMS, а запоминает
// последний код по номеру. В тест-режиме включается флагом окружения.
type Fake struct {
	mu   sync.Mutex
	last map[string]string
}

func NewFake() *Fake { return &Fake{last: map[string]string{}} }

func (f *Fake) SendCode(_ context.Context, phone, code string) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.last[phone] = code
	// Включается только когда нет ключа Dexatel (dev-режим), поэтому реальные
	// коды пользователей сюда не попадают.
	slog.Info("fake SMS: код выпущен", "phone", phone, "code", code)
	return "fake", nil
}

// Last возвращает последний код, отправленный на номер (для тестов).
func (f *Fake) Last(phone string) string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.last[phone]
}
