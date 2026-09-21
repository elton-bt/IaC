# Stage 1 - Build
FROM ubuntu:26.04 AS build-stage

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends nodejs npm && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Aproveita o cache de camadas para as dependências do npm
COPY react-example-app/package.json react-example-app/package-lock.json ./
RUN npm install

# Copia o código-fonte e gera o build estático
COPY react-example-app/ ./
RUN npm run build

# Stage 2 - Production / Runtime
FROM nginxinc/nginx-unprivileged:1.31-alpine-slim

LABEL maintainer="elton-bt" description="React Example App served with unprivileged Nginx (Multistage)"

# Copia apenas os artefatos compilados com permissões do usuário nginx
COPY --from=build-stage --chown=nginx:nginx /app/build/ /usr/share/nginx/html/

EXPOSE 8080

USER nginx

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]