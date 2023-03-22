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
sudo apt upgrade -y
sudo apt install -y mc nginx nodejs npm
git clone https://github.com/arnab-datta/counter-app.git
cd counter-app
npm install
npm run build
sudo mkdir /var/www/html/counter-app
sudo cp -r build/. /var/www/html/counter-app/
sudo ufw allow ssh;
sudo ufw allow "Nginx Full";
sudo ufw allow 80;
sudo ufw enable ' 

