# Сборка notifications → distroless (минимальный образ, без shell — меньше поверхность атаки).
FROM golang:1.25 AS build
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/notifications ./cmd/notifications

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/notifications /notifications
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/notifications"]
