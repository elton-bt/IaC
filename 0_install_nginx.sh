#!/bin/bash

sudo apt update; 
sudo apt upgrade -y
sudo apt install -y mc nginx nodejs npm
git clone https://github.com/arnab-datta/counter-app.git
cd counter-app
npm install
npm run build
sudo mkdir /var/www/html/counter-app
sudo cp -r build/. /var/www/html/counter-app/