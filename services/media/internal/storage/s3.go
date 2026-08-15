// Package storage — доступ к S3-совместимому хранилищу фотографий.
//
// Клиент грузит файл напрямую в хранилище по временной ссылке (presigned PUT),
// минуя наш бэкенд: фотографии техники и заданий весят мегабайты, и пропускать
// их через сервис — лишний трафик и лишняя точка отказа (ADR-5).
package storage

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"path"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// UploadLink — всё, что нужно клиенту для загрузки одного файла.
type UploadLink struct {
	// Key — путь внутри бакета, по нему файл потом находится.
	Key string `json:"key"`
	// UploadURL — временная ссылка для PUT.
	UploadURL string `json:"uploadUrl"`
	// PublicURL — постоянный адрес, который сохраняется в карточке.
	PublicURL string `json:"publicUrl"`
	// ExpiresIn — сколько секунд ссылка действительна.
	ExpiresIn int `json:"expiresIn"`
}

// S3 — хранилище на minio-go (работает и с MinIO, и с Cloudflare R2).
type S3 struct {
	client    *minio.Client
	bucket    string
	publicURL string
	ttl       time.Duration
}

var ErrUnsupportedType = errors.New("media: такой тип файла не принимаем")

// allowed — что разрешено грузить. Список закрытый: хранилище не должно
// превращаться в свалку произвольных файлов.
var allowed = map[string]string{
	"image/jpeg": ".jpg",
	"image/png":  ".png",
	"image/webp": ".webp",
	"image/heic": ".heic",
	"application/pdf": ".pdf",
}

func New(endpoint, accessKey, secretKey, bucket, publicURL string, useSSL bool) (*S3, error) {
	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
		Secure: useSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("media: подключение к хранилищу: %w", err)
	}
	return &S3{
		client:    client,
		bucket:    bucket,
		publicURL: strings.TrimRight(publicURL, "/"),
		// Пятнадцати минут хватает на загрузку с мобильного интернета и мало
		// для того, чтобы утёкшая ссылка кому-то пригодилась.
		ttl: 15 * time.Minute,
	}, nil
}

// Link выдаёт ссылку на загрузку. Имя файла придумывает сервер: клиентское имя
// может содержать что угодно, вплоть до путей с «..».
func (s *S3) Link(ctx context.Context, ownerID, folder, contentType string) (*UploadLink, error) {
	ext, ok := allowed[strings.ToLower(strings.TrimSpace(contentType))]
	if !ok {
		return nil, ErrUnsupportedType
	}
	if folder == "" {
		folder = "misc"
	}

	key := path.Join(cleanSegment(folder), cleanSegment(ownerID), uuid.NewString()+ext)
	u, err := s.client.PresignedPutObject(ctx, s.bucket, key, s.ttl)
	if err != nil {
		return nil, fmt.Errorf("media: ссылка на загрузку: %w", err)
	}

	return &UploadLink{
		Key:       key,
		UploadURL: u.String(),
		PublicURL: s.publicURL + "/" + key,
		ExpiresIn: int(s.ttl.Seconds()),
	}, nil
}

// Ready проверяет, что бакет на месте: без него загрузка молча ломается на
// стороне клиента, а причина будет видна только в логах хранилища.
func (s *S3) Ready(ctx context.Context) error {
	ok, err := s.client.BucketExists(ctx, s.bucket)
	if err != nil {
		return err
	}
	if !ok {
		return fmt.Errorf("media: бакета %q нет", s.bucket)
	}
	return nil
}

// cleanSegment оставляет от сегмента пути только безопасные символы.
func cleanSegment(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	var b strings.Builder
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9', r == '-', r == '_':
			b.WriteRune(r)
		}
	}
	if b.Len() == 0 {
		return "misc"
	}
	return url.PathEscape(b.String())
}
