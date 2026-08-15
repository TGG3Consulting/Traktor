package share

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// Превью ссылок в мессенджерах (ТЗ §4.2).

func TestПревьюЗаданияСобираетКарточку(t *testing.T) {
	orders := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/v1/jobs/") {
			t.Fatalf("неожиданный путь: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{
			"title":"Выкопать траншею 40 м",
			"description":"Глубина 1,2 м, грунт мягкий",
			"address":"Ереван, Аван",
			"budgetAmount":120000,
			"photos":[{"url":"https://media.local/1.jpg"}]
		}`))
	}))
	defer orders.Close()

	h := New(orders.URL, "", "https://app.homly.am")
	rr := httptest.NewRecorder()
	h.Routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/jobs/abc", nil))

	body := rr.Body.String()
	for _, want := range []string{
		`og:title" content="Выкопать траншею 40 м"`,
		"Ереван, Аван",
		// Цена в превью — то, ради чего по ссылке кликают.
		"120 000",
		`og:image" content="https://media.local/1.jpg"`,
		`og:url" content="https://app.homly.am/jobs/abc"`,
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("в превью нет %q:\n%s", want, body)
		}
	}
}

func TestПревьюБезФотографииБерётЛоготип(t *testing.T) {
	orders := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"title":"Нужен самосвал","description":"Вывезти грунт"}`))
	}))
	defer orders.Close()

	h := New(orders.URL, "", "https://app.homly.am")
	rr := httptest.NewRecorder()
	h.Routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/jobs/abc", nil))

	// Пустое og:image превращает карточку в одну строку текста.
	if !strings.Contains(rr.Body.String(), "/icons/og-default.png") {
		t.Fatalf("нет картинки по умолчанию:\n%s", rr.Body.String())
	}
}

func TestСнятоеЗаданиеНеЛомаетПревью(t *testing.T) {
	orders := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer orders.Close()

	h := New(orders.URL, "", "https://app.homly.am")
	rr := httptest.NewRecorder()
	h.Routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/jobs/abc", nil))

	if rr.Code != http.StatusOK {
		t.Fatalf("битая ссылка должна отдавать страницу, а не ошибку: %d", rr.Code)
	}
	if !strings.Contains(rr.Body.String(), "не найдено") {
		t.Fatalf("нет объяснения:\n%s", rr.Body.String())
	}
}

func TestПревьюПрофиляПоказываетДоверие(t *testing.T) {
	identity := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"name":"Карен","city":"Ереван","verified":true,"rating":4.8,"ratingCount":36}`))
	}))
	defer identity.Close()

	h := New("", identity.URL, "https://app.homly.am")
	rr := httptest.NewRecorder()
	h.Routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/users/xyz", nil))

	body := rr.Body.String()
	for _, want := range []string{"Карен", "Ереван", "4.8", "работ: 36", "профиль проверен"} {
		if !strings.Contains(body, want) {
			t.Fatalf("в превью профиля нет %q:\n%s", want, body)
		}
	}
}

func TestРазметкаЭкранируется(t *testing.T) {
	orders := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"title":"Траншея \"под ключ\" <script>alert(1)</script>","description":"текст"}`))
	}))
	defer orders.Close()

	h := New(orders.URL, "", "https://app.homly.am")
	rr := httptest.NewRecorder()
	h.Routes().ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/jobs/abc", nil))

	// Название задания пишет заказчик: без экранирования кавычка обрывает
	// атрибут, а тег выполняется у всех, кто открыл ссылку.
	if strings.Contains(rr.Body.String(), "<script>") {
		t.Fatalf("разметка из названия попала в страницу:\n%s", rr.Body.String())
	}
}

func TestДлинноеОписаниеПодрезаетсяПоСлову(t *testing.T) {
	long := strings.Repeat("слово ", 100)
	got := cut(long, 50)
	if len([]rune(got)) > 51 {
		t.Fatalf("описание не подрезано: %d", len([]rune(got)))
	}
	if strings.Contains(got, "слов…") {
		t.Fatalf("обрыв на середине слова выглядит неряшливо: %q", got)
	}
}

func TestСуммаЧитаемая(t *testing.T) {
	if got := money(120000); got != "120 000 ֏" {
		t.Fatalf("сумма: %q", got)
	}
	if got := money(900); got != "900 ֏" {
		t.Fatalf("сумма: %q", got)
	}
}
