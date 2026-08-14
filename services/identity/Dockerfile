# Сборка identity → distroless (минимальный образ, без shell — меньше поверхность атаки).
FROM golang:1.25 AS build
WORKDIR /src

# Слой зависимостей кэшируется отдельно: правка кода не приводит к повторной
# загрузке модулей.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/identity ./cmd/identity

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/identity /identity
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/identity"]
