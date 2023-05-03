FROM ubuntu:22.04
RUN apt update && apt install -y mc nginx git
RUN git clone https://github.com/elton-bt/simple-abc-site.git /var/www/html/abc
EXPOSE 80
CMD ["/usr/sbin/nginx", "-g", "daemon off;"]
