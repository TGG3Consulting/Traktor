package httpapi

import (
	"encoding/json"
	"net/http"
	"testing"
)

// Гостевой просмотр — заявленный сценарий (ТЗ §2.1 «просто посмотреть»), и он
// не должен ронять сервис. Ошибку нашли живой проверкой: гость приходил без
// идентификатора, а счётчик просмотров пытался записать строку «guest» в поле
// с идентификатором пользователя.
func TestГостьВидитЗаданиеИНеЛоматьСчётчик(t *testing.T) {
	h := newAPI()
	draft := decodeJob(t, do(t, h, http.MethodPost, "/v1/jobs/drafts", client, fullDraftBody))
	_ = do(t, h, http.MethodPost, "/v1/jobs/"+draft.ID+"/publish", client, "")

	rec := do(t, h, http.MethodGet, "/v1/jobs/"+draft.ID, "", "")

	if rec.Code != http.StatusOK {
		t.Fatalf("гость должен видеть задание, получили %d (%s)", rec.Code, rec.Body)
	}
	j := decodeJob(t, rec)
	if j.ViewsCount != 0 {
		t.Fatalf("просмотр гостя не считается, получили %d", j.ViewsCount)
	}
}

func TestГостьВидитЛентуТорга(t *testing.T) {
	h := newAPI()
	draft := decodeJob(t, do(t, h, http.MethodPost, "/v1/jobs/drafts", client, fullDraftBody))
	_ = do(t, h, http.MethodPatch, "/v1/jobs/drafts/"+draft.ID, client,
		`{"mode":"auction","auction":{"durationH":24,"decisionWindowH":12}}`)
	_ = do(t, h, http.MethodPost, "/v1/jobs/"+draft.ID+"/publish", client, "")
	_ = do(t, h, http.MethodPost, "/v1/jobs/"+draft.ID+"/bids", owner, `{"price":100000}`)

	rec := do(t, h, http.MethodGet, "/v1/jobs/"+draft.ID+"/bids", "", "")

	if rec.Code != http.StatusOK {
		t.Fatalf("лента торга открыта всем, получили %d", rec.Code)
	}
	var body struct {
		Items []map[string]any `json:"items"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if len(body.Items) != 1 {
		t.Fatalf("ожидали одну ставку, получили %d", len(body.Items))
	}
	if _, has := body.Items[0]["ownerId"]; has {
		t.Fatal("имена участников торга не раскрываются (ТЗ §2.9)")
	}
}
