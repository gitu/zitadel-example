# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o sample-app .

# Final stage
FROM alpine:3.20

RUN apk --no-cache add ca-certificates

WORKDIR /app

# Copy the binary and templates from builder
COPY --from=builder /app/sample-app .

EXPOSE 8090

CMD ["./sample-app"]