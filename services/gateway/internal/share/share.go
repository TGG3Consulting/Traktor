// Package share — превью ссылок в мессенджерах (ТЗ §4.2).
//
// Ссылками на задание и на исполнителя делятся в WhatsApp и Telegram — это
// основной канал сарафана. Flutter Web отдаёт один пустой index.html, поэтому
// бот мессенджера видит вместо карточки название приложения и ничего больше:
// ссылка выглядит как спам, и по ней не переходят.
//
// Здесь тот же адрес отдаётся ботам как обычная страница с og-тегами, а живого
// человека сразу уводит в приложение.
package share

import (
	"context"
	"encoding/json"
	"fmt"
	"html"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
)

// Handler собирает страницы превью.
type Handler struct {
	client *http.Client

	// ordersURL и identityURL — откуда берутся данные карточки.
	ordersURL   string
	identityURL string
	// appURL — куда уходит живой человек, открывший ссылку в браузере.
	appURL string
	// defaultImage — картинка для карточек без фотографии. Пустое og:image
	// превращает превью в одну строку текста.
	defaultImage string
}

func New(ordersURL, identityURL, appURL string) *Handler {
	return &Handler{
		client:       &http.Client{Timeout: 3 * time.Second},
		ordersURL:    strings.TrimRight(ordersURL, "/"),
		identityURL:  strings.TrimRight(identityURL, "/"),
		appURL:       strings.TrimRight(appURL, "/"),
		defaultImage: strings.TrimRight(appURL, "/") + "/icons/og-default.png",
	}
}

func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()
	r.Get("/jobs/{id}", h.job)
	r.Get("/users/{id}", h.user)
	return r
}

// job — превью задания.
func (h *Handler) job(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	target := h.appURL + "/jobs/" + id

	var j struct {
		Title       string `json:"title"`
		Description string `json:"description"`
		Address     string `json:"address"`
		Budget      *int64 `json:"budgetAmount"`
		Photos      []struct {
			URL string `json:"url"`
		} `json:"photos"`
	}
	if err := h.get(r.Context(), h.ordersURL+"/v1/jobs/"+id, &j); err != nil || j.Title == "" {
		// Задание могли снять или ссылка битая: показываем нейтральную
		// страницу вместо пустого превью, ведущего в никуда.
		writePage(w, page{
			Title:       "Traktor — техника и работы в Армении",
			Description: "Задание не найдено. Возможно, его уже сняли.",
			Image:       h.defaultImage,
			URL:         target,
		})
		return
	}

	desc := strings.TrimSpace(j.Description)
	if j.Address != "" {
		desc = j.Address + " · " + desc
	}
	if j.Budget != nil && *j.Budget > 0 {
		// Цена в превью — то, ради чего по ссылке кликают.
		desc = fmt.Sprintf("%s · бюджет %s", desc, money(*j.Budget))
	}

	image := h.defaultImage
	if len(j.Photos) > 0 {
		image = j.Photos[0].URL
	}
	writePage(w, page{
		Title:       j.Title,
		Description: cut(desc, 200),
		Image:       image,
		URL:         target,
	})
}

// user — превью карточки человека.
func (h *Handler) user(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	target := h.appURL + "/users/" + id

	var u struct {
		Name        string  `json:"name"`
		City        string  `json:"city"`
		Verified    bool    `json:"verified"`
		Rating      float64 `json:"rating"`
		RatingCount int     `json:"ratingCount"`
	}
	if err := h.get(r.Context(), h.identityURL+"/v1/users/"+id, &u); err != nil || u.Name == "" {
		writePage(w, page{
			Title:       "Traktor — техника и работы в Армении",
			Description: "Профиль не найден.",
			Image:       h.defaultImage,
			URL:         target,
		})
		return
	}

	parts := []string{}
	if u.City != "" {
		parts = append(parts, u.City)
	}
	if u.RatingCount > 0 {
		parts = append(parts, fmt.Sprintf("рейтинг %.1f · работ: %d", u.Rating, u.RatingCount))
	}
	if u.Verified {
		parts = append(parts, "профиль проверен")
	}
	if len(parts) == 0 {
		parts = append(parts, "исполнитель на Traktor")
	}

	writePage(w, page{
		Title:       u.Name,
		Description: strings.Join(parts, " · "),
		Image:       h.defaultImage,
		URL:         target,
	})
}

func (h *Handler) get(ctx context.Context, url string, v any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	resp, err := h.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("share: %s вернул %d", url, resp.StatusCode)
	}
	return json.NewDecoder(resp.Body).Decode(v)
}

type page struct {
	Title       string
	Description string
	Image       string
	URL         string
}

// writePage отдаёт страницу с og-тегами. Она же сразу уводит человека в
// приложение: бот выполняет только разбор HTML и редирект не делает, а браузер
// уходит по адресу мгновенно.
func writePage(w http.ResponseWriter, p page) {
	e := html.EscapeString
	image := p.Image

	var b strings.Builder
	b.WriteString(`<!doctype html><html lang="ru"><head><meta charset="utf-8">`)
	b.WriteString(`<meta name="viewport" content="width=device-width,initial-scale=1">`)
	fmt.Fprintf(&b, `<title>%s</title>`, e(p.Title))
	fmt.Fprintf(&b, `<meta name="description" content="%s">`, e(p.Description))
	fmt.Fprintf(&b, `<meta property="og:type" content="website">`)
	fmt.Fprintf(&b, `<meta property="og:site_name" content="Traktor">`)
	fmt.Fprintf(&b, `<meta property="og:title" content="%s">`, e(p.Title))
	fmt.Fprintf(&b, `<meta property="og:description" content="%s">`, e(p.Description))
	fmt.Fprintf(&b, `<meta property="og:url" content="%s">`, e(p.URL))
	fmt.Fprintf(&b, `<meta property="og:image" content="%s">`, e(image))
	fmt.Fprintf(&b, `<meta name="twitter:card" content="summary_large_image">`)
	fmt.Fprintf(&b, `<meta name="twitter:title" content="%s">`, e(p.Title))
	fmt.Fprintf(&b, `<meta name="twitter:description" content="%s">`, e(p.Description))
	fmt.Fprintf(&b, `<meta name="twitter:image" content="%s">`, e(image))
	fmt.Fprintf(&b, `<link rel="canonical" href="%s">`, e(p.URL))
	// Редирект — обычной ссылкой и мета-обновлением: скрипты бот не выполняет,
	// а человек без JS всё равно должен попасть в приложение.
	fmt.Fprintf(&b, `<meta http-equiv="refresh" content="0; url=%s">`, e(p.URL))
	b.WriteString(`</head><body>`)
	fmt.Fprintf(&b, `<h1>%s</h1><p>%s</p><p><a href="%s">Открыть в Traktor</a></p>`,
		e(p.Title), e(p.Description), e(p.URL))
	b.WriteString(`</body></html>`)

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	// Превью можно кэшировать недолго: задание живёт часами, а бот
	// мессенджера обращается за ним при каждой пересылке.
	w.Header().Set("Cache-Control", "public, max-age=300")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(b.String()))
}

// cut подрезает описание: мессенджеры всё равно показывают два-три предложения,
// а обрыв на середине слова выглядит неряшливо.
func cut(s string, max int) string {
	s = strings.Join(strings.Fields(s), " ")
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	trimmed := string(r[:max])
	if i := strings.LastIndex(trimmed, " "); i > max/2 {
		trimmed = trimmed[:i]
	}
	return trimmed + "…"
}

// money — сумма в драмах с разделителями разрядов.
func money(v int64) string {
	s := fmt.Sprintf("%d", v)
	var out []byte
	for i, c := range []byte(s) {
		if i > 0 && (len(s)-i)%3 == 0 {
			out = append(out, ' ')
		}
		out = append(out, c)
	}
	return string(out) + " ֏"
}
