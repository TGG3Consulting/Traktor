package push

import (
	"context"
	"log"
	"strings"
	"sync"
)

// Fake — провайдер для разработки и тестов: ничего не шлёт наружу, только
// пишет в лог и запоминает отправленные сообщения (для проверки в тестах).
// Токены с префиксом "invalid" считаются протухшими — так тесты и dev могут
// прогонять ветку очистки токенов без реального FCM.
type Fake struct {
	mu   sync.Mutex
	Sent []Message
}

func NewFake() *Fake { return &Fake{} }

func (f *Fake) Name() string { return "fake" }

func (f *Fake) Send(_ context.Context, m Message) error {
	if strings.HasPrefix(m.Token, "invalid") {
		return ErrTokenInvalid
	}
	f.mu.Lock()
	f.Sent = append(f.Sent, m)
	f.mu.Unlock()
	log.Printf("push(fake): → %s | %s: %s", m.Token, m.Title, m.Body)
	return nil
}

// Count — сколько сообщений реально «доставлено» (для тестов).
func (f *Fake) Count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.Sent)
}
