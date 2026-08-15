// Package catalog — доменная модель справочника: дерево категорий работ и
// техники с шаблоном характеристик (ТЗ §1.12 Category, §2.5, §2.6).
package catalog

// Kind — ветвь дерева. Задание ссылается на работу, техника — на unit.
type Kind string

const (
	KindWork Kind = "work" // что нужно сделать
	KindUnit Kind = "unit" // чем это делают
)

// SpecField — одно поле характеристик. Клиент строит по нему форму: тип
// определяет виджет, unit — подпись единицы, min/max — валидацию,
// options — варианты для select.
type SpecField struct {
	Key      string   `json:"key"`
	Type     string   `json:"type"` // number | text | select | bool
	Unit     string   `json:"unit,omitempty"`
	Min      *float64 `json:"min,omitempty"`
	Max      *float64 `json:"max,omitempty"`
	Options  []string `json:"options,omitempty"`
	LabelHy  string   `json:"label_hy,omitempty"`
	LabelRu  string   `json:"label_ru,omitempty"`
	LabelEn  string   `json:"label_en,omitempty"`
	Required bool     `json:"required,omitempty"`
}

// Category — узел справочника. Name отдаётся сразу на трёх языках: клиент сам
// выбирает нужный и переключает язык без похода на сервер (ТЗ §1.4).
type Category struct {
	ID           string      `json:"id"`
	ParentID     *string     `json:"parentId,omitempty"`
	Kind         Kind        `json:"kind"`
	Slug         string      `json:"slug"`
	Name         Name        `json:"name"`
	Icon         string      `json:"icon"`
	SpecTemplate []SpecField `json:"specTemplate"`
	SortOrder    int         `json:"sortOrder"`
	// Active — видна ли категория в приложении. Скрытая остаётся в базе:
	// на неё ссылаются уже созданные задания и техника (ТЗ §4.1, п.5).
	Active   bool       `json:"active"`
	Children []Category `json:"children,omitempty"`
}

// Name — название на трёх языках проекта.
type Name struct {
	Hy string `json:"hy"`
	Ru string `json:"ru"`
	En string `json:"en"`
}

// BuildTree превращает плоский список в дерево, сохраняя порядок сортировки.
// Узлы, чей родитель отсутствует в списке (например, отфильтрован по kind),
// поднимаются в корень — иначе ветка молча исчезла бы из выдачи.
func BuildTree(flat []Category) []Category {
	exists := make(map[string]bool, len(flat))
	for _, c := range flat {
		exists[c.ID] = true
	}

	childrenOf := make(map[string][]Category, len(flat))
	var roots []Category
	for _, c := range flat {
		if c.ParentID != nil && exists[*c.ParentID] {
			childrenOf[*c.ParentID] = append(childrenOf[*c.ParentID], c)
			continue
		}
		roots = append(roots, c)
	}

	// Дерево собирается сверху вниз: так каждый узел получает уже готовые
	// поддеревья, и порядок сортировки из запроса сохраняется на всех уровнях.
	var build func(c Category) Category
	build = func(c Category) Category {
		c.Children = nil
		for _, ch := range childrenOf[c.ID] {
			c.Children = append(c.Children, build(ch))
		}
		return c
	}
	for i := range roots {
		roots[i] = build(roots[i])
	}
	return roots
}
