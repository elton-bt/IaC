#!/bin/bash

sudo apt update; 
sudo apt upgrade -y
sudo apt install -y mc nginx nodejs npm
git clone https://github.com/elton-bt/react-example-app.git
cd react-example-app
npm install
npm run build
sudo cp -r build/. /var/www/html/