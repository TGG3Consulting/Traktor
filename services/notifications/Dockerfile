# Сборка notifications → distroless (минимальный, без shell, меньше поверхность атаки).
FROM golang:1.24 AS build
WORKDIR /src
COPY go.mod ./
COPY . .
# Прод-сборка с Postgres (в CI доступна сеть для pgx):
#   RUN CGO_ENABLED=0 go build -tags postgres -o /out/notifications ./cmd/notifications
RUN CGO_ENABLED=0 go build -o /out/notifications ./cmd/notifications

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/notifications /notifications
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/notifications"]
