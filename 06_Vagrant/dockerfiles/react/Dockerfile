FROM ubuntu:22.04

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y nginx nodejs npm && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/elton-bt/react-example-app.git

WORKDIR /react-example-app

RUN npm install && \
    npm run build && \
    rm -rf /var/www/html/* && \
    cp -r build/. /var/www/html/

CMD ["nginx", "-g", "daemon off;"]