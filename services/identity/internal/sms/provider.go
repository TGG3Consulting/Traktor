// Package sms — отправка OTP-кода. За интерфейсом прячется провайдер
// (Dexatel), чтобы его можно было заменить (путь эвакуации, архитектура §10).
package sms

import "context"

type Provider interface {
	// SendCode отправляет код на номер E.164. Возвращает канал доставки.
	SendCode(ctx context.Context, phone, code string) (channel string, err error)
}
