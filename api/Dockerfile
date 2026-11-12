# Multi-arch (amd64 NAS, arm64) static build.
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG TARGETOS TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -o /out/pravdomer-api ./cmd/pravdomer-api

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/pravdomer-api /pravdomer-api
EXPOSE 8096
USER nonroot
ENTRYPOINT ["/pravdomer-api"]
