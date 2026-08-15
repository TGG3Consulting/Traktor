package catalog

import (
	"errors"
	"testing"
)

// Правка справочника у модерации (ТЗ §4.1, п.5).

func TestНазваниеНужноНаТрёхЯзыках(t *testing.T) {
	_, err := ValidateName(Name{Ru: "Бурение", En: "Drilling"})
	if !errors.Is(err, ErrNoName) {
		// Пустая строка на чужом языке выглядит как поломка приложения.
		t.Fatalf("недоперевод не должен проходить: %v", err)
	}
	n, err := ValidateName(Name{Hy: " Հորատում ", Ru: " Бурение ", En: " Drilling "})
	if err != nil {
		t.Fatalf("нормальное название: %v", err)
	}
	if n.Ru != "Бурение" {
		t.Fatalf("пробелы по краям должны срезаться: %q", n.Ru)
	}
}

func TestКлючТолькоЛатиницей(t *testing.T) {
	bad := []string{"Бурение", "work earth", "work_earth", "-work", "work-", ""}
	for _, v := range bad {
		if _, err := ValidateSlug(v); !errors.Is(err, ErrBadSlug) {
			t.Fatalf("ключ %q должен быть отклонён: %v", v, err)
		}
	}
	got, err := ValidateSlug("  Work-Drilling  ")
	if err != nil || got != "work-drilling" {
		t.Fatalf("ключ приводится к нижнему регистру: %q / %v", got, err)
	}
}

func TestШаблонХарактеристикПроверяетсяСтрого(t *testing.T) {
	min, max := 5.0, 1.0
	cases := map[string][]SpecField{
		"пустая подпись":       {{Key: "depth", Type: "number"}},
		"неизвестный тип":      {{Key: "depth", Type: "slider", LabelRu: "Глубина"}},
		"список без вариантов": {{Key: "soil", Type: "select", LabelRu: "Грунт"}},
		"минимум больше максимума": {
			{Key: "depth", Type: "number", LabelRu: "Глубина", Min: &min, Max: &max},
		},
		"повтор ключа": {
			{Key: "depth", Type: "number", LabelRu: "Глубина"},
			{Key: "depth", Type: "text", LabelRu: "Глубина словами"},
		},
	}
	for name, fields := range cases {
		if _, err := ValidateSpec(fields); !errors.Is(err, ErrBadSpec) {
			// Ошибка здесь — сломанная форма визарда у всех, кто выберет
			// категорию, поэтому проверяем строго.
			t.Fatalf("%s: должно быть отклонено, получили %v", name, err)
		}
	}

	ok := []SpecField{
		{Key: "depth", Type: "number", Unit: "м", LabelRu: "Глубина"},
		{Key: "soil", Type: "select", LabelRu: "Грунт", Options: []string{"мягкий", "скальный"}},
	}
	if _, err := ValidateSpec(ok); err != nil {
		t.Fatalf("нормальный шаблон: %v", err)
	}
}
