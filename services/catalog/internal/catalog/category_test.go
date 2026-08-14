package catalog

import "testing"

func ptr(s string) *string { return &s }

func TestBuildTreeСобираетДеревоИСохраняетПорядок(t *testing.T) {
	flat := []Category{
		{ID: "1", Slug: "excavator", SortOrder: 10},
		{ID: "2", ParentID: ptr("1"), Slug: "crawler", SortOrder: 10},
		{ID: "3", ParentID: ptr("1"), Slug: "wheeled", SortOrder: 20},
		{ID: "4", Slug: "truck", SortOrder: 20},
	}

	tree := BuildTree(flat)

	if len(tree) != 2 {
		t.Fatalf("корней должно быть 2, получили %d", len(tree))
	}
	if tree[0].Slug != "excavator" || tree[1].Slug != "truck" {
		t.Fatalf("порядок корней нарушен: %s, %s", tree[0].Slug, tree[1].Slug)
	}
	if len(tree[0].Children) != 2 {
		t.Fatalf("у экскаватора должно быть 2 потомка, получили %d", len(tree[0].Children))
	}
	if tree[0].Children[0].Slug != "crawler" || tree[0].Children[1].Slug != "wheeled" {
		t.Fatal("порядок потомков нарушен")
	}
	if len(tree[1].Children) != 0 {
		t.Fatal("у самосвала потомков быть не должно")
	}
}

// Узел, чей родитель отфильтрован (например, выбрали только kind=unit, а
// родитель — work), не должен потеряться: он поднимается в корень.
func TestBuildTreeПоднимаетСиротуВКорень(t *testing.T) {
	flat := []Category{
		{ID: "2", ParentID: ptr("нет-такого"), Slug: "crawler"},
	}

	tree := BuildTree(flat)

	if len(tree) != 1 || tree[0].Slug != "crawler" {
		t.Fatalf("сирота должна стать корнем, получили %+v", tree)
	}
}

func TestBuildTreeСобираетГлубокоеДерево(t *testing.T) {
	flat := []Category{
		{ID: "1", Slug: "a"},
		{ID: "2", ParentID: ptr("1"), Slug: "b"},
		{ID: "3", ParentID: ptr("2"), Slug: "c"},
	}

	tree := BuildTree(flat)

	if len(tree) != 1 {
		t.Fatalf("корень один, получили %d", len(tree))
	}
	if len(tree[0].Children) != 1 || tree[0].Children[0].Slug != "b" {
		t.Fatal("второй уровень собран неверно")
	}
	if len(tree[0].Children[0].Children) != 1 || tree[0].Children[0].Children[0].Slug != "c" {
		t.Fatal("третий уровень собран неверно")
	}
}
