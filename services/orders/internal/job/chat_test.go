package job

import (
	"errors"
	"strings"
	"testing"
)

func TestМаскировкаПрячетТелефоныИНики(t *testing.T) {
	cases := []struct {
		name string
		text string
	}{
		{"телефон с плюсом", "Звоните +374 91 234 567"},
		{"телефон подряд", "мой номер 093456789"},
		{"телефон с дефисами", "тел 093-45-67-89"},
		{"ник телеграма", "пиши @karen_excavator"},
		{"ссылка телеграма", "вот t.me/karen"},
		{"почта", "скинь на karen@mail.ru"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			masked, changed := MaskContacts(c.text)
			if !changed || !strings.Contains(masked, "[контакт скрыт]") {
				t.Fatalf("контакт должен быть скрыт: %q → %q", c.text, masked)
			}
		})
	}
}

func TestМаскировкаНеТрогаетОбычныеЧисла(t *testing.T) {
	cases := []string{
		"Траншея 40 метров, глубина 1,2 м",
		"Цена 120000 драм",
		"Приеду в 9:30, работаем до 18:00",
		"Нужно 12 тонн вывезти",
	}

	for _, text := range cases {
		masked, changed := MaskContacts(text)
		if changed {
			t.Fatalf("обычные числа не контакты: %q → %q", text, masked)
		}
	}
}

func TestПустоеСообщениеОтклоняется(t *testing.T) {
	if !errors.Is(ValidateMessage("   "), ErrEmptyMessage) {
		t.Fatal("пустое сообщение отправлять нельзя")
	}
	if err := ValidateMessage("Здравствуйте, когда сможете приехать?"); err != nil {
		t.Fatalf("обычное сообщение должно проходить: %v", err)
	}
}

func TestСлишкомДлинноеСообщениеОтклоняется(t *testing.T) {
	var ve *ValidationError
	if !errors.As(ValidateMessage(strings.Repeat("а", 2001)), &ve) {
		t.Fatal("сообщение длиннее 2000 символов должно отклоняться")
	}
}

func TestПерепискаЗакрываетсяВместеСЗаданием(t *testing.T) {
	if err := CanChat(&Job{Status: StatusCollectingOffers}); err != nil {
		t.Fatalf("по открытому заданию переписка идёт: %v", err)
	}
	if err := CanChat(&Job{Status: StatusCompleted}); err != nil {
		t.Fatalf("после завершения стороны ещё договаривают детали: %v", err)
	}
	if !errors.Is(CanChat(&Job{Status: StatusCancelled}), ErrChatClosed) {
		t.Fatal("по снятому заданию переписки нет")
	}
}
