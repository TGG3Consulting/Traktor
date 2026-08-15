package httpapi

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"traktor/orders/internal/job"
	"traktor/orders/internal/service"
)

type bidBody struct {
	Price   int64   `json:"price"`
	Comment string  `json:"comment"`
	UnitID  *string `json:"unitId"`
}

func (s *Server) placeBid(w http.ResponseWriter, r *http.Request) {
	var body bidBody
	if !decode(w, r, &body) {
		return
	}
	bid, err := s.svc.PlaceBid(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "id"),
		service.BidInput{Price: body.Price, Comment: body.Comment, UnitID: body.UnitID})
	if err != nil {
		failBid(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, bid)
}

// jobBids — лента торга. Открыта всем, кто видит задание: цены публичны,
// имена участников — нет (ТЗ §2.9, защита от сговора).
func (s *Server) jobBids(w http.ResponseWriter, r *http.Request) {
	bids, err := s.svc.JobBids(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		failBid(w, err)
		return
	}

	viewer := r.Header.Get(userHeader)
	items := make([]map[string]any, 0, len(bids))
	for _, b := range bids {
		item := map[string]any{
			"id":        b.ID,
			"price":     b.Price,
			"currency":  b.Currency,
			"status":    b.Status,
			"rank":      b.Rank,
			"createdAt": b.CreatedAt,
			"comment":   b.Comment,
			// Свою ставку исполнитель узнаёт по этому признаку — иначе в
			// анонимной ленте не понять, какая из строк твоя.
			"mine": viewer != "" && b.OwnerID == viewer,
		}
		if b.Score != nil {
			item["score"] = *b.Score
		}
		items = append(items, item)
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) myBidForJob(w http.ResponseWriter, r *http.Request) {
	bid, err := s.svc.MyBidForJob(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "id"))
	if errors.Is(err, job.ErrBidNotFound) {
		writeJSON(w, http.StatusOK, map[string]any{"bid": nil})
		return
	}
	if err != nil {
		failBid(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"bid": bid})
}

func (s *Server) myBids(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	items, err := s.svc.MyBids(r.Context(), r.Header.Get(userHeader), limit, offset)
	if err != nil {
		failBid(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) withdrawBid(w http.ResponseWriter, r *http.Request) {
	bid, err := s.svc.WithdrawBid(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "bidId"))
	if err != nil {
		failBid(w, err)
		return
	}
	writeJSON(w, http.StatusOK, bid)
}

func (s *Server) acceptBid(w http.ResponseWriter, r *http.Request) {
	bid, err := s.svc.AcceptBid(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "bidId"))
	if err != nil {
		failBid(w, err)
		return
	}
	writeJSON(w, http.StatusOK, bid)
}

func (s *Server) declineAllBids(w http.ResponseWriter, r *http.Request) {
	j, err := s.svc.DeclineAllBids(r.Context(), r.Header.Get(userHeader), chi.URLParam(r, "id"))
	if err != nil {
		failBid(w, err)
		return
	}
	writeJSON(w, http.StatusOK, j)
}

// finishAuction — подведение итогов. Обычно вызывается фоновым обработчиком по
// времени финиша; ручной вызов нужен для тестов и разбора инцидентов.
func (s *Server) finishAuction(w http.ResponseWriter, r *http.Request) {
	j, err := s.svc.FinishAuction(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		failBid(w, err)
		return
	}
	writeJSON(w, http.StatusOK, j)
}

func failBid(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, job.ErrBidNotFound):
		problem(w, http.StatusNotFound, "bid_not_found", "ставка не найдена")
	case errors.Is(err, job.ErrNotAuction):
		problem(w, http.StatusConflict, "not_auction", "у задания фиксированная цена — здесь отклик, а не ставка")
	case errors.Is(err, job.ErrAuctionClosed):
		problem(w, http.StatusConflict, "auction_closed", "торг завершён")
	case errors.Is(err, job.ErrBidTooLate):
		problem(w, http.StatusConflict, "too_late", "отозвать ставку можно не позднее чем за 2 часа до финиша")
	case errors.Is(err, job.ErrBidNotActive):
		problem(w, http.StatusConflict, "bid_not_active", "ставка уже неактивна")
	case errors.Is(err, job.ErrOwnJob):
		problem(w, http.StatusForbidden, "own_job", "это ваше задание — ставить нельзя")
	default:
		fail(w, err)
	}
}
