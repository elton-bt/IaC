FROM nginxinc/nginx-unprivileged:1.31-alpine-slim

LABEL maintainer="elton-bt" description="React Example App served with unprivileged Nginx"

USER root

COPY ./react-example-app /tmp/app

RUN apk add --no-cache --virtual .build-deps nodejs npm && \
    cd /tmp/app && \
    npm install && \
    npm run build && \
    rm -rf /usr/share/nginx/html/* && \
    cp -r /tmp/app/build/. /usr/share/nginx/html/ && \
    chown -R nginx:nginx /usr/share/nginx/html && \
    apk del .build-deps && \
    rm -rf /tmp/app /root/.npm /tmp/* /var/cache/apk/*

EXPOSE 8080

USER nginx

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
