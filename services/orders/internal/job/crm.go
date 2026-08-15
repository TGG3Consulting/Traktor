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
