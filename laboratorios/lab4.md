# Laboratório 4 (Expandido) — Build, Push Manual para o GHCR, Docker Compose com Limites de Recursos e Primeiros Passos com Docker Swarm

**Disciplina:** Infraestrutura de TI para Sistemas na Internet
**Aula de referência:** Aula 06 (Construindo Imagens Eficientes: Dockerfile e Multi-Stage Builds) e Aula 08 (Orquestração Local com Docker Compose & Entrega da Release 1) — com uma prévia manual do que a Aula 12 (GHCR) fará de forma automatizada.
**Projeto usado como cobaia:** fork pessoal de [`react-example-app`](https://github.com/elton-bt/react-example-app) (React/Create React App) para os cenários de build e push manual, e [`gotodolist`](https://github.com/elton-bt/gotodolist) (Go + PostgreSQL) para os cenários de Compose com limites de recursos e Docker Swarm.
**Objetivo:** sair da teoria ("o que é um Dockerfile", "o que é um registry", "o que é orquestração") para a prática de **construir e publicar uma imagem sob a sua própria identidade no GitHub Container Registry, sem nenhuma automação por trás, governar quanto de CPU e memória cada serviço de uma stack pode consumir, comprovar com comandos reais que esses limites realmente valem, e dar os primeiros passos em orquestração multi-host com Docker Swarm** — exatamente a mecânica que o pipeline de CI/CD da Aula 12 vai esconder atrás de um `git push`.

> ℹ️ **Por que este documento existe:** o Laboratório Prático da Aula 06 (em `slides-revisado.md`) já ensina Multi-Stage Build com dois exemplos (React+Nginx e Go+scratch), e o Laboratório Prático da Aula 08 já ensina a estrutura de um `docker-compose.yml` completo (Frontend + Backend + Banco + Proxy). Este documento é a **versão aprofundada**: em vez de um exemplo descartável, vocês publicam uma imagem de verdade sob a própria conta do GitHub (sem a rede de proteção do GitHub Actions), aplicam limites reais de CPU/memória na stack padrão da disciplina e comprovam esses limites até o ponto de derrubar um container de propósito — e, como bônus, transformam essa mesma stack em um cluster Docker Swarm.

> ⚠️ **Nota de honestidade técnica:** os comandos e trechos de saída deste documento foram validados em uma máquina Linux com Docker Engine 29.6.1 e Docker Compose v5.3.1 (plugin `docker compose`, não o antigo `docker-compose` em Python) em setembro de 2026. Tamanhos exatos de imagem, textos de aviso da CLI e o comportamento exato do OOM Killer podem variar conforme a versão do Docker, do kernel e do pacote `stress-ng` — sempre que o texto disser "resultado observado", trate como uma amostra real e não como um valor mágico.

---

## Como usar a LLM neste laboratório (leia isso primeiro)

Não peça à LLM para gerar o `Dockerfile` ou o `docker-compose.yml` inteiro e colar cego no projeto. Use este protocolo de 4 passos:

1. **Descreva a decisão técnica que você está tentando tomar** — não só "me dê o comando", mas o contexto: *"preciso decidir entre `deploy.resources.limits` e o atalho `mem_limit` no meu Compose"*, ou *"meu `docker stack deploy` ignorou o serviço da API e recebi este aviso exato"*.
2. **Peça à LLM duas coisas específicas:** (a) o trade-off técnico real por trás da decisão (não só "qual é mais moderno"), e (b) **um comando de verificação** que comprove, no seu próprio ambiente, qual comportamento está realmente em vigor (ex.: `docker inspect --format`).
3. **Rode o comando de verificação você mesmo** antes de aceitar a explicação como definitiva.
4. **Só depois aplique a mudança** e confirme de novo — "a documentação diz que funciona assim" não é o mesmo que "está configurado assim agora, no seu container".

---

## Preparação do Ambiente (compartilhada — fazer uma vez, ~20 min)

### 1. Fork do projeto usado no build manual

Acesse [`github.com/elton-bt/react-example-app`](https://github.com/elton-bt/react-example-app) autenticado com a sua conta do GitHub e clique em **Fork** (canto superior direito). Isso cria uma cópia em `github.com/<seu-usuario>/react-example-app` — é essa cópia, sob a sua própria identidade, que vamos construir e publicar (o GHCR associa cada imagem à conta que fez o push, por isso o exercício não usa o repositório do professor diretamente).

Clone o **seu fork** (troque `<seu-usuario>` pelo seu usuário real do GitHub):

```bash
git clone https://github.com/<seu-usuario>/react-example-app.git
cd react-example-app
```

### 2. Criar um Personal Access Token (PAT) para autenticar no GHCR

Fora de um workflow do GitHub Actions (que usa o `secrets.GITHUB_TOKEN` automático — ver Aula 12), publicar manualmente exige um token pessoal:

1. GitHub → foto de perfil → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token (classic)**.
2. Marque o escopo `write:packages` (esse escopo já inclui `read:packages` automaticamente).
3. Copie o token gerado **agora** — o GitHub só o exibe uma vez.

> ⚠️ Prefira o token **clássico** para este exercício. Em setembro de 2026, o suporte de *fine-grained personal access tokens* ao Container Registry ainda é mais limitado/inconsistente que o dos tokens clássicos — confira a documentação atual do GitHub antes de recomendar um ou outro à turma.
>
> 🔒 Nunca commite esse token em nenhum arquivo do repositório (nem em `.env`, nem em um script "só para testar"). Se estiver em uma máquina de laboratório compartilhada, revogue o token ao final da aula (mesma tela onde ele foi criado → **Delete**).

### 3. Login no GHCR

```bash
export CR_PAT=cole_seu_token_aqui
echo "$CR_PAT" | docker login ghcr.io -u <seu-usuario> --password-stdin
```

Resultado esperado: `Login Succeeded`.

### 4. Clonar/atualizar o `gotodolist` (usado a partir do Cenário 3)

```bash
cd ..
git clone https://github.com/elton-bt/gotodolist.git   # pule se já tiver dos laboratórios anteriores
cd gotodolist
cp example.env .env
```

### 5. Limpar containers, stacks e swarms de laboratórios anteriores que possam colidir

```bash
docker rm -f gotodolist-db gotodolist-backend gotodolist-db-recuperado react-teste react-teste-v2 2>/dev/null || true
docker stack rm gotodolist gotodolist-swarm 2>/dev/null || true
docker swarm leave --force 2>/dev/null || true
```

### 6. Checklist de baseline

- [ ] `docker login ghcr.io` retornou `Login Succeeded`.
- [ ] Seu fork existe em `https://github.com/<seu-usuario>/react-example-app`.
- [ ] `docker compose version` mostra a versão do **plugin** (`Docker Compose version v2.x` ou `v5.x`) — se aparecer um binário Python separado chamado `docker-compose`, é a versão antiga (V1); desinstale-a ou garanta que `docker compose` (com espaço) seja o comando usado no laboratório.
- [ ] Pasta `gotodolist` clonada e `.env` criado a partir de `example.env`.

---

# NÚCLEO

## Cenário 1 — Build Manual e Push para o GHCR: a Mecânica de um Registry

### Causa raiz / Fundamento teórico

Uma imagem construída com `docker build` só existe, a princípio, na sua própria máquina. Para ela rodar em outro lugar — um servidor, o notebook de um colega, ou (mais adiante neste laboratório) um cluster Docker Swarm — ela precisa estar em um **registry**: um "GitHub para imagens de container".

- **`docker save`/`docker load`** movem uma imagem como um arquivo `.tar` manual — funciona, mas não escala, não tem versionamento e não tem controle de acesso.
- **`docker push`/`docker pull`** falam um protocolo HTTP de distribuição de imagens: camadas são reaproveitadas entre pushes (só o que mudou é enviado de novo), há autenticação e há um histórico de tags.
- O **GHCR (GitHub Container Registry)**, em `ghcr.io`, associa cada imagem publicada à conta ou organização do GitHub que fez o push — por isso o exercício pede um **fork**: cada aluno publica sob a própria identidade, não a do professor.
- Na Aula 12, a action `docker/login-action` usa o `secrets.GITHUB_TOKEN` gerado automaticamente **dentro** de um workflow do GitHub Actions. Fora de um workflow, não existe esse token mágico — é exatamente essa mecânica "por baixo do capô" que este cenário dissseca manualmente, antes de você confiar nela automatizada.

### Como configurar e executar

1. Com o repositório do fork já clonado (Preparação, passo 1), inspecione o `Dockerfile` que já vem pronto no projeto:
   ```bash
   cat Dockerfile
   ```
   Conteúdo real do repositório:
   ```dockerfile
   FROM  node:18-alpine
   WORKDIR /app
   COPY package.json package-lock.json ./
   COPY . .
   RUN npm install
   CMD ["npm","run","start"]
   ```
   Guarde essa foto — vamos criticar e melhorar esse `Dockerfile` no Cenário 2. Por ora, o objetivo é só **publicá-lo como está** para dominar a mecânica do registry.

2. Construa a imagem localmente:
   ```bash
   docker build -t react-example-app:v1 .
   ```
   > 💡 O `package.json` do projeto usa `react-scripts` (Create React App) — o comando `npm run start` do `CMD` sobe o **servidor de desenvolvimento** do Webpack, que escuta por padrão em `0.0.0.0:3000` dentro do container. Se o `npm install` mostrar avisos de dependências desatualizadas, é esperado nesse projeto; o build deve terminar mesmo assim.

3. Rode e teste antes de publicar qualquer coisa:
   ```bash
   docker run -d --name react-teste -p 3000:3000 react-example-app:v1
   sleep 5
   curl -I http://localhost:3000
   ```
   Se o `curl` não responder de primeira, o servidor de desenvolvimento ainda pode estar compilando — espere mais alguns segundos e tente de novo, ou acompanhe com `docker logs -f react-teste`.

4. Anote o tamanho da imagem antes de otimizar (vamos comparar no Cenário 2):
   ```bash
   docker images react-example-app:v1
   ```

5. Marque a imagem com o endereço do seu namespace no GHCR (troque `<seu-usuario>` pelo seu usuário do GitHub **em minúsculas** — nomes de imagem Docker não aceitam maiúsculas):
   ```bash
   docker tag react-example-app:v1 ghcr.io/<seu-usuario>/react-example-app:v1
   ```

6. Publique:
   ```bash
   docker push ghcr.io/<seu-usuario>/react-example-app:v1
   ```

7. Verifique no GitHub: acesse `https://github.com/<seu-usuario>?tab=packages` (ou perfil → aba **Packages**). Clique no pacote recém-criado.
   - Por padrão, **a primeira publicação de um pacote é sempre privada**, independentemente da visibilidade do repositório de origem.
   - Repare que o pacote ainda não está "vinculado" a nenhum repositório do seu GitHub — em **Package settings** (parte inferior da página do pacote) você pode conectá-lo ao repositório do fork e, na seção **Danger Zone**, mudar a visibilidade para pública se quiser.

8. **Prove que a imagem está realmente no registry** (não só marcada localmente) apagando a cópia local e puxando de novo do zero:
   ```bash
   docker rm -f react-teste
   docker rmi ghcr.io/<seu-usuario>/react-example-app:v1 react-example-app:v1
   docker images | grep react-example-app   # deve voltar vazio
   docker pull ghcr.io/<seu-usuario>/react-example-app:v1
   ```
   Se o pacote ainda estiver privado, o `pull` só funciona porque você continua logado (`docker login ghcr.io`) com uma conta autorizada — é a prova viva do controle de acesso do registry.

### Como observar/diagnosticar (erros comuns)

| Erro observado | Causa provável | Correção |
| :--- | :--- | :--- |
| `denied: denied` | Token sem o escopo `write:packages`, ou nome de usuário errado na tag | Gerar um PAT novo com o escopo certo; conferir se a tag usa exatamente `ghcr.io/<seu-usuario>/...` |
| `unauthorized: authentication required` | Sessão de login expirada ou nunca feita nesta sessão de terminal | Rodar `docker login ghcr.io` de novo |
| `invalid reference format` | Letra maiúscula em algum ponto do nome da imagem | Nomes de imagem Docker são sempre em minúsculas |
| `push` trava ou dá timeout | Rede do laboratório bloqueando HTTPS de saída para `ghcr.io` | Testar antes com `curl -I https://ghcr.io` |

### Como corrigir / validar

Depois de corrigir qualquer um dos erros acima, repita o `docker push` — ele é idempotente (reenviar a mesma imagem não causa dano, apenas reaproveita camadas já existentes no registry).

### Como usar a LLM aqui

Peça à LLM para explicar a diferença entre a autenticação usada aqui (PAT pessoal, você mesmo digitando a senha) e a autenticação usada dentro de um workflow do GitHub Actions (`secrets.GITHUB_TOKEN`, criado e descartado automaticamente a cada execução) — e por que a segunda é considerada mais segura para pipelines de CI/CD.

---

## Cenário 2 — Multi-Stage: Consertando a Imagem e Comparando Tamanhos Reais

### Causa raiz / Fundamento teórico

O `Dockerfile` publicado no Cenário 1 tem, na prática, quatro problemas reais (não hipotéticos — estão no repositório de verdade):

1. **A ordem das instruções não economiza cache nenhum.** Ele copia `package.json`/`package-lock.json` primeiro (como a Aula 06 ensina), mas em seguida faz `COPY . .` — copiando **tudo** — **antes** de rodar `npm install`. Isso anula completamente o benefício de cache: qualquer alteração em qualquer arquivo do projeto (até um `.css`) já invalida a camada de instalação de dependências, exatamente o anti-padrão que a "Regra de Ouro da Ordem das Instruções" da Aula 06 pede para evitar.
2. **O `CMD` sobe o servidor de desenvolvimento** (`react-scripts start`, o Webpack Dev Server) — isso nunca deveria ir para produção: é mais lento, inclui *hot-reload*, *source maps* e todo o ferramental de desenvolvimento dentro da imagem final.
3. **Não existe um `.dockerignore`** no repositório. Isso significa que `COPY . .` também copia a pasta `.git` (todo o histórico de commits!) para dentro da imagem — desperdício de espaço e, potencialmente, um risco de vazar informação de commits antigos que ninguém revisou pensando que aquilo iria parar dentro de uma imagem publicada.
4. **`FROM node:18-alpine`** usa uma versão do Node.js já fora do período de suporte (Node 18 chegou ao fim de vida em abril de 2025) — exatamente o tipo de achado que o scanner de imagem da Aula 11 (Trivy) sinalizaria como `Security Misconfiguration`/dependência desatualizada.

Além disso, o `package.json` declara `react-router-dom` como dependência — ou seja, esta aplicação usa **roteamento do lado do cliente**. Isso importa muito na hora de servir os arquivos compilados com Nginx: sem uma regra de *fallback*, recarregar a página em qualquer rota que não seja a raiz (`/`) devolve `404 Not Found`, porque esses caminhos não existem como arquivos reais — só o JavaScript, já carregado, sabe rotear para eles.

### Como corrigir

1. Crie um `.dockerignore` (reaproveitando o padrão do Exemplo A da Aula 06):
   ```text
   node_modules
   build
   .git
   .gitignore
   .devcontainer
   README.md
   Dockerfile
   Dockerfile.multi
   ```

2. Crie um arquivo de configuração do Nginx com a regra de *fallback* para SPA, `nginx.lab.conf`:
   ```nginx
   server {
       listen 80;
       root /usr/share/nginx/html;
       index index.html;

       location / {
           try_files $uri $uri/ /index.html;
       }
   }
   ```

3. Reescreva o Dockerfile como multi-stage em um novo arquivo `Dockerfile.multi` (reaproveitando o Exemplo A da Aula 06, com a base do estágio de build atualizada para uma versão do Node ainda suportada):
   ```dockerfile
   # Estágio 1: build dos artefatos estáticos (ambiente pesado, descartável)
   FROM node:22-alpine AS builder
   WORKDIR /app
   COPY package.json package-lock.json ./
   RUN npm ci
   COPY . .
   RUN npm run build

   # Estágio 2: runtime enxuto — sem Node, sem devDependencies, sem toolchain
   FROM nginx:1.27-alpine AS runner
   RUN rm -rf /etc/nginx/conf.d/*
   COPY nginx.lab.conf /etc/nginx/conf.d/default.conf
   COPY --from=builder /app/build /usr/share/nginx/html
   EXPOSE 80
   CMD ["nginx", "-g", "daemon off;"]
   ```
   > ⚠️ Confira, antes de cada semestre, se `node:22-alpine` e `nginx:1.27-alpine` ainda são tags atuais e mantidas — Node.js e Nginx lançam novas versões estáveis com frequência.

4. Construa a versão otimizada e compare o tamanho com a versão ingênua do Cenário 1:
   ```bash
   docker build -f Dockerfile.multi -t react-example-app:v2 .
   docker images | grep react-example-app
   ```

5. Teste a versão nova, incluindo a rota "profunda" que só existe do lado do cliente (prova de que o `try_files` funciona):
   ```bash
   docker run -d --name react-teste-v2 -p 3000:80 react-example-app:v2
   curl -I http://localhost:3000/
   curl -I http://localhost:3000/qualquer/rota/interna
   ```
   As duas chamadas devem responder `200 OK` — sem o `try_files`, a segunda devolveria `404`.

6. Publique a versão otimizada com uma nova tag (sem sobrescrever a `v1` — isso é, por si só, uma prévia informal do SemVer que a Aula 12 formaliza):
   ```bash
   docker tag react-example-app:v2 ghcr.io/<seu-usuario>/react-example-app:v2
   docker push ghcr.io/<seu-usuario>/react-example-app:v2
   docker tag react-example-app:v2 ghcr.io/<seu-usuario>/react-example-app:latest
   docker push ghcr.io/<seu-usuario>/react-example-app:latest
   ```

### Tabela Comparativa (preencham com os valores reais da sua máquina)

| Versão | Base de runtime final | Contém `devDependencies`? | Contém `node_modules` completo? | Roda servidor de desenvolvimento? | Tamanho observado |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `v1` (ingênua) | `node:18-alpine` (fora de suporte) | Sim | Sim | Sim (`react-scripts start`) | ______ |
| `v2` (multi-stage) | `nginx:1.27-alpine` | Não | Não (só os artefatos estáticos compilados) | Não (Nginx serve arquivos prontos) | ______ |

### Como usar a LLM aqui

Peça à LLM para explicar por que rodar o servidor de desenvolvimento do Webpack dentro de um container de produção é um anti-padrão (além do tamanho da imagem, pense em desempenho e superfície de ataque) — e depois peça para ela explicar o que exatamente o `try_files $uri $uri/ /index.html;` está fazendo, linha a linha.

---

## Cenário 3 — Docker Compose "Mais Completo": Limites de CPU e Memória na Stack do `gotodolist`

### Causa raiz / Fundamento teórico

O `docker-compose-dev.yaml` real do `gotodolist` já implementa boas práticas da Aula 08: sem a chave `version:` obsoleta, `healthcheck` em todos os serviços com estado, e `depends_on` combinado com `condition: service_healthy`. Ele também já segrega redes: o serviço `frontend` participa só da rede `frontend_api`, o `db` participa só da `api_db`, e apenas a `api` transita entre as duas.

> 💡 Repare que isso é, na prática, exatamente o padrão de isolamento DMZ vs Rede Interna do Banco do Cenário 4 do [`laboratório-3.md`](laboratório-3.md) — só que aqui vem pronto de fábrica no projeto da disciplina, não construído manualmente por vocês.

O que falta nesse arquivo — e é o foco deste cenário — são **limites explícitos de CPU e memória**. Sem eles, um container com um vazamento de memória ou um loop de CPU descontrolado pode consumir 100% dos recursos do host, derrubando os outros serviços que rodam ali (o problema do "vizinho barulhento"/*noisy neighbor*) — um risco real em qualquer servidor compartilhado.

Existem duas sintaxes no Compose para isso:
- **Atalhos legados** (`mem_limit`, `cpus`, direto no nível do serviço) — mais simples, mas documentados como caminho de compatibilidade retroativa.
- **`deploy.resources.limits`/`reservations`** — a sintaxe da *Compose Specification*, recomendada, e que reaproveitaremos **sem nenhuma alteração** no Cenário 5 (Docker Swarm). Não é decoração: é a mesma seção que o `docker stack deploy` lê nativamente.

> ⚠️ **Nota de honestidade técnica:** historicamente, a seção `deploy.resources` só era respeitada em modo Swarm (`docker stack deploy`), sendo ignorada por `docker-compose up`. Isso mudou com o **plugin `docker compose` (V2)**, usado em toda a disciplina: ele aplica `deploy.resources.limits.cpus`/`memory` mesmo fora do Swarm, traduzindo para as mesmas restrições de cgroups que `docker run --cpus`/`--memory` aplicariam. Não aceite isso de graça — o passo de diagnóstico abaixo prova que o limite foi realmente aplicado ao seu container.

### Como configurar

Dentro da pasta `gotodolist` (clonada na Preparação), crie um novo arquivo `docker-compose-lab4.yaml` — não vamos alterar os arquivos originais do projeto:

```yaml
name: gotodolist-lab4

services:
  db:
    image: postgres:17-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${DB_NAME:-gotodolist}
      POSTGRES_USER: ${DB_USER:-gotodolist}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-replace-me}
    ports:
      - "${DB_HOST_PORT:-5432}:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - api_db
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 5s
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
        reservations:
          cpus: "0.25"
          memory: 256M

  api:
    build:
      context: .
      dockerfile: desacoplado/backend/Dockerfile
      args:
        APP_VERSION: ${APP_VERSION:-dev}
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      DB_HOST: ${DB_HOST:-db}
      DB_PORT: ${DB_PORT:-5432}
      DB_NAME: ${DB_NAME:-gotodolist}
      DB_USER: ${DB_USER:-gotodolist}
      DB_PASSWORD: ${DB_PASSWORD:-replace-me}
      DB_SSLMODE: ${DB_SSLMODE:-disable}
      CORS_ALLOW_ORIGIN: ${CORS_ALLOW_ORIGIN:-*}
    ports:
      - "${API_HOST_PORT:-8081}:8081"
    networks:
      - frontend_api
      - api_db
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:8081/health"]
      interval: 20s
      timeout: 5s
      retries: 5
      start_period: 15s
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
        reservations:
          cpus: "0.1"
          memory: 64M

  frontend:
    build:
      context: .
      dockerfile: desacoplado/frontend/Dockerfile
      args:
        APP_VERSION: ${APP_VERSION:-dev}
    restart: unless-stopped
    depends_on:
      api:
        condition: service_healthy
    environment:
      GOTODOLIST_API_BASE_URL: ${GOTODOLIST_API_BASE_URL:-}
    ports:
      - "${FRONTEND_HOST_PORT:-8082}:8080"
    networks:
      - frontend_api
    deploy:
      resources:
        limits:
          cpus: "0.3"
          memory: 128M
        reservations:
          cpus: "0.05"
          memory: 32M

volumes:
  postgres-data:

networks:
  frontend_api:
  api_db:
```

> 💡 Vale abrir e ler `desacoplado/backend/Dockerfile` e `desacoplado/frontend/Dockerfile` do próprio projeto antes de seguir: o backend já é multi-stage (Go compilado estaticamente sobre `alpine`, usuário não-root `app`) e o frontend já roda sobre `nginxinc/nginx-unprivileged` (usuário não-root por padrão) — o projeto padrão da disciplina já aplica, na prática, as boas práticas da Aula 06 que vocês reforçaram manualmente no Cenário 2.

Suba a stack:

```bash
docker compose -f docker-compose-lab4.yaml --env-file .env up -d --build
docker compose -f docker-compose-lab4.yaml ps
```

### Como observar/diagnosticar

Não confie apenas no arquivo YAML — comprove que o limite chegou até o container de verdade:

```bash
docker inspect gotodolist-lab4-api-1 --format 'CPUs(nano)={{.HostConfig.NanoCpus}} Memoria(bytes)={{.HostConfig.Memory}}'
```

`NanoCpus` é a CPU em bilionésimos (0.5 CPU = `500000000`); `Memory` vem em bytes (256M ≈ `268435456`). Para acompanhar consumo em tempo real:

```bash
docker stats --no-stream
```

### ⚠️ Armadilha

Se você definir um limite de memória menor do que o necessário para o processo sequer inicializar (por exemplo, `memory: 32M` para o `db`), o container entra em um ciclo de `Restarting` sem nunca ficar saudável. O Cenário 4 mostra exatamente como diagnosticar isso com certeza (`OOMKilled`), em vez de ficar "chutando" um número maior até parar de falhar.

### Como corrigir / validar

Se algum serviço não subir, `docker compose -f docker-compose-lab4.yaml logs <serviço>` normalmente mostra o processo sendo interrompido no meio da inicialização — sinal de limite baixo demais, a ser confirmado no próximo cenário.

### Como usar a LLM aqui

Peça à LLM para explicar a diferença entre `limits` (o teto que o container nunca pode ultrapassar) e `reservations` (o mínimo garantido pelo agendador, relevante principalmente em Swarm) — e por que faz sentido que `reservations` seja sempre menor ou igual a `limits`.

---

## Cenário 4 — Provocando (e Confirmando) um OOM Kill: o Limite de Memória Não é Sugestão

### Causa raiz / Fundamento teórico

CPU e memória são limitados de formas fundamentalmente diferentes pelo kernel Linux:

- **CPU (`--cpus`/`deploy.resources.limits.cpus`):** o kernel usa o *CFS bandwidth control* — ele apenas **atrasa** o processo, dando menos fatias de tempo de processador. O processo nunca morre por causa disso, só fica mais lento.
- **Memória (`--memory`/`deploy.resources.limits.memory`):** é um limite rígido de cgroup. Se o processo tenta alocar além do permitido, o **OOM Killer** do kernel mata algum processo dentro daquele cgroup para liberar memória. Não tem meio-termo: ou cabe, ou alguém morre.

### Como provocar

```bash
docker run -d --name teste-limite-memoria \
  --memory=100m --memory-swap=100m \
  alpine:latest \
  sh -c "apk add --no-cache stress-ng >/dev/null 2>&1 && stress-ng --vm 1 --vm-bytes 300m --vm-keep --timeout 30s"
```

`--memory-swap` igual a `--memory` desliga a folga de swap (por padrão o Docker permite até 2x o limite em swap antes de matar o processo) — isso torna o teste um limite estritamente rígido. O `stress-ng` tenta alocar 300MB dentro de um cgroup de 100MB: 3x o permitido.

### Como observar

```bash
docker wait teste-limite-memoria
docker inspect teste-limite-memoria --format 'OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}'
```

*Resultado observado (validado nesta documentação, Docker 29.6.1, cgroups v2):*
```text
OOMKilled=true ExitCode=0
```

Repare em algo sutil: o processo principal do container (o `sh` que orquestra o `apk add` e o `stress-ng`) conseguiu terminar sozinho ao fim do teste — mas a flag `OOMKilled` mesmo assim ficou `true`. Essa flag reflete se o **kernel matou qualquer processo dentro do cgroup de memória daquele container** em algum momento (bem provavelmente um processo auxiliar de curta duração, como parte do próprio `apk add`), não necessariamente o processo principal. Rodem vocês mesmos e comparem: dependendo da versão do `stress-ng`, do kernel e de quão perto do limite a alocação fica, também é comum ver `ExitCode=137` (128 + sinal 9/SIGKILL) quando é o próprio processo principal que morre. O que **não muda** é a lição central: **estourar o limite de memória sempre aciona o OOM Killer — a única incerteza é qual processo especificamente ele escolhe matar.**

### Comparando com o limite de CPU (sufoca, mas não mata)

```bash
docker run -d --name teste-limite-cpu --cpus="0.5" alpine:latest sh -c "yes > /dev/null"
docker stats --no-stream teste-limite-cpu
```

*Resultado observado:* CPU% girando em torno de 50% (nunca muito acima disso) e o container continua `Up` — ele nunca é derrubado, só fica permanentemente sufocado.

### Tabela comparativa

| Recurso | O que acontece ao ultrapassar o limite | O processo morre? | Como confirmar |
| :--- | :--- | :--- | :--- |
| Memória (`--memory`) | Kernel Linux (OOM Killer) mata processo(s) dentro do cgroup | Quase sempre sim, para algum processo do cgroup | `docker inspect --format '{{.State.OOMKilled}}'` |
| CPU (`--cpus`) | Kernel limita (*throttling*) o tempo de CPU concedido via CFS bandwidth control | Não — só fica mais lento | `docker stats` (CPU% nunca ultrapassa o limite configurado) |

### Como corrigir / validar

```bash
docker rm -f teste-limite-memoria teste-limite-cpu
```

Reforcem a lição para a stack real do Cenário 3: se `OOMKilled=true` aparecer em produção, a correção **não é sempre** "aumentar o número até parar de acontecer" — primeiro vale investigar se há um vazamento de memória real na aplicação; só depois disso, se o consumo normal e saudável realmente exige mais, aumentar o limite (dentro do que o host aguenta).

### Como usar a LLM aqui

Peça à LLM para explicar por que estourar memória aciona o OOM Killer (sinal `SIGKILL`, não `SIGTERM`) enquanto estourar CPU só resulta em *throttling* — e o que o código de saída `137` significa em qualquer ambiente de containers, inclusive Kubernetes (é a mesma aritmética: 128 + número do sinal).

---

# BÔNUS & DESAFIOS AVANÇADOS

## Cenário 5 — Docker Swarm: do Single-Node ao Stack Deploy

### Causa raiz / Motivação

Tudo que fizemos até aqui roda em **um único host**. O Docker Swarm transforma vários hosts Docker em um cluster único, com orquestração nativa — réplicas, *rolling update*, *self-healing* básico — sem precisar instalar nada além do próprio Docker Engine (diferente do Kubernetes, que é um projeto à parte).

A chave `deploy:` que vocês já usaram no Cenário 3 para limites de CPU/memória não foi decoração: é a sintaxe **nativa** do Swarm. O `docker stack deploy` lê exatamente essa seção.

### Como configurar

1. Inicialize o modo Swarm:
   ```bash
   docker swarm init
   ```
   > ⚠️ **Erro comum e real** em notebooks conectados a mais de uma rede (Wi-Fi + VPN + interface virtual, por exemplo):
   > ```text
   > Error response from daemon: could not choose an IP address to advertise since this
   > system has multiple addresses on different interfaces (...) - specify one with --advertise-addr
   > ```
   > Identifique o IP da interface correta (`ip -br addr`) e especifique-o:
   > ```bash
   > docker swarm init --advertise-addr <SEU_IP>
   > ```

2. Confirme o nó único como manager:
   ```bash
   docker node ls
   ```

3. **Tente** publicar a stack com limites de recursos do Cenário 3 diretamente:
   ```bash
   docker stack deploy -c docker-compose-lab4.yaml gotodolist
   ```
   *Resultado observado:* um aviso do tipo `Ignoring unsupported options: build`, e os serviços `api`/`frontend` (que só têm `build:`, sem `image:`) não sobem — não existe imagem nenhuma para o Swarm agendar.

   **Causa raiz:** o Swarm pode agendar uma réplica de serviço em **qualquer nó** do cluster. Esse nó não tem o seu `Dockerfile` nem o contexto de build — ele só sabe fazer `docker pull` de um registry. Por isso o Swarm ignora `build:` silenciosamente: ele foi projetado para múltiplos hosts, e "construir a imagem localmente" só faz sentido para um host só.

4. Corrija criando `docker-compose-swarm.yaml`, reaproveitando o `docker-compose-prod.yaml` real do projeto (que já usa `image:` em vez de `build:`, apontando para as imagens que o pipeline de CI da Aula 12 já publica automaticamente em `ghcr.io/elton-bt/gotodolist-api` e `gotodolist-frontend`, ambas públicas) — acrescido dos limites de recursos e réplicas:
   ```yaml
   name: gotodolist-swarm

   services:
     db:
       image: postgres:17-alpine
       environment:
         POSTGRES_DB: ${DB_NAME:-gotodolist}
         POSTGRES_USER: ${DB_USER:-gotodolist}
         POSTGRES_PASSWORD: ${DB_PASSWORD:-replace-me}
       volumes:
         - postgres-data:/var/lib/postgresql/data
       networks:
         - api_db
       deploy:
         replicas: 1
         resources:
           limits:
             cpus: "1.0"
             memory: 512M
           reservations:
             cpus: "0.25"
             memory: 256M

     api:
       image: ghcr.io/${GHCR_OWNER:-elton-bt}/gotodolist-api:${IMAGE_TAG:-latest}
       depends_on:
         db:
           condition: service_healthy
       environment:
         DB_HOST: ${DB_HOST:-db}
         DB_PORT: ${DB_PORT:-5432}
         DB_NAME: ${DB_NAME:-gotodolist}
         DB_USER: ${DB_USER:-gotodolist}
         DB_PASSWORD: ${DB_PASSWORD:-replace-me}
         DB_SSLMODE: ${DB_SSLMODE:-disable}
         CORS_ALLOW_ORIGIN: ${CORS_ALLOW_ORIGIN:-*}
       ports:
         - "${API_HOST_PORT:-8081}:8081"
       networks:
         - frontend_api
         - api_db
       deploy:
         replicas: 2
         update_config:
           parallelism: 1
           delay: 10s
           monitor: 15s
           max_failure_ratio: 0
           failure_action: rollback
         rollback_config:
           parallelism: 1
           delay: 5s
         resources:
           limits:
             cpus: "0.5"
             memory: 256M
           reservations:
             cpus: "0.1"
             memory: 64M

     frontend:
       image: ghcr.io/${GHCR_OWNER:-elton-bt}/gotodolist-frontend:${IMAGE_TAG:-latest}
       depends_on:
         api:
           condition: service_healthy
       environment:
         GOTODOLIST_API_BASE_URL: ${GOTODOLIST_API_BASE_URL:-}
       ports:
         - "${FRONTEND_HOST_PORT:-8082}:8080"
       networks:
         - frontend_api
       deploy:
         replicas: 2
         resources:
           limits:
             cpus: "0.3"
             memory: 128M
           reservations:
             cpus: "0.05"
             memory: 32M

   volumes:
     postgres-data:

   networks:
     frontend_api:
     api_db:
   ```
   > ⚠️ **Outra diferença importante do Swarm:** `depends_on` continua aceito na sintaxe, mas a condição `service_healthy` **não é respeitada** em modo Swarm — o Docker sobe os serviços sem esperar a dependência ficar saudável, contando com o `healthcheck` + política de restart + a resiliência da própria aplicação para convergir. Deixamos a chave no arquivo por documentação, mas não contem com ela para ordenar a inicialização aqui.

5. `docker stack deploy` **não lê o arquivo `.env` automaticamente** como o `docker compose up` faz — as variáveis precisam já estar exportadas no shell:
   ```bash
   set -a
   source .env
   set +a
   docker stack deploy -c docker-compose-swarm.yaml gotodolist
   ```

6. Acompanhe:
   ```bash
   docker stack services gotodolist
   docker stack ps gotodolist
   ```

7. Acesse a aplicação pela porta publicada (`http://localhost:8082`) normalmente — e repare que, graças à *routing mesh* (rede de ingresso) do Swarm, **qualquer nó do cluster** responderia nessa porta, mesmo que a réplica específica não esteja rodando ali:

   ```text
                          ┌───────────────────────────────┐
                          │      Docker Swarm Cluster      │
                          │                                │
    docker stack deploy   │      ┌────────────┐             │
    ────────────────────> │      │  Manager   │ (agenda tarefas)
                          │      └─────┬──────┘             │
                          │            │                    │
                          │   ┌────────┼────────┐           │
                          │   │        │        │           │
                          │ ┌─▼──┐   ┌─▼──┐   ┌──▼─┐        │
                          │ │Nó A│   │Nó B│   │Nó C│        │
                          │ └────┘   └────┘   └────┘        │
                          └───────────────────────────────┘
    Uma requisição na porta publicada, em QUALQUER nó, chega
    ao serviço certo — mesmo que a réplica não esteja rodando
    naquele nó específico (Routing Mesh / rede "ingress").
   ```

### Como observar/diagnosticar

Confirme que o mesmo bloco `deploy.resources` do Cenário 3 realmente chegou ao Swarm, agora traduzido para a linguagem de serviço:

```bash
docker service inspect --pretty gotodolist_api
```

Procure a seção `Resources` — os valores de `Limits`/`Reservations` devem bater exatamente com o que está no `docker-compose-swarm.yaml`.

### Como corrigir / validar

Se algum serviço aparecer como `0/2` réplicas por muito tempo em `docker stack services`, investigue com `docker service ps --no-trunc gotodolist_api` — o campo de erro costuma apontar image pull falhando (rede) ou falha de healthcheck.

### Como usar a LLM aqui

Peça à LLM para explicar a *routing mesh* (rede *ingress*) do Swarm comparada à simples publicação de porta do Compose — e por que o Swarm exige imagens já publicadas em um registry em vez de aceitar `build:`.

---

## Cenário 6 — Escalando Réplicas e Rolling Update com Rollback

### Causa raiz / Fundamento teórico

O Swarm permite escalar réplicas e atualizar serviços sem downtime total, usando `update_config`/`rollback_config` — já presentes no `docker-compose-swarm.yaml` do Cenário 5.

### Como configurar

1. Escale manualmente e observe:
   ```bash
   docker service scale gotodolist_api=3
   docker service ps gotodolist_api
   ```

2. Provoque uma atualização deliberadamente ruim (uma tag que não existe no GHCR):
   ```bash
   docker service update --image ghcr.io/elton-bt/gotodolist-api:tag-que-nao-existe gotodolist_api
   ```

3. Acompanhe repetindo o comando a cada poucos segundos:
   ```bash
   docker service ps gotodolist_api
   ```
   Espera-se ver tarefas em estado `Rejected`/`Failed` para a nova imagem e, graças a `failure_action: rollback`, o Swarm reverter sozinho para a imagem anterior depois da janela de `monitor` configurada.

4. Confirme que voltou à imagem funcional:
   ```bash
   docker service inspect --pretty gotodolist_api | grep -i image
   ```

5. Caso o rollback automático não dispare a tempo (ou você queira reverter manualmente uma atualização válida, mas indesejada):
   ```bash
   docker service rollback gotodolist_api
   ```

### Como observar/diagnosticar

`docker service logs gotodolist_api --tail 30` mostra as tentativas de pull/start que falharam durante a atualização ruim.

### Como corrigir / validar

Depois de confirmado o rollback, escale de volta e limpe o ambiente:
```bash
docker service scale gotodolist_api=2
docker stack rm gotodolist
docker swarm leave --force
```

### Como usar a LLM aqui

Peça à LLM para comparar `failure_action: rollback` (automático, baseado em healthcheck) com `docker service rollback` (manual, sob demanda) — e em que cenário de produção cada um faz mais sentido.

---

## Desafio Avançado — Cluster Swarm Multi-Nó de Verdade com Vagrant

Tudo até aqui rodou em um Swarm de **um nó só** (o próprio notebook fazendo o papel de manager e worker ao mesmo tempo). Para sentir a orquestração multi-host de verdade, reaproveitem as habilidades de Vagrant Multi-Machine da Aula 04.

1. Crie um `Vagrantfile` com 3 máquinas em rede privada:
   ```ruby
   Vagrant.configure("2") do |config|
     config.vm.box = "ubuntu/jammy64"

     NODES = {
       "swarm-manager" => "192.168.56.30",
       "swarm-worker1" => "192.168.56.31",
       "swarm-worker2" => "192.168.56.32",
     }

     NODES.each do |name, ip|
       config.vm.define name do |node|
         node.vm.hostname = name
         node.vm.network "private_network", ip: ip
         node.vm.provision "shell", inline: <<-SHELL
           apt-get update
           apt-get install -y docker.io
           usermod -aG docker vagrant
           systemctl enable --now docker
         SHELL
         node.vm.provider "virtualbox" do |vb|
           vb.memory = "1024"
           vb.cpus = 1
         end
       end
     end
   end
   ```
   > 💻 `docker.io` é o pacote empacotado pelo próprio Ubuntu — suficiente para este desafio. Em um cenário de produção real, prefira o repositório oficial do Docker para ter uma versão mais recente.

2. Suba as três VMs e forme o cluster:
   ```bash
   vagrant up
   vagrant ssh swarm-manager -c "docker swarm init --advertise-addr 192.168.56.30"
   ```
   Copie o comando `docker swarm join --token SWMTKN-...` da saída anterior e rode em cada worker:
   ```bash
   vagrant ssh swarm-worker1 -c "docker swarm join --token SWMTKN-... 192.168.56.30:2377"
   vagrant ssh swarm-worker2 -c "docker swarm join --token SWMTKN-... 192.168.56.30:2377"
   ```

3. Confirme o cluster real com 3 nós:
   ```bash
   vagrant ssh swarm-manager -c "docker node ls"
   ```

4. Publique a stack do Cenário 5 a partir do manager (copie o `docker-compose-swarm.yaml` e o `.env` para dentro da VM, por exemplo com `vagrant upload`, ou clone o `gotodolist` diretamente dentro da VM).

5. **O teste que só faz sentido com múltiplos nós de verdade:** derrube um worker de propósito e observe o Swarm reagendar sozinho as tarefas que estavam nele:
   ```bash
   vagrant halt swarm-worker1
   vagrant ssh swarm-manager -c "docker service ps gotodolist_api"
   ```

6. Encerre tudo:
   ```bash
   vagrant destroy -f
   ```

---

## Tabela-Resumo (Cheat Sheet)

| Sintoma observado | Causa provável | Primeiro comando de diagnóstico | Como corrigir |
| :--- | :--- | :--- | :--- |
| `denied: denied` no `docker push` | Token sem escopo `write:packages`, ou usuário incorreto/maiúsculo na tag | Conferir a tag com `docker images` | Gerar PAT com o escopo certo; usar nome de usuário em minúsculas |
| Imagem multi-stage não reduziu de tamanho | Estágio final ainda copiando `node_modules`/ferramental de build | `docker history <imagem>` | Garantir que só `COPY --from=builder` copie os artefatos finais |
| Rota interna do SPA retorna `404` atrás do Nginx | Falta regra de *fallback* para roteamento do lado do cliente | `curl -I` em uma rota profunda | Adicionar `try_files $uri $uri/ /index.html;` |
| `docker compose up` não aplicou o limite de memória | CLI antiga (`docker-compose` Python/V1) em vez do plugin `docker compose` (V2) | `docker compose version` | Atualizar para o plugin V2 |
| Container reiniciando sem parar (`Restarting`) após aplicar limites | Limite de memória menor do que o necessário para o processo inicializar | `docker inspect --format '{{.State.OOMKilled}}'` | Aumentar o limite (com critério) ou investigar consumo real da aplicação |
| `docker stack deploy` ignora um serviço | Compose usa `build:` sem `image:` — Swarm não constrói imagens | Aviso `Ignoring unsupported options: build` no próprio comando | Publicar a imagem em um registry e referenciar via `image:` |
| Variáveis do `.env` não aparecem no Swarm | `docker stack deploy` não lê `.env` automaticamente como o `docker compose` | `docker service inspect --pretty` | Exportar as variáveis no shell antes (`set -a; source .env; set +a`) |
| `docker swarm init` falha com erro de múltiplos endereços | Máquina com mais de uma interface de rede ativa | A própria mensagem de erro já indica isso | Especificar `--advertise-addr <ip>` |

---

## Entregável

Preencham a tabela abaixo para **todos os cenários do núcleo (1 a 4)**. Cenários bônus ficam como desafio.

| Cenário | O que foi configurado/observado | Causa raiz ou motivação técnica | Comando de verificação utilizado | Resultado ou correção aplicada |
| :--- | :--- | :--- | :--- | :--- |
| 1 — Build e push manual para o GHCR | | | | |
| 2 — Multi-stage (tamanho antes/depois) | | | | |
| 3 — Limites de CPU/memória aplicados | | | | |
| 4 — OOM Kill controlado | | | | |
| 5 — Swarm: stack deploy (bônus) | | | | |
| 6 — Swarm: scale/rolling update (bônus) | | | | |

---

### Armadilhas conhecidas
- **Visibilidade padrão do GHCR:** todo pacote publicado pela primeira vez nasce **privado**, mesmo que o repositório de origem seja público. Quem for consumir a imagem de outra máquina precisa estar logado ou o pacote precisa ser tornado público manualmente.
- **`docker-compose` (V1, Python) vs `docker compose` (V2, plugin):** só o V2 aplica `deploy.resources` fora do modo Swarm. Se os limites "não fizerem efeito nenhum", a primeira suspeita é a versão da CLI.
- **`docker stack deploy` não lê `.env`:** diferente de `docker compose up`, é preciso exportar as variáveis manualmente no shell antes (`set -a; source .env; set +a`).
- **`depends_on` com `condition: service_healthy` não é respeitado em modo Swarm** — só em `docker compose up` local.
- **Limpeza de imagens acumuladas:** este laboratório gera várias tags (`v1`, `v2`, `latest`) e reconstrói imagens repetidamente. Usem `docker image prune` e `docker system df` para não acumular lixo no disco do laboratório.
- **Higiene do token:** se o laboratório for em máquina compartilhada, revoguem o PAT (`docker logout ghcr.io` não invalida o token em si — é preciso deletá-lo na própria página de tokens do GitHub).
- **WSL2/máquinas com VPN:** `docker swarm init` tende a falhar por múltiplas interfaces nesses ambientes.
