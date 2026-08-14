package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"traktor/catalog/internal/catalog"
	"traktor/catalog/internal/store"
)

func newTestServer() http.Handler { return New(store.NewMemory()).Routes() }

func get(t *testing.T, h http.Handler, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec
}

func TestСписокКатегорийОтдаётсяДеревом(t *testing.T) {
	rec := get(t, newTestServer(), "/v1/categories")

	if rec.Code != http.StatusOK {
		t.Fatalf("ожидали 200, получили %d", rec.Code)
	}
	var body struct {
		Items []catalog.Category `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("ответ не разобрался: %v", err)
	}
	if len(body.Items) == 0 {
		t.Fatal("справочник пуст")
	}
	first := body.Items[0]
	if first.Name.Ru == "" || first.Name.Hy == "" || first.Name.En == "" {
		t.Fatalf("название должно приходить на трёх языках: %+v", first.Name)
	}
	if first.Icon == "" {
		t.Fatal("у категории должна быть иконка Phosphor")
	}
	if first.SpecTemplate == nil {
		t.Fatal("specTemplate должен быть массивом, а не null — иначе клиенту нужна доп. проверка")
	}
}

func TestФильтрПоВетвиДерева(t *testing.T) {
	rec := get(t, newTestServer(), "/v1/categories?kind=unit")
	if rec.Code != http.StatusOK {
		t.Fatalf("ожидали 200, получили %d", rec.Code)
	}
	var body struct {
		Items []catalog.Category `json:"items"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	// В памяти лежат только work-категории, поэтому ветвь техники пуста —
	// но ответ обязан быть массивом, а не null.
	if body.Items == nil {
		t.Fatal("items должен быть [] при пустом результате")
	}
}

func TestНеизвестнаяВетвьОтклоняется(t *testing.T) {
	rec := get(t, newTestServer(), "/v1/categories?kind=машины")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("ожидали 400, получили %d", rec.Code)
	}
}

func TestКатегорияПоИдентификатору(t *testing.T) {
	h := newTestServer()

	ok := get(t, h, "/v1/categories/c02b2502-1789-5217-be9f-d5fc04fe1cae")
	if ok.Code != http.StatusOK {
		t.Fatalf("ожидали 200, получили %d", ok.Code)
	}
	var c catalog.Category
	_ = json.Unmarshal(ok.Body.Bytes(), &c)
	if c.Slug != "work-earth" {
		t.Fatalf("вернулась не та категория: %s", c.Slug)
	}

	missing := get(t, h, "/v1/categories/00000000-0000-0000-0000-000000000000")
	if missing.Code != http.StatusNotFound {
		t.Fatalf("ожидали 404, получили %d", missing.Code)
	}
}
