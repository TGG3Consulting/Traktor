package job

import "time"

// PlatformStats — сводка по площадке (ТЗ §4.1, п.1).
//
// Без неё владелец узнаёт о проблеме от людей, которые уже ушли: заданий стало
// меньше, сделок не стало вовсе, а в очереди модерации копится. Здесь всё это
// видно одним экраном.
type PlatformStats struct {
	From time.Time `json:"from"`
	To   time.Time `json:"to"`

	// Jobs — опубликованные задания за период.
	Jobs int `json:"jobs"`
	// Deals — сколько из них дошло до сделки.
	Deals int `json:"deals"`
	// Completed — сделки, закрытые как выполненные.
	Completed int `json:"completed"`
	// GMV — оборот по завершённым сделкам, в драмах.
	GMV int64 `json:"gmv"`

	// Очереди модерации: их длина — сигнал, что реагировать нужно сегодня.
	OpenDisputes   int `json:"openDisputes"`
	OpenComplaints int `json:"openComplaints"`

	// Users — регистрации за период. Считает identity, orders о людях не знает
	// (правило 12: cross-schema JOIN запрещён).
	Users int `json:"users"`
}

// Conversion — доля заданий, дошедших до сделки, в процентах.
//
// Это главная цифра площадки: задания без откликов означают, что исполнителей
// в категории или районе нет, и заказчик не вернётся.
func (s PlatformStats) Conversion() int {
	if s.Jobs == 0 {
		return 0
	}
	return int(float64(s.Deals) / float64(s.Jobs) * 100)
}

// AvgCheck — средний чек по завершённым сделкам.
func (s PlatformStats) AvgCheck() int64 {
	if s.Completed == 0 {
		return 0
	}
	return s.GMV / int64(s.Completed)
}
