#!/bin/bash
#Para a execução do script, é necessário divulgar para o servidor a chave pública do seu cliente
#ssh-keygen -t rsa 
#o cliente também deve instalar o sshpass e ter um arquivo senha_servidor no mesmo diretório do script.

echo "Informe o IP o servidor":
read serverIP

echo "Informe o nome do usuário no servidor":
read serverUser

sshpass -f senha_servidor ssh -tt $serverUser@$serverIP '
sudo apt update; 
sudo apt upgrade -y;
sudo apt install -y mc nginx nodejs npm;
sudo git clone https://github.com/elton-bt/simple-abc-site.git /var/www/html/abc;
git clone https://github.com/contentful/the-example-app.nodejs.git;
sudo npm install pm2 -g;
cd the-example-app.nodejs;
sudo npm install;
sudo pm2 start "npm run start:dev" app.js;
sudo systemctl start nginx;
sudo ufw allow ssh;
sudo ufw allow "Nginx Full";
sudo ufw allow 3000;
sudo ufw enable ' 

