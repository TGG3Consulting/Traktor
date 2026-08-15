package catalog

import (
	"errors"
	"regexp"
	"strings"
)

// Правка справочника у модерации (ТЗ §4.1, п.5).
//
// Пока категории живут только в миграции, добавление вида работ требует
// выката сервиса: владелец не может отреагировать на спрос, пока не дойдут
// руки у разработчика. Здесь — правила, по которым справочник правится
// на ходу, не ломая уже созданные задания.

var (
	ErrNoName      = errors.New("catalog: название нужно на всех трёх языках")
	ErrBadSlug     = errors.New("catalog: ключ — латиница, цифры и дефис")
	ErrSlugTaken   = errors.New("catalog: такой ключ уже занят")
	ErrBadKind     = errors.New("catalog: ветвь — work или unit")
	ErrBadIcon     = errors.New("catalog: неизвестная иконка")
	ErrBadSpec     = errors.New("catalog: поле характеристик описано неверно")
	ErrOwnParent   = errors.New("catalog: категория не может быть своим родителем")
	ErrParentKind  = errors.New("catalog: родитель из другой ветви дерева")
	ErrHasChildren = errors.New("catalog: сначала уберите вложенные категории")
)

var slugRe = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)

// specTypes — типы полей, которые умеет строить клиент. Новый тип без правок
// приложения превратится в пустое место в форме, поэтому список закрытый.
var specTypes = map[string]bool{
	"number": true, "text": true, "select": true, "bool": true,
}

// ValidateName — название обязательно на всех трёх языках: пустая строка на
// чужом языке выглядит как поломка приложения, а не как недоперевод.
func ValidateName(n Name) (Name, error) {
	n.Hy, n.Ru, n.En = strings.TrimSpace(n.Hy), strings.TrimSpace(n.Ru), strings.TrimSpace(n.En)
	if n.Hy == "" || n.Ru == "" || n.En == "" {
		return n, ErrNoName
	}
	return n, nil
}

// ValidateSlug — стабильный ключ для кода и аналитики. Меняться он не должен:
// по нему сходятся отчёты за прошлые месяцы.
func ValidateSlug(slug string) (string, error) {
	slug = strings.ToLower(strings.TrimSpace(slug))
	if !slugRe.MatchString(slug) {
		return "", ErrBadSlug
	}
	return slug, nil
}

// ValidateSpec проверяет шаблон характеристик. Ошибка здесь — это сломанная
// форма визарда у всех, кто выберет категорию, поэтому проверяем строго.
func ValidateSpec(fields []SpecField) ([]SpecField, error) {
	seen := map[string]bool{}
	out := make([]SpecField, 0, len(fields))
	for _, f := range fields {
		f.Key = strings.TrimSpace(f.Key)
		if !slugRe.MatchString(f.Key) || seen[f.Key] {
			return nil, ErrBadSpec
		}
		seen[f.Key] = true

		if !specTypes[f.Type] {
			return nil, ErrBadSpec
		}
		// Список без вариантов — это поле, которое нечем заполнить.
		if f.Type == "select" && len(f.Options) == 0 {
			return nil, ErrBadSpec
		}
		if f.Min != nil && f.Max != nil && *f.Min > *f.Max {
			return nil, ErrBadSpec
		}
		if strings.TrimSpace(f.LabelRu) == "" {
			return nil, ErrBadSpec
		}
		out = append(out, f)
	}
	return out, nil
}

// ValidKind — ветвь дерева.
func ValidKind(k Kind) bool { return k == KindWork || k == KindUnit }
