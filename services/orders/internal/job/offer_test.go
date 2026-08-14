package job

import (
	"errors"
	"strings"
	"testing"
)

func TestСогласиеСЦенойДолжноСовпадатьСЦенойЗадания(t *testing.T) {
	o := &Offer{Kind: OfferAccept, Price: 100000}

	if err := ValidateOffer(o, 100000); err != nil {
		t.Fatalf("совпадающая цена должна проходить: %v", err)
	}

	o.Price = 90000
	var ve *ValidationError
	if !errors.As(ValidateOffer(o, 100000), &ve) || ve.Fields["price"] == "" {
		t.Fatal("«принимаю цену» с другой суммой — это встречное предложение, а не согласие")
	}
}

func TestВстречноеПредложениеМожетОтличатьсяОтЦены(t *testing.T) {
	o := &Offer{Kind: OfferCounter, Price: 90000, Comment: "Сделаю за два дня"}

	if err := ValidateOffer(o, 100000); err != nil {
		t.Fatalf("встречная цена ниже — нормальный сценарий: %v", err)
	}
}

func TestСлишкомНизкаяЦенаОтклоняется(t *testing.T) {
	o := &Offer{Kind: OfferCounter, Price: 20000}

	var ve *ValidationError
	if !errors.As(ValidateOffer(o, 100000), &ve) || ve.Fields["price"] == "" {
		t.Fatal("цена ниже трети обычно означает недопонимание задачи")
	}
}

func TestДлинныйКомментарийОтклоняется(t *testing.T) {
	o := &Offer{Kind: OfferCounter, Price: 90000, Comment: strings.Repeat("а", 201)}

	var ve *ValidationError
	if !errors.As(ValidateOffer(o, 100000), &ve) || ve.Fields["comment"] == "" {
		t.Fatal("комментарий ограничен 200 символами (ТЗ §2.8)")
	}
}

func TestОткликиТолькоДляОткрытойФиксЦены(t *testing.T) {
	fixed := &Job{Mode: ModeFixed, Status: StatusCollectingOffers}
	if err := CanAcceptOffers(fixed); err != nil {
		t.Fatalf("открытое задание с фикс-ценой принимает отклики: %v", err)
	}

	auction := &Job{Mode: ModeAuction, Status: StatusBidding}
	if !errors.Is(CanAcceptOffers(auction), ErrAuctionMode) {
		t.Fatal("на аукционе делаются ставки, а не отклики")
	}

	closed := &Job{Mode: ModeFixed, Status: StatusCancelled}
	if !errors.Is(CanAcceptOffers(closed), ErrJobNotOpen) {
		t.Fatal("снятое задание откликов не принимает")
	}
}
