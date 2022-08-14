#!/bin/bash

sudo apt update; 
sudo apt upgrade -y
sudo apt install -y mc nginx nodejs npm
sudo git clone https://github.com/elton-bt/simple-abc-site.git /var/www/html/abc
git clone https://github.com/contentful/the-example-app.nodejs.git
sudo npm install pm2 -g
cd the-example-app.nodejs
sudo npm install
sudo pm2 start "npm run start:dev" app.js
sudo systemctl start nginx


