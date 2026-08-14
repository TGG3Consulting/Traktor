// Package proxy — маршрутизация запросов к сервисам по префиксу пути.
package proxy

import (
	"net/http"
	"net/http/httputil"
	"net/url"
	"sort"
	"strings"
)

// Route связывает префикс пути с базовым URL сервиса-апстрима.
type Route struct {
	Prefix   string
	Upstream string
}

// Router строит реверс-прокси по набору маршрутов. Наиболее длинный
// совпадающий префикс выигрывает.
func Router(routes []Route) (http.Handler, error) {
	// Длинные префиксы — раньше.
	sort.Slice(routes, func(i, j int) bool { return len(routes[i].Prefix) > len(routes[j].Prefix) })

	proxies := make([]struct {
		prefix string
		rp     *httputil.ReverseProxy
	}, 0, len(routes))

	for _, rt := range routes {
		u, err := url.Parse(rt.Upstream)
		if err != nil {
			return nil, err
		}
		rp := httputil.NewSingleHostReverseProxy(u)
		// Прокидываем корректные заголовки; хост апстрима.
		orig := rp.Director
		rp.Director = func(req *http.Request) {
			orig(req)
			req.Host = u.Host
		}
		proxies = append(proxies, struct {
			prefix string
			rp     *httputil.ReverseProxy
		}{rt.Prefix, rp})
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		for _, p := range proxies {
			if strings.HasPrefix(r.URL.Path, p.prefix) {
				p.rp.ServeHTTP(w, r)
				return
			}
		}
		http.NotFound(w, r)
	}), nil
}
