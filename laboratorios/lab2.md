# Laboratório 2 — Diagnosticando e Corrigindo Erros de Rede Reais

**Disciplina:** Infraestrutura de TI para Sistemas na Internet<br>
**Aula de referência:** Aula 02<br>
**Projeto sugerido para uso:** [`gotodolist`](https://github.com/elton-bt/gotodolist), variante **`desacoplado`** (frontend + API separados — é a única variante com CORS)<br>
**Objetivo:** provocar os erros, reconhecê-lo em diferentes ferramentas e corrigi-los.

---


## Como usar a LLM neste laboratório (leia isso primeiro)

Vocês vão ter a tentação de colar o erro numa LLM e simplesmente aplicar o que ela mandar. **Não façam isso.** Usem este protocolo de 4 passos, que é a maneira correta como engenheiro para usar uma LLM no trabalho real:

1. **Cole o erro EXATO** (a mensagem completa, sem parafrasear) + o contexto: o que você estava tentando fazer, qual comando rodou, o que esperava que acontecesse.
2. **Peça duas coisas específicas à LLM:** (a) qual é a causa mais provável, e (b) **um comando que você mesmo possa rodar para confirmar essa hipótese** antes de aceitar a explicação.
3. **Rode o comando sugerido você mesmo** e compare o resultado com o que a LLM previu. Se não bateu, volte à LLM com o resultado real ("rodei X, o resultado foi Y, isso bate com sua hipótese?") em vez de aceitar a primeira resposta.
4. **Só aplique a correção depois de confirmar a causa com evidência real** — e teste se ela realmente resolveu (rode o comando de diagnóstico de novo), não só "parece que sim".

Uma LLM que só te dá a resposta pronta sem te ensinar a confirmá-la não está te ensinando infraestrutura — está só terceirizando o problema. O objetivo aqui é sair sabendo **diagnosticar** alguns erro de rede, não só ter decorado a correção destes 9 casos específicos.

---

## Preparação do Ambiente (compartilhada — fazer uma vez, ~15 min)

Todos os cenários abaixo usam a mesma base: banco de dados em container (tratado como caixa-preta — veremos sobre Docker posteriormente), API Go rodando direto com `go run`, e frontend estático servido com `python3 -m http.server`.

### 1. Subir uma VM 

```bash
git clone https://github.com/elton-bt/IaC
cd 06_Vagrant/
vagrant up
vagrant ssh
```

### 2. Clonar o repositório

```bash
git clone https://github.com/elton-bt/gotodolist.git
cd gotodolist
```

### 3. Subir o PostgreSQL

```bash
docker run -d --name gotodolist-db \
  -p 5432:5432 \
  -e POSTGRES_USER=gotodolist \
  -e POSTGRES_PASSWORD=umasenhaqualquer \
  -e POSTGRES_DB=gotodolist \
  postgres:17-alpine
```

### 4. Subir a API (terminal 1)

```bash
export APP_PORT=8081
export DB_HOST=127.0.0.1
export DB_PORT=5432
export DB_NAME=gotodolist
export DB_USER=gotodolist
export DB_PASSWORD=umasenhaqualquer
export DB_SSLMODE=disable
export CORS_ALLOW_ORIGIN='*'

go run ./desacoplado/backend
```

Deixe este terminal aberto — é nele que vocês vão dar Ctrl+C e reiniciar o processo várias vezes ao longo do laboratório.

### 5. Servir o frontend (terminal 2)

```bash
cd gotodolist/desacoplado/frontend
python3 -m http.server 8082
```

### 5. Checklist do ambiente (confirme ANTES de quebrar qualquer coisa).

- [ ] Abrir `http://ipdavm:8082` no navegador.
- [ ] O card "saúde da api" mostra `ok`.
- [ ] Criar uma tarefa de teste pelo formulário e ver ela aparecer na lista.
- [ ] Do terminal da sua máquina real digite `curl -I http://ipdavm:8081/health` retorna `HTTP/1.1 200 OK`.

Se algum desses passos falhar, **pare e resolva antes de continuar** — os cenários a seguir partem do princípio de que o ambiente está saudável no início de cada um.

---

## Cenário 1 — `ECONNREFUSED` / "Connection refused"

### Causa raiz
Nada está escutando naquela porta — ou porque o processo caiu, ou porque nunca foi iniciado. O sistema operacional do lado do servidor responde com um pacote TCP `RST` (reset), dizendo "não tem ninguém aqui".

### Parte A — o backend caiu

1. Com tudo funcionando, confirme o "antes":
   ```bash
   curl -I http://localhost:8081/health
   ```
   Deve retornar `200 OK`.

2. Vá ao terminal 1 (onde a API está rodando) e derrube o processo com `Ctrl+C`.

3. Rode o mesmo `curl` de novo:
   ```bash
   curl -I http://localhost:8081/health
   ```
   Resultado esperado: `curl: (7) Failed to connect to localhost port 8081 ... Connection refused`.

4. Confirme com uma segunda ferramenta, usando só o bash na VM:
   ```bash
   cat < /dev/tcp/127.0.0.1/8081
   ```
   Resultado esperado: `bash: connect: Connection refused` — quase instantâneo.

5. Vá ao navegador (frontend ainda aberto em `8082`) e recarregue a página. Abra o DevTools (F12) → aba **Console**: deve aparecer algo como `Failed to fetch`. Na aba **Network**, clique na requisição para `/health` — o status aparece como *failed*, e passando o mouse sobre ela o Chrome mostra `net::ERR_CONNECTION_REFUSED`.

⚠️ **Atenção — o navegador pode "mascarar" isto como se fosse erro de CORS.** O frontend (`8082`) e a API (`8081`) são origens diferentes, e o `apiRequest` do frontend manda `Content-Type: application/json` em toda chamada — logo, toda requisição para a API é cross-origin *e* passa por preflight (`OPTIONS`). Quando a conexão falha antes de qualquer resposta chegar (nosso caso aqui), o texto exato que aparece **depende do navegador**:
   - **Chrome:** Console mostra `Failed to fetch`; na aba **Network**, passando o mouse sobre a requisição falha, aparece `net::ERR_CONNECTION_REFUSED`.
   - **Firefox:** Console mostra algo como *"Requisição cross-origin bloqueada: A diretiva Same Origin (mesma origem) não permite a leitura do recurso remoto em `http://.../health` (motivo: falha na requisição CORS)"*, e na aba **Rede** a requisição `OPTIONS` aparece com status **CORS Failed**. Apesar do texto citar CORS, a causa real é a mesma conexão recusada dos passos 3 e 4 — o Firefox relata *qualquer* falha de requisição cross-origin através do mesmo aviso, mesmo quando não é um problema de CORS de verdade.

6. **Corrigir:** volte ao terminal 1 e suba a API de novo (reexporte as variáveis se o terminal foi fechado, ou apenas rode de novo se ainda estão no ambiente):
   ```bash
   go run ./desacoplado/backend
   ```
   Confirme com `curl -I http://localhost:8081/health` → `200 OK` de novo.

### Parte B — o banco caiu (a API não sobe)

Esta variante é mais sutil: o `gotodolist` **sanitiza de propósito** os erros de conexão com o banco (decisão de segurança documentada no próprio projeto) — então o log da aplicação não mostra o motivo real. Vocês vão precisar investigar por fora.

1. Pare a API (`Ctrl+C` no terminal 1, se ainda estiver rodando).
2. Pare o banco:
   ```bash
   docker stop gotodolist-db
   ```
3. Tente subir a API de novo:
   ```bash
   go run ./desacoplado/backend
   ```
   Resultado esperado: uma linha de log parecida com `level=ERROR msg="banco indisponivel"` e o processo encerra sozinho (`exit status 1`). **Note que não aparece nenhum detalhe do erro real** — isso é proposital.
4. Para ver a causa real, investigue a porta do banco diretamente:
   ```bash
   cat < /dev/tcp/127.0.0.1/5432
   ```
   Resultado esperado: `bash: connect: Connection refused` — a mesma assinatura da Parte A, só que em outra porta.
5. **Corrigir:**
   ```bash
   docker start gotodolist-db
   ```
   Espere alguns segundos (o Postgres demora um pouco para aceitar conexões depois de iniciar) e tente de novo:
   ```bash
   go run ./desacoplado/backend
   ```

### Tabela de comparação — mesmo erro, ferramentas diferentes

| Ferramenta | Texto exato observado |
| :--- | :--- |
| `curl` | `curl: (7) Failed to connect to <host> port <porta> ... Connection refused` |
| `bash` (`/dev/tcp`) | `bash: connect: Connection refused` |
| Navegador — Chrome (Network tab) | `net::ERR_CONNECTION_REFUSED` |
| Navegador — Chrome (Console/JS) | `Failed to fetch` (genérico — o JS não sabe o motivo exato, só que falhou) |
| Navegador — Firefox (Rede) | `CORS Failed` na requisição `OPTIONS` |
| Navegador — Firefox (Console) | `Requisição cross-origin bloqueada ... (motivo: falha na requisição CORS)` — **texto cita CORS, mas a causa real é conexão recusada** |
| Node.js (se tiver instalado) | `Error: connect ECONNREFUSED 127.0.0.1:8081` |

---

## Cenário 2 — DNS: "Host not found" / "Could not resolve host" / `ENOTFOUND` / `ERR_NAME_NOT_RESOLVED`

### Causa raiz
**Estas quatro expressões são o mesmo erro** — falha de resolução de nome (DNS) — só que cada ferramenta escreve isso com palavras diferentes.

### Como provocar

1. Com o ambiente saudável (backend rodando, etc), edite `desacoplado/frontend/config.js`:

   Antes:
   ```js
   window.GOTODOLIST_CONFIG = {
     apiBase: "",
     version: "dev",
   };
   ```

   Depois:
   ```js
   window.GOTODOLIST_CONFIG = {
     apiBase: "http://api-fantasma.local:8081",
     version: "dev",
   };
   ```

2. Recarregue `http://localhost:8082` no navegador.

### Como observar o erro (compare as 4 ferramentas)

| Ferramenta | Comando | Texto exato observado |
| :--- | :--- | :--- |
| Navegador (Network tab) | recarregar a página | `net::ERR_NAME_NOT_RESOLVED` |
| Navegador (Console/JS) | — | `Failed to fetch` (de novo genérico!) |
| `curl` | `curl http://api-fantasma.local:8081/health` | `curl: (6) Could not resolve host: api-fantasma.local` |
| `ping` | `ping -c 1 api-fantasma.local` | `ping: api-fantasma.local: Name or service not known` |
| `dig` | `dig api-fantasma.local +short` | (resposta vazia — o domínio não existe) |
| Node.js (opcional) | `node -e "fetch('http://api-fantasma.local:8081/health').catch(e=>console.error(e))"` | `... cause: Error: getaddrinfo ENOTFOUND api-fantasma.local` |

> 💡 Reparem: o Console do navegador mostra `Failed to fetch` tanto aqui quanto no Cenário 1 (ECONNREFUSED). O JavaScript, por segurança, não expõe o motivo exato de uma falha de rede para o código da página — só quem investiga na aba **Network** ou no terminal descobre se foi DNS, conexão recusada, timeout, etc.

⚠️ Assim como no Cenário 1, o **Firefox** tende a relatar isso também como bloqueio de CORS (por ser uma requisição cross-origin com preflight que falhou), em vez do `net::ERR_NAME_NOT_RESOLVED` mais específico do Chrome. O `curl`/`dig`/`ping` continuam sendo a fonte confiável, independente do navegador.

### Como corrigir

**Opção 1 — reverter a configuração** (o mais direto):
```js
window.GOTODOLIST_CONFIG = {
  apiBase: "",
  version: "dev",
};
```

**Opção 2 — resolver via `/etc/hosts`**: mantenha o `config.js` apontando para `api-fantasma.local` e adicione uma entrada local na sua máquina real:
```bash
echo "ip_da_vm  api-fantasma.local" | sudo tee -a /etc/hosts
```
Recarregue a página — volta a funcionar, porque agora existe uma resposta *local* para esse nome, sem precisar de DNS real. Isso confirma que o problema era **só** de resolução de nome: assim que o nome resolve para algum lugar (mesmo que seja um arquivo local), o resto do fluxo continua normalmente.

Não esqueça de reverter (`sudo sed -i '/api-fantasma.local/d' /etc/hosts`) ao final, para não deixar lixo na máquina.

---

## Cenário 3 — CORS quebrado + correção simples

### Causa raiz
CORS é uma regra que o **navegador** aplica, não o backend. Quando o JavaScript de uma página em `http://localhost:8082` tenta chamar `http://localhost:8081` (porta diferente = origem diferente), o navegador só entrega a resposta ao código da página se o servidor disser explicitamente, no header `Access-Control-Allow-Origin`, que aquela origem é permitida.

O `gotodolist` já vem com uma variável de ambiente pronta pra isso: `CORS_ALLOW_ORIGIN` (padrão `*`, ou seja, "libera geral"). O middleware (`withCORS`, em `desacoplado/backend/server.go`) coloca esse valor no header de **toda** resposta, inclusive nas requisições de "pré-checagem" (`OPTIONS`, chamadas de *preflight*) que o navegador dispara antes de qualquer chamada com `Content-Type: application/json` — e o frontend deste projeto manda esse header em **toda** chamada, até em `GET`. Ou seja: um `CORS_ALLOW_ORIGIN` errado quebra a página **assim que ela carrega**, sem precisar clicar em nada.

### Como provocar

1. Confirme que está tudo funcionando com o padrão (`CORS_ALLOW_ORIGIN=*`).
2. No terminal 1, `Ctrl+C` na API, depois:
   ```bash
   export CORS_ALLOW_ORIGIN='http://localhost:4000'
   go run ./desacoplado/backend
   ```
   (`4000` é uma porta que **não é** a do nosso frontend — de propósito.)
3. Recarregue `http://localhost:8082`.

### Como observar

- A página para de funcionar: o card de saúde fica em estado de erro, a lista de tarefas não carrega.
- Abra o DevTools → **Console**. A mensagem é parecida com:
  > *Requisição cross-origin bloqueada: A diretiva Same Origin (mesma origem) não permite a leitura do recurso remoto em http://192.168.10.143:8081/api/tasks (motivo: cabeçalho 'Access-Control-Allow-Origin' do CORS não corresponde a 'http://localhost:4000')*
- Na aba **Network**, clique na requisição: repare que ela teve uma resposta HTTP normal (às vezes até `200`) — **o servidor respondeu perfeitamente**. O bloqueio acontece só no navegador, depois da resposta chegar. Isso é uma pegadinha comum: "mas o Postman/curl funciona!" — funciona mesmo, porque CORS só existe em navegadores.
  ```bash
  curl -i http://ip-da-vm:8081/health
  ```
  Repare no header `Access-Control-Allow-Origin: http://localhost:4000` na resposta — o curl não se importa com isso, só o navegador aplica a regra.

### ⚠️ Anti-padrão (não façam isso)
Não "resolvam" isso desabilitando a segurança do navegador (`--disable-web-security`) ou instalando uma extensão tipo "Allow CORS". Isso só engana o **seu** navegador — qualquer usuário real da aplicação continua bloqueado. Vocês estariam escondendo o sintoma, não corrigindo a causa.

### Como corrigir sem liberar para toda origem ('*') :

```bash
# Ctrl+C no terminal da API, depois:
export CORS_ALLOW_ORIGIN='http://ip-da-vm:8082'
go run ./desacoplado/backend
```

Recarregue a página e confirme que voltou a funcionar e agora sem liberar para qualquer origem — só a do frontend.

---

## Instalando o Caddy - proxy reverso com HTTPS automático

Vamos instalar o [Caddy](https://caddyserver.com/), um servidor web/proxy reverso que faz gestão de certificados HTTPS automaticamente.

### Instalação na VM (Ubuntu 26.04)

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
sudo chmod o+r /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

Isso instala o Caddy como um serviço `systemd`. Para este laboratório, porém, é mais prático **não** usar o serviço systemd, e sim rodar o Caddy manualmente em foreground — assim vemos os logs ao vivo no terminal e paramos com `Ctrl+C` quando quisermos.

```bash
sudo systemctl stop caddy
sudo systemctl disable caddy
```

> 💻 **Alternativa sem `apt` (ex.: WSL2 sem systemd habilitado):** baixe o binário estático em [caddyserver.com/download](https://caddyserver.com/download) (escolha `linux`/`amd64`, sem módulos extras), dê permissão de execução (`chmod +x caddy`) e use `./caddy run --config Caddyfile` do mesmo jeito que os exemplos abaixo.

---

## Cenário 4 — 502 Bad Gateway

### Causa raiz
Um proxy reverso (Caddy, Nginx, etc.) está no ar, mas o serviço para o qual ele encaminha as requisições (o *upstream*) não responde. O proxy tenta se conectar ao backend, recebe a mesma recusa de conexão do Cenário 1, e **traduz isso em uma resposta HTTP 502** para quem pediu a página.

### Como provocar

1. Crie um arquivo `Caddyfile-502` na raiz do projeto:
   ```caddyfile
   :9090 {
       reverse_proxy localhost:8081
   }
   ```
2. Garanta que a API está rodando em `8081` (terminal 1).
3. Em um novo terminal, rode o Caddy em foreground:
   ```bash
   caddy run --config Caddyfile-502 --adapter caddyfile
   ```
4. Teste o proxy funcionando:
   ```bash
   curl -I http://ip-da-vm:9090/health
   ```
   Deve retornar `200 OK` — a requisição passou pelo Caddy e chegou até a API.
5. Agora derrube a API (`Ctrl+C` no terminal 1).
6. Teste de novo:
   ```bash
   curl -i http://ip-da-vm:9090/health
   ```
   Resultado esperado: `HTTP/1.1 502 Bad Gateway`.

### Como observar

Olhe o terminal onde o Caddy está rodando (o log estruturado aparece ao vivo). Deve aparecer uma entrada de erro mencionando algo como `ERROR   http.log.error dial tcp 127.0.0.1:8081: connect: connection refused`.

> 💡 **O ponto central deste cenário:** o `ECONNREFUSED` do Cenário 1 não desapareceu — ele só **migrou**. Agora é o Caddy, no papel de cliente da API, que recebe a recusa de conexão, e ele a traduz numa resposta HTTP (502) para quem pediu a página no navegador. Um erro de rede na camada de transporte virou um código de status HTTP na camada de aplicação.

### Como corrigir

```bash
# no terminal 1:
go run ./desacoplado/backend
```

Confirme:
```bash
curl -I http://ip-da-vm:9090/health
```
Deve voltar a `200 OK`.

**Deixe o Caddy rodando** (`Ctrl+C` só depois do Cenário 5).

### Consultando a LLM:
Peça para a LLM comparar 502 (Bad Gateway) com 503 (Service Unavailable) e 504 (Gateway Timeout) — e depois confirmem qual desses o `/health` da própria API retorna quando o banco cai.

⚠️ Dê um print da consulta via curl do resultado do `/health` com o banco parado, vocês vão precisar enviar para o classroom.
---

## Cenário 5 — CORS corrigido via Caddy (sem tocar no backend)

### Causa raiz / motivação
No Cenário 3, corrigimos o CORS ajustando a variável de ambiente do próprio backend. Mas e se você **não pudesse** mexer no backend (ex.: é um serviço de terceiros, ou uma equipe diferente cuida dele, ou a mudança demoraria dias para ser aprovada)? Um proxy reverso na frente pode reescrever o header de resposta antes que ele chegue ao navegador.

### Como provocar (deixar o backend "errado" de propósito)

```bash
# Ctrl+C no terminal 1, depois:
export CORS_ALLOW_ORIGIN='http://ip-da-vm:4000'
go run ./desacoplado/backend
```

### Como corrigir via Caddy

1. Crie um segundo arquivo, `Caddyfile-cors-fix`:
   ```caddyfile
   :9091 {
       reverse_proxy ip-da-vm:8081
       header >Access-Control-Allow-Origin "http://ip-da-vm:8082"
   }
   ```
   O prefixo `>` é importante: ele faz o Caddy **adiar** a escrita desse header até o momento de enviar a resposta ao cliente, garantindo que ele prevaleça sobre o valor que o `reverse_proxy` já copiou do backend (sem o `>`, a ordem interna de execução do Caddy poderia aplicar o `header` antes do proxy rodar, e o valor errado do backend sobrescreveria o seu).

2. Em outro terminal, suba esse segundo Caddy (mantenha o do Cenário 4 rodando também, se quiser):
   ```bash
   caddy run --config Caddyfile-cors-fix --adapter caddyfile
   ```

3. Edite `desacoplado/frontend/config.js` para apontar para o Caddy, não direto para a API:
   ```js
   window.GOTODOLIST_CONFIG = {
     apiBase: "http://ip-da-vm:9091",
     version: "dev",
   };
   ```

4. Recarregue `http://localhost:8082`. Deve funcionar — mesmo com o backend ainda "errado".

### Como confirmar que foi o Caddy que corrigiu (e não algum acaso)

```bash
# Direto na API (ainda "errada"):
curl -i http://ip-da-vm:8081/health | grep -i access-control-allow-origin
# Deve mostrar: Access-Control-Allow-Origin: http://ip-da-vm:4000  (o valor errado)

# Através do Caddy (corrigido):
curl -i http://ip-da-vm:9091/health | grep -i access-control-allow-origin
# Deve mostrar: Access-Control-Allow-Origin: http://ip-da-vm:8082  (o valor certo)
```

### Fechamento
Reverta o `config.js` para `apiBase: ""` e o backend para `CORS_ALLOW_ORIGIN='*'` (ou `http://ip-da-vm:8082`) antes de seguir em frente, para não carregar configuração de teste para os próximos cenários.

---

## Cenário 6 — `ETIMEDOUT` (trava sem resposta nenhuma)

### Causa raiz
Diferente do `ECONNREFUSED` (o servidor responde ativamente "não tem ninguém aqui"), o `ETIMEDOUT` acontece quando os pacotes **somem no caminho** — nenhuma resposta chega, nem positiva nem negativa. O cliente fica esperando até o próprio timeout dele (do sistema operacional, ou configurado pela aplicação) desistir. Isso normalmente acontece quando um firewall está configurado para **descartar** pacotes silenciosamente (`DROP`) em vez de recusá-los explicitamente (`REJECT`).

> 🔒 **REJECT vs DROP, a diferença que importa aqui:** `REJECT` manda de volta um "não" explícito (é o que gera `ECONNREFUSED`, instantâneo). `DROP` finge que o pacote nunca chegou (é o que gera `ETIMEDOUT`, demorado). Muitos firewalls de produção preferem `DROP` por segurança — um atacante escaneando portas não consegue nem saber se existe algo ali ou não, porque tudo demora igual.

### Como provocar (com `iptables`)

1. Confirme o "antes" (SEM a regra de firewall ainda), comparando com o Cenário 1:
   ```bash
      timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/5432 && echo CONECTOU'
   ```
   Deve mostrar `CONECTOU` quase instantaneamente (o Postgres está escutando).

2. Adicione a regra de `DROP` (silenciosa) para a porta do Postgres:
   ```bash
   sudo iptables -A OUTPUT -p tcp --dport 5432 -d 127.0.0.1 -j DROP
   ```

3. Teste de novo, com um timeout curto de propósito (para não travar a aula):
   ```bash
   timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/5432 && echo CONECTOU'
   echo "código de saída: $?"
   ```
   Resultado esperado: **nada acontece por 5 segundos** — nenhuma mensagem de erro, nenhum "CONECTOU" — e o código de saída é `124` (o código que o comando `timeout` usa quando precisa matar o processo à força).

4. Compare mentalmente com o Cenário 1 (Parte B): lá, o erro apareceu **na hora**. Aqui, não aparece erro nenhum até o timeout estourar.

> ⏱️ **Nota de tempo:** se vocês tentassem essa mesma conexão *sem* o `timeout 5` (por exemplo, deixando `go run ./desacoplado/backend` tentar conectar sozinho, sem nenhum timeout customizado na aplicação), o sistema operacional só desistiria sozinho depois de **~1 a 2 minutos** (o parâmetro `tcp_syn_retries` do kernel Linux). Não é preciso esperar isso em sala — o importante é entender que sem um timeout explícito configurado, uma aplicação real ficaria pendurada esse tempo todo. É por isso que APIs bem escritas sempre configuram timeouts de conexão explícitos (o próprio `gotodolist` faz isso para o servidor HTTP, com `HTTP_READ_TIMEOUT` e afins — vale conferir `docs/getting-started.md` do projeto).

### Como corrigir

```bash
sudo iptables -D OUTPUT -p tcp --dport 5432 -d 127.0.0.1 -j DROP
```

Confirme que voltou ao normal:
```bash
timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/5432 && echo CONECTOU'
```
---

## Cenário 7 — SSL Certificate Expired (e parentes: self-signed, hostname errado)

### Causa raiz
"Problema de certificado SSL" **não é um erro único** — é uma família de causas diferentes: certificado expirado, certificado autoassinado (sem uma Autoridade Certificadora confiável por trás), ou certificado válido só para outro domínio. Vamos comparar as três antes de gerar a nossa própria.

### Teste 1 — observação sem nenhuma configuração (badssl.com)

O site [badssl.com](https://badssl.com/) existe justamente para testes com certificados SSL: cada subdomínio tem um problema de certificado diferente, de propósito.

1. Abra no navegador: `https://expired.badssl.com/` → aviso de segurança bloqueando o acesso.
2. Confirme via `curl`:
   ```bash
   curl https://expired.badssl.com/
   ```
   Resultado esperado: `curl: (60) SSL certificate problem: certificate has expired`.
3. Confirme via `openssl` (mostra o código de verificação padronizado):
   ```bash
   openssl s_client -connect expired.badssl.com:443 -servername expired.badssl.com </dev/null 2>/dev/null | grep "Verify return code"
   ```
   Resultado esperado: `Verify return code: 10 (certificate has expired)`.
4. Agora compare com **duas causas diferentes** da mesma família:
   ```bash
   curl https://self-signed.badssl.com/
   curl https://wrong.host.badssl.com/
   ```
   Reparem que as mensagens de erro do curl são diferentes uma da outra — "self signed certificate" não é a mesma coisa que "certificate has expired", mesmo os dois aparecendo como "cadeado quebrado" no navegador.

### Teste 2 — gerando o seu próprio certificado expirado

1. Gere um certificado autoassinado com data de validade **já no passado** (requer OpenSSL 3.0+; confira com `openssl req -help` se as flags `-not_before`/`-not_after` estão disponíveis na sua versão):
   ```bash
   openssl req -x509 -newkey rsa:2048 -nodes \
     -keyout expirado-key.pem -out expirado-cert.pem \
     -subj "/CN=localhost" \
     -not_before 20240101000000Z -not_after 20240102000000Z
   ```

2. Crie um `Caddyfile-ssl-expirado` apontando manualmente para esse certificado (sem usar o HTTPS automático do Caddy):
   ```caddyfile
   https://ip-da-vm:9443 {
       tls expirado-cert.pem expirado-key.pem
       respond "certificado expirado"
   }
   ```

3. Suba esse Caddy:
   ```bash
   sudo caddy run --config Caddyfile-ssl-expirado --adapter caddyfile
   ```

4. Teste via navegador: `https://ip-da-vm:9443` → aviso de certificado expirado e/ou:
   ```bash
   curl -v https://ip-da-vm:9443
   ```
   Resultado esperado: uma mensagem de certificado expirado, igual à do `expired.badssl.com`.

---

## Cenário 8 — HTTPS automático com Caddy

> Diferente dos cenários anteriores, aqui não vamos provocar nenhum erro — vamos configurar a coisa certa desde o início, e ver como isso evita os incidentes do Cenário 7 na raiz.

### Causa raiz / motivação
A maioria dos incidentes de certificado (Cenário 7) vem de **gestão manual**: alguém esqueceu de renovar, gerou o arquivo errado, ou digitou a data errada. O recurso "Automatic HTTPS" do Caddy remove essa causa raiz: você só diz **para quem** é o site (um hostname), e o Caddy cuida sozinho de obter, instalar e renovar o certificado — sem `.pem` manual, sem `certbot`, sem cron job de renovação.

### Como configurar

1. Garanta que a API está rodando em `8081` (terminal 1), bem como o frontend em `8082` (terminal 1).

2. Mude o config.js do frontend para apontar para o Caddy, não direto para a API:
   ```js
   window.GOTODOLIST_CONFIG = {
     apiBase: "https://ip-da-vm",
     version: "dev",
   };
   ```

3. Crie um `Caddyfile-https-auto` com o conteúdo abaixo:
   ```caddyfile
   https://ip-da-vm {
    tls internal

    # Rotas da API → Go na 8081 - notem o IP privado da API
    handle /health* {
        reverse_proxy 127.0.0.1:8081
    }
    handle /api/* {
        reverse_proxy 127.0.0.1:8081
    }

    # Tudo mais → frontend Python na 8082
    handle {
        reverse_proxy 127.0.0.1:8082
    }
   }

   ```

4. Suba o Caddy:
   ```bash
   caddy run --config Caddyfile-https-auto --adapter caddyfile
   ```
   > 💻 Se aparecer erro de permissão tentando abrir a porta `80` (o Caddy tenta usá-la para redirecionar HTTP→HTTPS automaticamente), pode rodar com `sudo` ou ignorar — a aplicação funciona normalmente em `9444` de qualquer jeito.

### Como confirmar que está funcionando

1. Acesse `https://ip-da-vm` **diretamente no navegador** (não pelo frontend). Deve aparecer um aviso de certificado não confiável (`NET::ERR_CERT_AUTHORITY_INVALID` no Chrome) — o Caddy usou sua **própria CA interna**, já que esse hostname não é um domínio público de verdade (o Caddy percebe isso sozinho e nem tenta pedir certificado ao Let's Encrypt).
2. Em outro terminal, instale a CA interna do Caddy no repositório de confiança do seu sistema (confira com `caddy help trust` se o comando existe na sua versão):
   ```bash
   sudo caddy trust
   ```
3. Na VM, o Caddy salva a sua chave de CA raiz em:
   ```bash
   sudo cat /root/.local/share/caddy/pki/authorities/local/root.crt
   ```
4. Copie esse conteúdo e salve em um arquivo no seu computador físico, por exemplo: caddy-root.crt
5. No seu computador físico, abra o navegador e instale esse certificado como **Autoridade Certificadora confiável** (o processo depende do sistema operacional e do navegador — no Windows, por exemplo, você clica duas vezes no `.crt` e segue o assistente; no macOS, abre o Keychain Access e arrasta o arquivo para lá; no Linux, depende da distro e do navegador). Depois de instalado, feche e reabra o navegador.
   - **Chrome / Brave / Edge**: Acesse `chrome://settings/certificates` → Aba Autoridades → Clique em Importar e selecione o arquivo `caddy-root.crt` → Marque a opção de confiar nesta autoridade para identificar sites.
   - **Firefox**: Acesse `about:preferences#privacy` → Role até Certificados → Ver certificados → Aba Autoridades → Importar.
6. Recarregue `https://ip-da-vm` — agora o cadeado aparece **válido**, sem aviso nenhum.


### Resumo
- Isso é **HTTPS local de desenvolvimento**, diferente do que acontece em produção com um domínio real: lá, o Caddy troca a CA interna por uma CA pública (Let's Encrypt/ZeroSSL) automaticamente, e o navegador de qualquer visitante já confia nela por padrão — ninguém mais precisa rodar `caddy trust`.
- `caddy trust` instala uma CA nova no seu sistema. Em uma máquina compartilhada (ex.: laboratório da faculdade), rode `sudo caddy untrust` ao final da aula para remover essa confiança extra.
- Sem um nome de domínio público, o Caddy não consegue obter certificado de uma CA pública (Let's Encrypt/ZeroSSL) — mas ele ainda consegue gerar um certificado **interno** confiável para a sua própria CA interna, e isso é suficiente para desenvolvimento local.
- Se houvesse uma outra API executando em outro host, bastaria adicionar outro bloco `handle` no Caddyfile, apontando para o IP/porta corretos, e o Caddy cuidaria de obter certificado válido para esse outro host também. Ex:
   ```caddyfile
   # API de usuários → VM diferente
    handle /users* {
        reverse_proxy ip-da-outra-api:porta-api
    }
    ```
    O navegador acessa https://ip-da-vm/users → Caddy roteia para http://ip-da-outra-api:porta-api/users de forma transparente. O usuário nem sabe que existe uma segunda VM. Isso é exatamente o padrão API Gateway / Reverse Proxy — um ponto de entrada único (geralmente com IP público) que distribui o tráfego para múltiplos serviços em máquinas diferentes. Em produção é assim que funciona o NGINX, o Traefik, o AWS ALB, etc. O Caddy só torna isso mais simples de configurar.
- Reverta o `config.js` para `apiBase: ""` antes de seguir para outros exercícios, para não carregar configuração de teste.

---

## Entregável

Preencham a tabela abaixo para **todos os cenários** e enviem pelo Classroom. Não é necessário capturar prints de tela, mas podem anexar se quiserem — o importante é que a tabela esteja completa.
| Cenário | Erro exato observado | Causa raiz | Comando de diagnóstico usado | Correção aplicada |
| :--- | :--- | :--- | :--- | :--- |
| 1 — ECONNREFUSED (backend) | | | | |
| 1 — ECONNREFUSED (banco) | | | | |
| 2 — DNS | | | | |
| 3 — CORS quebrado | | | | |
| 4 — 502 Bad Gateway | | | | |
| 5 — CORS via Caddy | | | | |
| 6 — ETIMEDOUT  | | | | |
| 7 — SSL expirado  | | | | |
| 8 — SSL válido  | | | | |

---




