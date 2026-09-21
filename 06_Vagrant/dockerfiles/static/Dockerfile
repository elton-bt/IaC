FROM ubuntu:latest
RUN apt update && apt install -y nginx git
RUN git clone https://github.com/elton-bt/simple-abc-site.git /var/www/html/abc
EXPOSE 80
CMD ["/usr/sbin/nginx", "-g", "daemon off;"]
