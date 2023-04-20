# Stage 1 - Build
FROM ubuntu:22.04 as build-stage

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y mc nginx nodejs npm && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/elton-bt/react-example-app.git

WORKDIR /react-example-app

RUN npm install && \
    npm run build

# Stage 2 - Production
FROM nginx:latest

RUN rm -rf /usr/share/nginx/html/*

COPY --from=build-stage /react-example-app/build/ /usr/share/nginx/html/

CMD ["nginx", "-g", "daemon off;"]