package httpapi

import (
	"encoding/csv"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"traktor/orders/internal/job"
	"traktor/orders/internal/profiles"
)

// Выгрузка сделок за период (ТЗ §3.1 п.7, §3.2 п.6).
//
// Формат — CSV с разделителем «точка с запятой» и меткой BOM: Excel на
// русской и армянской раскладке открывает такой файл двойным щелчком и не
// ломает кириллицу. Полноценный XLSX добавим, если понадобятся формулы и
// оформление; для налоговой и бухгалтерии достаточно таблицы.

// exportDeals — GET /v1/crm/export?period=year&role=owner|client.
func (s *Server) exportDeals(w http.ResponseWriter, r *http.Request) {
	me := r.Header.Get(userHeader)

	period := job.Period(r.URL.Query().Get("period"))
	switch period {
	case job.PeriodWeek, job.PeriodMonth, job.PeriodQuarter, job.PeriodYear, job.PeriodAll:
	default:
		period = job.PeriodYear // отчёт чаще всего нужен за год
	}
	asOwner := r.URL.Query().Get("role") != "client"

	deals, err := s.svc.DealsForExport(r.Context(), me, period, asOwner)
	if err != nil {
		fail(w, err)
		return
	}

	// Имена второй стороны: в отчёте «Карен Саркисян» полезнее строки с
	// идентификатором.
	ids := make([]string, 0, len(deals))
	for _, d := range deals {
		if asOwner {
			ids = append(ids, d.ClientID)
		} else {
			ids = append(ids, d.OwnerID)
		}
	}
	people := s.svc.Profiles(r.Context(), ids)

	filename := fmt.Sprintf("traktor-%s-%s.csv", period, time.Now().Format("2006-01-02"))
	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="`+filename+`"`)

	// BOM: без него Excel открывает файл в системной кодировке и показывает
	// вместо русских букв мусор.
	_, _ = w.Write([]byte{0xEF, 0xBB, 0xBF})

	cw := csv.NewWriter(w)
	cw.Comma = ';'
	defer cw.Flush()

	side := "Заказчик"
	if !asOwner {
		side = "Исполнитель"
	}
	_ = cw.Write([]string{"Дата", "Задание", side, "Сумма", "Валюта", "Статус"})

	for _, d := range deals {
		other := d.ClientID
		if !asOwner {
			other = d.OwnerID
		}
		day := d.CreatedAt
		if d.ClosedAt != nil {
			day = *d.ClosedAt
		}
		_ = cw.Write([]string{
			day.Format("02.01.2006"),
			d.JobTitle,
			profiles.DisplayName(people[other], "—"),
			strconv.FormatInt(d.Price, 10),
			d.Currency,
			statusRU(d.Status),
		})
	}
}

// statusRU — статус по-человечески: отчёт читает бухгалтер, а не разработчик.
func statusRU(s job.DealStatus) string {
	switch s {
	case job.DealCompleted:
		return "завершена"
	case job.DealCancelled:
		return "отменена"
	case job.DealDisputed:
		return "спор"
	case job.DealWorkDone:
		return "ждёт приёмки"
	case job.DealInProgress:
		return "в работе"
	case job.DealOnTheWay:
		return "исполнитель выехал"
	default:
		return "подтверждена"
	}
}
