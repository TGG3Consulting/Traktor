package service

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"testing"
	"time"

	"traktor/identity/internal/sms"
	"traktor/identity/internal/store"
	"traktor/identity/internal/token"
)

func newAuth(t *testing.T) (*Auth, *sms.Fake, *ecdsa.PublicKey) {
	t.Helper()
	priv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	fake := sms.NewFake()
	a := NewAuth(store.NewMemory(), fake, token.NewSigner(priv, "test"), time.Now)
	return a, fake, &priv.PublicKey
}

func TestOtpFlow(t *testing.T) {
	ctx := context.Background()
	a, fake, pub := newAuth(t)
	const phone = "+37491234567"

	if _, _, err := a.StartOTP(ctx, phone); err != nil {
		t.Fatalf("start: %v", err)
	}
	code := fake.Last(phone)
	if len(code) != 6 {
		t.Fatalf("ожидали 6-значный код, получили %q", code)
	}

	// Неверный код — ошибка.
	if _, err := a.VerifyOTP(ctx, phone, "000000"); err == nil {
		t.Fatal("неверный код должен отклоняться")
	}

	// Верный код — сессия с валидным access-токеном.
	sess, err := a.VerifyOTP(ctx, phone, code)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	claims, err := token.Parse(sess.AccessToken, pub, time.Now())
	if err != nil {
		t.Fatalf("парсинг токена: %v", err)
	}
	if claims.Sub != sess.User.ID || claims.ActiveRole != "client" {
		t.Fatalf("claims не совпадают: %+v", claims)
	}
}

func TestLockoutAfter3(t *testing.T) {
	ctx := context.Background()
	a, _, _ := newAuth(t)
	const phone = "+37491000000"
	_, _, _ = a.StartOTP(ctx, phone)
	for i := 0; i < 2; i++ {
		if _, err := a.VerifyOTP(ctx, phone, "111111"); err != ErrCodeInvalid {
			t.Fatalf("попытка %d: ждали ErrCodeInvalid, получили %v", i, err)
		}
	}
	if _, err := a.VerifyOTP(ctx, phone, "111111"); err != ErrTooManyAttempts {
		t.Fatalf("3-я попытка должна дать ErrTooManyAttempts, получили %v", err)
	}
}

func TestRefreshRotationAndReuse(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)
	const phone = "+37491222333"
	_, _, _ = a.StartOTP(ctx, phone)
	sess, err := a.VerifyOTP(ctx, phone, fake.Last(phone))
	if err != nil {
		t.Fatal(err)
	}
	// Первый refresh — ок, выдаёт новую пару.
	s2, err := a.Refresh(ctx, sess.RefreshToken)
	if err != nil {
		t.Fatalf("refresh: %v", err)
	}
	// Повторное использование старого refresh — отклоняется (reuse detection).
	if _, err := a.Refresh(ctx, sess.RefreshToken); err != ErrRefreshInvalid {
		t.Fatalf("повтор старого refresh должен отклоняться, получили %v", err)
	}
	if s2.AccessToken == "" {
		t.Fatal("новый access пустой")
	}
}

func TestRefreshPreservesRole(t *testing.T) {
	ctx := context.Background()
	a, fake, pub := newAuth(t)
	const phone = "+37491444555"
	_, _, _ = a.StartOTP(ctx, phone)
	sess, err := a.VerifyOTP(ctx, phone, fake.Last(phone))
	if err != nil {
		t.Fatal(err)
	}
	// Пользователь стал исполнителем.
	if _, err := a.UpdateProfile(ctx, sess.User.ID, ProfilePatch{ActiveRole: ptr("owner")}); err != nil {
		t.Fatalf("update: %v", err)
	}
	// После ротации токена роль владельца должна сохраниться (баг-регресс).
	s2, err := a.Refresh(ctx, sess.RefreshToken)
	if err != nil {
		t.Fatalf("refresh: %v", err)
	}
	claims, err := token.Parse(s2.AccessToken, pub, time.Now())
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if claims.ActiveRole != "owner" {
		t.Fatalf("после refresh активная роль должна быть owner, получили %q", claims.ActiveRole)
	}
	if !contains(claims.Roles, "owner") {
		t.Fatalf("после refresh роли должны содержать owner: %v", claims.Roles)
	}
}

func TestUpdateProfile(t *testing.T) {
	ctx := context.Background()
	a, fake, _ := newAuth(t)
	const phone = "+37491666777"
	_, _, _ = a.StartOTP(ctx, phone)
	sess, err := a.VerifyOTP(ctx, phone, fake.Last(phone))
	if err != nil {
		t.Fatal(err)
	}
	u, err := a.UpdateProfile(ctx, sess.User.ID, ProfilePatch{
		Name: ptr("Тигран"), City: ptr("Ереван"), ActiveRole: ptr("owner"),
	})
	if err != nil {
		t.Fatalf("update: %v", err)
	}
	if u.Name != "Тигран" || u.City != "Ереван" || u.ActiveRole != "owner" {
		t.Fatalf("профиль не обновился: %+v", u)
	}
	if !u.Verified {
		t.Fatal("профиль с именем должен стать verified")
	}
	if !contains(u.Roles, "owner") || !contains(u.Roles, "client") {
		t.Fatalf("должны быть обе роли: %v", u.Roles)
	}
	// Недопустимая роль отклоняется.
	if _, err := a.UpdateProfile(ctx, sess.User.ID, ProfilePatch{ActiveRole: ptr("admin")}); err != ErrInvalidRole {
		t.Fatalf("ждали ErrInvalidRole, получили %v", err)
	}
	// Несуществующий пользователь.
	if _, err := a.UpdateProfile(ctx, "no-such-id", ProfilePatch{Name: ptr("x")}); err == nil {
		t.Fatal("ждали ошибку на несуществующего пользователя")
	}
}

func ptr(s string) *string { return &s }
