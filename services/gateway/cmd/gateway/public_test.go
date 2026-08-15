package main

import "testing"

func TestКакиеПутиЗаданийОткрытыБезВхода(t *testing.T) {
	cases := []struct {
		path string
		want bool
	}{
		{"/v1/jobs", true},  // лента
		{"/v1/jobs/", true}, // лента со слэшем
		{"/v1/jobs/8e2f0f7e-0d2a-4a1e-9c4e-1e8a2f7b0c11", true}, // деталка
		{"/v1/jobs/my", false},     // мои задания
		{"/v1/jobs/drafts", false}, // черновики
		{"/v1/jobs/drafts/8e2f0f7e-0d2a-4a1e-9c4e-1e8a2f7b0c11", false},
		{"/v1/jobs/8e2f0f7e-0d2a-4a1e-9c4e-1e8a2f7b0c11/publish", false},
		{"/v1/jobs/8e2f0f7e-0d2a-4a1e-9c4e-1e8a2f7b0c11/cancel", false},
		{"/v1/jobs/8e2f0f7e-0d2a-4a1e-9c4e-1e8a2f7b0c11/bids", true},     // лента торга
		{"/v1/jobs/8e2f0f7e-0d2a-4a1e-9c4e-1e8a2f7b0c11/bids/my", false}, // своя ставка
		{"/v1/me", false},
	}
	for _, c := range cases {
		if got := publicJobsPath(c.path); got != c.want {
			t.Errorf("%s: получили %v, ожидали %v", c.path, got, c.want)
		}
	}
}
