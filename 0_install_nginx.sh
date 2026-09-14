#!/bin/bash

sudo apt update
sudo apt upgrade -y
sudo apt install -y mc nginx nodejs npm

# Clona o repositório correto
git clone https://github.com/elton-bt/react-example-app.git
cd react-example-app

# Instala dependências e gera os estáticos de produção
npm install
npm run build

# Limpa a pasta padrão do Nginx e copia os arquivos compilados
sudo rm -rf /var/www/html/*
sudo cp -r build/. /var/www/html/

# Configura o Nginx para redirecionar rotas SPA para o index.html
sudo sed -i 's/try_files \$uri \$uri\/ =404;/try_files \$uri \$uri\/ \/index.html;/' /etc/nginx/sites-available/default

# Valida e recarrega a configuração do Nginx
sudo nginx -t && sudo systemctl reload nginx