#!/bin/bash
#Para a execução do script, é necessário divulgar para o servidor a chave pública do seu cliente
#ssh-keygen -t rsa 
#o cliente também deverá ter um arquivo de texto contendo os IPs e usuários de cada servidor no formato:
#ip usuario
#ip usuario

echo "Informe o nome do arquivo contendo o IP e nome de usuário do servidor:"":
read serverFile

while read -r serverIP serverUser; do
  echo "Conectando ao servidor $serverIP com o usuário $serverUser..."
  ssh -i private_key $serverUser@$serverIP '
    sudo apt update;
    sudo apt upgrade -y;
    sudo apt install -y mc nginx nodejs npm;
    git clone https://github.com/elton-bt/react-example-app.git;
    cd react-example-app;
    npm install;
    npm run build;
    sudo cp -r build/. /var/www/html/;
    sudo ufw allow ssh;
    sudo ufw allow "Nginx Full";
    sudo ufw allow 80;
    sudo ufw enable;'
  echo "Conexão encerrada."
done < "$serverFile"
