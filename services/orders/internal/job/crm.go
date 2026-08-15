package job

import "time"

// CRM исполнителя — «Мой бизнес» (ТЗ §3.1).
//
// Данные копятся сами из сделок: человек ничего не заполняет руками. Это и
// есть главный смысл встроенного CRM — чем дольше работаешь через площадку,
// тем ценнее твоя история.

// Period — за какой срок считаем сводку.
type Period string

const (
	PeriodWeek    Period = "week"
	PeriodMonth   Period = "month"
	PeriodQuarter Period = "quarter"
	PeriodYear    Period = "year"
	PeriodAll     Period = "all"
)

// Range — границы периода и такой же отрезок перед ним: дельта «+18% к июлю»
// без сравнения не считается.
//
// Обе границы включительны: сделка, закрытая сию секунду, должна попадать в
// «за месяц», а не ждать следующего запроса.
type Range struct {
	From time.Time
	To   time.Time
	// PrevFrom и PrevTo — предыдущий отрезок той же длины.
	PrevFrom time.Time
	PrevTo   time.Time
}

// RangeOf раскрывает период в даты. «Всё время» тоже имеет границы: так
// запросы к базе одинаковые, а сравнивать просто не с чем.
func RangeOf(p Period, now time.Time) Range {
	to := now
	var from time.Time

	switch p {
	case PeriodWeek:
		from = to.AddDate(0, 0, -7)
	case PeriodQuarter:
		from = to.AddDate(0, -3, 0)
	case PeriodYear:
		from = to.AddDate(-1, 0, 0)
	case PeriodAll:
		from = to.AddDate(-100, 0, 0)
	default: // месяц — то, что чаще всего смотрят
		from = to.AddDate(0, -1, 0)
	}

	length := to.Sub(from)
	return Range{
		From: from,
		To:   to,
		// Прошлый отрезок кончается за мгновение до начала текущего: иначе
		// сделка ровно на стыке посчиталась бы дважды.
		PrevFrom: from.Add(-length),
		PrevTo:   from.Add(-time.Nanosecond),
	}
}

// Funnel — воронка исполнителя (ТЗ §3.1): где теряются заказы.
type Funnel struct {
	// Offers — сколько раз откликнулся или поставил ставку.
	Offers int `json:"offers"`
	// Won — сколько раз выбрали.
	Won int `json:"won"`
	// Completed — сколько работ довёл до конца.
	Completed int `json:"completed"`
}

// WinRate — доля выигранных откликов, 0..1. Ноль откликов — ноль, а не
// деление на ноль.
func (f Funnel) WinRate() float64 {
	if f.Offers == 0 {
		return 0
	}
	return float64(f.Won) / float64(f.Offers)
}

// FinishRate — доля доведённых до конца среди выигранных.
func (f Funnel) FinishRate() float64 {
	if f.Won == 0 {
		return 0
	}
	return float64(f.Completed) / float64(f.Won)
}

// Client — строка клиентской базы (ТЗ §3.1).
type Client struct {
	UserID string `json:"userId"`
	Name   string `json:"name,omitempty"`
	Deals  int    `json:"deals"`
	Total  int64  `json:"total"`
	Last   time.Time `json:"last"`
}

// Regular — постоянный клиент: три сделки и больше.
func (c Client) Regular() bool { return c.Deals >= 3 }

// Business — сводка «Мой бизнес» за период.
type Business struct {
	Period   Period `json:"period"`
	Income   int64  `json:"income"`
	Deals    int    `json:"deals"`
	Average  int64  `json:"average"`
	Currency string `json:"currency"`

	// PrevIncome — доход за предыдущий такой же отрезок, для дельты.
	PrevIncome int64 `json:"prevIncome"`

	Funnel  Funnel   `json:"funnel"`
	Clients []Client `json:"clients"`
}

// Delta — изменение дохода к прошлому периоду в процентах. Если раньше дохода
// не было, процент не считается: «+∞%» ничего не объясняет.
func (b Business) Delta() (percent int, comparable bool) {
	if b.PrevIncome <= 0 {
		return 0, false
	}
	diff := float64(b.Income-b.PrevIncome) / float64(b.PrevIncome) * 100
	return int(diff), true
}

// AverageCheck — средний чек за период.
func AverageCheck(income int64, deals int) int64 {
	if deals == 0 {
		return 0
	}
	return income / int64(deals)
}

// Spending — сводка «Мои расходы» заказчика (ТЗ §3.2).
type Spending struct {
	Period   Period `json:"period"`
	Spent    int64  `json:"spent"`
	Deals    int    `json:"deals"`
	Average  int64  `json:"average"`
	Currency string `json:"currency"`

	PrevSpent int64 `json:"prevSpent"`

	// ByCategory — на что уходят деньги: земляные, перевозка, кран.
	ByCategory []CategorySpend `json:"byCategory"`
	// Owners — исполнители, с которыми работал.
	Owners []Client `json:"owners"`
	// Saved — сколько сэкономил аукцион: стартовая цена минус итоговая.
	Saved int64 `json:"saved"`
}

// CategorySpend — расходы по одному виду работ.
type CategorySpend struct {
	CategoryID string `json:"categoryId"`
	Total      int64  `json:"total"`
	Deals      int    `json:"deals"`
}

// Delta — изменение расходов к прошлому периоду.
func (s Spending) Delta() (percent int, comparable bool) {
	if s.PrevSpent <= 0 {
		return 0, false
	}
	diff := float64(s.Spent-s.PrevSpent) / float64(s.PrevSpent) * 100
	return int(diff), true
}

// BusyDay — день, в который исполнитель не работает или уже занят (ТЗ §3.1).
type BusyDay struct {
	Day time.Time `json:"day"`
	// Source: deal — день занят подтверждённой сделкой, manual — человек
	// отметил его сам. Разделение важно: сделку из календаря не убрать,
	// а свою пометку — можно.
	Source string `json:"source"`
	Note   string `json:"note,omitempty"`
	// DealID заполняется у дней, занятых сделкой: по нему открывается сделка.
	DealID string `json:"dealId,omitempty"`
	Title  string `json:"title,omitempty"`
}

const (
	BusySourceDeal   = "deal"
	BusySourceManual = "manual"
)

// SameDay — сравнение по календарному дню, без времени: занятость измеряется
// днями, а не минутами.
func SameDay(a, b time.Time) bool {
	ay, am, ad := a.Date()
	by, bm, bd := b.Date()
	return ay == by && am == bm && ad == bd
}

// DayKey — ключ дня в формате 2006-01-02: по нему календарь ищет отметки.
func DayKey(t time.Time) string { return t.Format("2006-01-02") }

// MonthRange — границы месяца, в котором лежит дата. Календарь всегда
// открывается месяцем целиком.
func MonthRange(at time.Time) (from, to time.Time) {
	from = time.Date(at.Year(), at.Month(), 1, 0, 0, 0, 0, time.UTC)
	to = from.AddDate(0, 1, 0).Add(-time.Nanosecond)
	return from, to
}
