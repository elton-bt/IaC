# ==========================================
# ESTÁGIO 1: Build (compilação do binário estático)
# ==========================================
FROM golang:1.26-alpine AS builder

WORKDIR /app

# Cria usuário não-privilegiado para uso na imagem scratch
RUN adduser -D -u 10001 -g '' appuser

# Otimização de cache: copia apenas os manifestos de dependência primeiro
COPY gotodolist/go.mod gotodolist/go.sum ./
RUN go mod download

# Copia o código-fonte do repositório
COPY gotodolist/ ./

# Compilação estática:
# - CGO_ENABLED=0: binário estático puro, sem dependência de libc externa
# - -ldflags="-s -w": remove tabela de símbolos e informações de debug (reduz ~40-50% do tamanho)
# - -trimpath: remove caminhos absolutos do sistema de arquivos do binário
# - ./desacoplado/backend: pacote que contém o package main da API
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /app/server ./desacoplado/backend

# ==========================================
# ESTÁGIO 2: Runtime (imagem scratch - vazia, sem SO)
# ==========================================
FROM scratch AS runner

# Copia certificados TLS (necessário caso a aplicação faça chamadas HTTPS de saída)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copia o usuário não-privilegiado criado no builder
COPY --from=builder /etc/passwd /etc/passwd

# Copia APENAS o binário compilado estático
COPY --from=builder /app/server /server

# Define a execução sob o usuário não-root
USER 10001:10001

# Porta padrão da API desacoplada do gotodolist
EXPOSE 8081

ENTRYPOINT ["/server"]

