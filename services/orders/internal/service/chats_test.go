package service

import (
	"context"
	"errors"
	"strings"
	"testing"

	"traktor/orders/internal/job"
)

func TestЧатОдинНаПаруУчастников(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)

	// Исполнитель написал первым, заказчик открыл переписку следом.
	fromOwner, err := svc.OpenChat(ctx, owner, j.ID, "")
	if err != nil {
		t.Fatalf("открытие чата исполнителем: %v", err)
	}
	fromClient, err := svc.OpenChat(ctx, client, j.ID, owner)
	if err != nil {
		t.Fatalf("открытие чата заказчиком: %v", err)
	}

	if fromOwner.ID != fromClient.ID {
		t.Fatal("на пару «задание + исполнитель» должен быть один чат")
	}
}

func TestПостороннийВЧатНеПопадает(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)
	c, _ := svc.OpenChat(ctx, owner, j.ID, "")

	if _, err := svc.Chat(ctx, owner2, c.ID); !errors.Is(err, job.ErrChatForbidden) {
		t.Fatalf("чужую переписку читать нельзя: %v", err)
	}
	if _, _, err := svc.SendMessage(ctx, owner2, c.ID, "привет"); !errors.Is(err, job.ErrChatForbidden) {
		t.Fatalf("в чужую переписку писать нельзя: %v", err)
	}
}

func TestКонтактыМаскируютсяДоСделки(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)
	c, _ := svc.OpenChat(ctx, owner, j.ID, "")

	msg, masked, err := svc.SendMessage(ctx, owner, c.ID, "Звоните +374 91 234 567, договоримся")
	if err != nil {
		t.Fatalf("отправка: %v", err)
	}

	if !masked {
		t.Fatal("отправитель должен узнать, что контакт скрыт")
	}
	if strings.Contains(msg.Text, "234") {
		t.Fatalf("телефон не должен уходить собеседнику: %q", msg.Text)
	}
}

func TestВЧатеСделкиКонтактыНеПрячутся(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j, o := dealReady(t, svc)
	_, _ = svc.ConfirmDeal(ctx, client, j.ID)

	c, err := svc.OpenChat(ctx, o.OwnerID, j.ID, "")
	if err != nil {
		t.Fatalf("открытие чата: %v", err)
	}
	if c.Kind != job.ChatDeal {
		t.Fatalf("после подтверждения сделки чат становится чатом сделки: %s", c.Kind)
	}

	msg, masked, err := svc.SendMessage(ctx, o.OwnerID, c.ID, "Наберу с +374 91 234 567")
	if err != nil {
		t.Fatalf("отправка: %v", err)
	}
	if masked || !strings.Contains(msg.Text, "234") {
		t.Fatal("в сделке стороны уже знают телефоны — прятать их незачем")
	}
}

func TestНепрочитанныеСчитаютсяТолькоЧужие(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)
	c, _ := svc.OpenChat(ctx, owner, j.ID, "")

	_, _, _ = svc.SendMessage(ctx, owner, c.ID, "Здравствуйте, когда удобно?")

	// У отправителя непрочитанного нет.
	forOwner, _ := svc.MyChats(ctx, owner, 20, 0)
	if len(forOwner) != 1 || forOwner[0].Unread != 0 {
		t.Fatalf("своё сообщение не может быть непрочитанным: %+v", forOwner)
	}

	forClient, _ := svc.MyChats(ctx, client, 20, 0)
	if len(forClient) != 1 || forClient[0].Unread != 1 {
		t.Fatalf("у получателя должно быть одно непрочитанное: %+v", forClient)
	}

	// Открыли переписку — значит прочитали.
	if _, err := svc.Messages(ctx, client, c.ID, 20, 0); err != nil {
		t.Fatalf("чтение: %v", err)
	}
	afterRead, _ := svc.MyChats(ctx, client, 20, 0)
	if afterRead[0].Unread != 0 {
		t.Fatalf("после открытия чата непрочитанных нет: %d", afterRead[0].Unread)
	}
}

func TestПоЗакрытомуЗаданиюПерепискаНеОткрывается(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)
	_, _ = svc.Cancel(ctx, client, j.ID)

	_, err := svc.OpenChat(ctx, owner, j.ID, "")

	if !errors.Is(err, job.ErrChatClosed) {
		t.Fatalf("по снятому заданию переписки нет: %v", err)
	}
}

func TestСобеседникПолучаетУведомление(t *testing.T) {
	svc, rec := newSvcWithNotifier()
	ctx := context.Background()
	j := published(t, svc)
	c, _ := svc.OpenChat(ctx, owner, j.ID, "")

	_, _, _ = svc.SendMessage(ctx, owner, c.ID, "Готов приступить завтра")

	msgs := rec.to(client)
	if len(msgs) == 0 {
		t.Fatal("о новом сообщении нужно уведомить собеседника")
	}
}

func TestПерепискаЧитаетсяСверхуВниз(t *testing.T) {
	svc := newSvc()
	ctx := context.Background()
	j := published(t, svc)
	c, _ := svc.OpenChat(ctx, owner, j.ID, "")

	_, _, _ = svc.SendMessage(ctx, owner, c.ID, "Первое")
	_, _, _ = svc.SendMessage(ctx, client, c.ID, "Второе")
	_, _, _ = svc.SendMessage(ctx, owner, c.ID, "Третье")

	msgs, err := svc.Messages(ctx, client, c.ID, 20, 0)
	if err != nil {
		t.Fatalf("история: %v", err)
	}
	if len(msgs) != 3 || msgs[0].Text != "Первое" || msgs[2].Text != "Третье" {
		t.Fatalf("диалог должен идти по времени, иначе ответы оказываются раньше вопросов: %+v", msgs)
	}
}
