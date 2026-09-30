# Laboratório 6 — Deploy com Portainer na OCI, CD Automatizado via Webhook, Domínio, Reverse Proxy com HTTPS e Database as a Service (DBaaS)

**Disciplina:** Infraestrutura de TI para Sistemas na Internet  
**Aula de referência:** Módulo 4 — Aula 14 (IaaS na OCI: Compute, Redes Virtuais e Acesso Seguro), Aula 15 (PaaS e Serverless na OCI) e Aula 16 (Bancos de Dados Gerenciados e Object Storage na OCI), com consolidação prática do Módulo 5 — Aula 18 (Pipeline de Deploy Contínuo).  
**Projetos usados como exemplo:**
- Fork pessoal de [`gotodolist`](https://github.com/elton-bt/gotodolist) (Go + PostgreSQL), ou aplicação própria com imagens de container publicadas no GHCR (workflows `ci.yml` e `release.yml` funcionando dos Laboratórios 4 e 5).  
**Objetivo:** sair da teoria ("o que é deploy na nuvem", "o que é um reverse proxy", "o que é DBaaS") para a prática de **implantar uma stack de produção real em uma VM na Oracle Cloud usando o Portainer Business Edition, automatizar o deploy contínuo com webhooks chamados pelo GitHub Actions, registrar um domínio gratuito via Namecheap (GitHub Student Developer Pack), configurar um reverse proxy com Nginx Proxy Manager para servir a aplicação via HTTPS com certificado TLS válido do Let's Encrypt, e migrar o banco de dados de um container local para um serviço gerenciado (DBaaS) na OCI** — fechando o ciclo completo de infraestrutura de produção que conecta tudo o que foi aprendido nos Módulos 1 a 4.

> ℹ️ **Por que este documento existe:** os Laboratórios anteriores ensinam a criar uma VM na OCI, subir um container manualmente via `docker run` e acessar pelo IP público. Este documento é a **versão aprofundada**: em vez de um `docker run` avulso, vocês implantarão uma stack completa com gerenciamento visual (Portainer), construirão um pipeline de **CD real** que atualiza a produção automaticamente a cada release, colocarão a aplicação atrás de um domínio próprio com HTTPS — exatamente como uma aplicação profissional funciona no mundo real — e experimentarão na prática o conceito de DBaaS substituindo o container de PostgreSQL por um banco gerenciado na nuvem.

> ⚠️ **Nota de honestidade técnica:** os comandos, configurações e capturas deste laboratório foram validados em uma instância `VM.Standard.A1.Flex` (Ampere ARM, Always Free) rodando Ubuntu 24.04 na OCI, com Docker Engine 29.6.1 e Portainer Business Edition 2.25 em setembro de 2026. A interface do Portainer, os campos exatos do Console da OCI e os passos do Namecheap **mudam com o tempo** — sempre que o texto disser "resultado observado" ou mostrar um screenshot, valide no seu próprio ambiente antes de aceitar. O Portainer Business Edition oferece gerenciamento de **3 nós gratuitos** (mais que suficiente para este curso).

---

## Como este laboratório está organizado

| Bloco | Cenários | Quando fazer |
| :--- | :--- | :--- |
| **Preparação** | Verificar VM na OCI com Docker instalado, criar conta no Portainer BE, verificar workflows `ci.yml` e `release.yml` funcionando no repositório | Sempre, primeiro (~15 min) |
| **Núcleo** | **1) Portainer e Stack na OCI:** Instalar Portainer BE na VM, criar uma stack com a aplicação do GHCR, liberar portas na Security List e acessar via IP público.<br>**2) CD Automatizado com Webhook:** Criar o webhook da stack no Portainer, criar o workflow `cd.yml` no GitHub Actions e testar o fluxo completo CI → Release → CD → nova versão em produção.<br>**3) Domínio com Namecheap:** Registrar um domínio `.me` gratuito via GitHub Student Developer Pack, configurar o A Record apontando para o IP público da VM.<br>**4) Reverse Proxy + HTTPS com Nginx Proxy Manager:** Subir o NPM via Portainer, configurar proxy host com o domínio registrado e obter certificado TLS automático do Let's Encrypt.
| **Bônus** | **5) DBaaS — PostgreSQL Gerenciado na OCI:** Provisionar o serviço OCI Database with PostgreSQL, migrar a aplicação para usar o banco gerenciado em vez do container local, comparar os trade-offs na prática.<br>**Desafio Avançado:** Configurar Uptime Kuma via Portainer para monitorar a disponibilidade da aplicação em produção.

Cada cenário segue rigorosamente a mesma estrutura: **Causa raiz / Fundamento teórico** → **Como configurar** → **Como observar/diagnosticar** → **Como validar** → **Como usar a LLM aqui**.

---

## Como usar a LLM neste laboratório (leia isso primeiro)

Não peça à LLM para gerar o `docker-compose.yml` do Portainer ou o workflow de CD inteiro e colar às cegas. Neste laboratório vocês estão lidando com **infraestrutura de produção exposta na Internet** — um erro pode expor dados, abrir portas desnecessárias ou quebrar o fluxo de deploy de todo o time.

Use este protocolo de 4 passos:

1. **Descreva o contexto real e específico** — não só "me dê o compose do Portainer", mas "estou rodando uma instância ARM `A1.Flex` na OCI, o Docker está na versão X, e ao tentar acessar a porta 9443 recebo este erro exato: (cole o erro)".
2. **Peça à LLM duas coisas específicas:**
   - (a) A causa raiz no nível da infraestrutura (ex.: a Security List da OCI bloqueia a porta? O firewall `iptables`/`nftables` do Ubuntu está filtrando? O Portainer está ouvindo em `0.0.0.0` ou `127.0.0.1`?).
   - (b) **Um comando de verificação** que comprove a hipótese antes de aceitar (ex.: `sudo iptables -L -n`, `curl -k https://localhost:9443`, `ss -tlnp | grep 9443`).
3. **Rode o comando de verificação você mesmo** e compare com a previsão da LLM.
4. **Só depois aplique a correção** — e valide de novo, preferencialmente de fora da VM (do seu navegador local) para confirmar que o acesso externo funciona.

Uma LLM que só te dá a resposta pronta sem te ensinar a confirmá-la não está te ensinando infraestrutura — está só terceirizando o problema.

---

## Preparação do Ambiente (compartilhada — fazer uma vez, ~15 min)

### 1. Verificar a VM na OCI com Docker instalado

Este laboratório **assume** que você já completou o Laboratório Prático da Aula anterior, portanto já possui:
- Uma instância Compute rodando na OCI (preferencialmente `VM.Standard.A1.Flex`, Always Free).
- Docker Engine instalado na VM.
- Acesso SSH à VM (via OCI Bastion ou chave SSH).

Conecte-se à VM e confirme:

```bash
# Conecte-se via SSH (substitua pelo IP público da sua VM)
ssh -i ~/.ssh/id_ed25519 ubuntu@<IP_PUBLICO_DA_VM>

# Confirme que o Docker está rodando
docker version
docker compose version
```

> 💡 Se você usou o OCI Bastion (recomendado na Aula 14), o comando SSH será o que o Console da OCI gerou para você. Se preferir acessar diretamente, certifique-se de que a porta 22 está liberada na Security List (mas lembre-se: o Bastion é a forma mais segura).

### 2. Verificar que os workflows CI e Release estão funcionando

Antes de criar o pipeline de CD, confirme que seu repositório tem os workflows dos Laboratórios 4 e 5 operacionais:

1. Acesse **Actions** no seu repositório GitHub.
2. Confirme que `ci.yml` executa com sucesso a cada push para `main`.
3. Confirme que `release.yml` executa com sucesso ao criar uma tag `v*` e publica a imagem no GHCR.

Se algum deles não está funcionando, **pare e resolva primeiro** — o CD depende de ambos.

### 3. Anotar informações da VM que serão usadas ao longo do laboratório

```bash
# IP público da VM (anote — será usado várias vezes)
curl -s ifconfig.me
echo ""

# Arquitetura da VM (importante para confirmar compatibilidade de imagens)
uname -m
# Esperado para A1.Flex: aarch64 (ARM 64-bit)
# Esperado para E2.1.Micro: x86_64 (AMD 64-bit)
```

> ⚠️ Se a sua VM é ARM (`aarch64`), certifique-se de que as imagens Docker que você vai usar têm build para `linux/arm64`. As imagens oficiais do Portainer, Nginx Proxy Manager e PostgreSQL já suportam ARM. Se a sua aplicação foi publicada no GHCR apenas para `amd64`, volte ao `release.yml` do Laboratório 5 e adicione multi-arch com Docker Buildx (`linux/amd64,linux/arm64`).

### 4. Checklist de baseline

- [ ] Conectei via SSH na VM da OCI e `docker version` retorna sucesso.
- [ ] `docker compose version` mostra a versão do plugin (V2/V5+).
- [ ] Workflows `ci.yml` e `release.yml` passando no repositório GitHub.
- [ ] Anotei o **IP público** da VM.
- [ ] Confirmei a **arquitetura** da VM (`aarch64` ou `x86_64`).
- [ ] A imagem da minha aplicação está publicada no GHCR, **funciona corretamente** e é compatível com a arquitetura da VM.

---

# NÚCLEO

## Cenário 1 — Portainer Business Edition e Stack de Produção na OCI

### Causa raiz / Fundamento teórico

Até agora, todo gerenciamento de containers foi feito via CLI (`docker run`, `docker compose up`). Isso funciona bem para desenvolvimento, mas em **produção** traz desafios:

- **Visibilidade:** sem uma interface visual, é difícil ter uma visão geral de todos os containers, seus status, logs e consumo de recursos.
- **Acesso compartilhado:** nem todo membro da equipe precisa (ou deveria) ter acesso SSH ao servidor. Uma interface web permite gerenciar containers sem expor o terminal.
- **Stacks declarativas:** o Portainer permite definir stacks (equivalentes a `docker-compose.yml`) diretamente na interface, com versionamento e webhooks para deploy automatizado.
- **Portainer Business Edition (BE):** versão comercial com funcionalidades extras (RBAC, registries externos, GitOps, Webhooks), **gratuita para até 3 nós** — mais que suficiente para o curso.

O fluxo que vamos construir:

```
Imagem no GHCR (ghcr.io/<usuario>/gotodolist:latest)
         │
         ▼
   Portainer BE (na VM da OCI)
         │
         ▼
   Stack (docker-compose) rodando na VM
         │
         ▼
   Aplicação acessível via IP público + porta
```

### Como configurar

#### 1.1 Instalar o Portainer Business Edition

Na VM da OCI, execute:

```bash
# Criar o volume para persistir os dados do Portainer
docker volume create portainer_data

# Subir o Portainer BE (a imagem é a mesma para AMD e ARM)
docker run -d \
  -p 8000:8000 \
  -p 9443:9443 \
  --name portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ee:lts
```

| Flag | Significado |
| :--- | :--- |
| `-p 9443:9443` | Interface web do Portainer (HTTPS auto-assinado) |
| `-p 8000:8000` | Porta para agentes Portainer (comunicação entre nós — usada em clusters) |
| `-v /var/run/docker.sock:...` | Dá ao Portainer acesso ao Docker Engine do host |
| `--restart=always` | Reinicia automaticamente se o container cair ou a VM reiniciar |
| `portainer-ee:lts` | Portainer **Enterprise Edition** (Business) na versão LTS |

> 💡 A diferença entre `portainer-ce` (Community Edition) e `portainer-ee` (Business/Enterprise Edition) é que a versão EE inclui RBAC, suporte a registries externos com autenticação simplificada, webhooks nativos para stacks e GitOps — todos recursos que usaremos neste laboratório. A versão EE é **gratuita para até 3 nós**.

#### 1.2 Liberar a porta 9443 na Security List da OCI

Antes de acessar o Portainer pelo navegador, é preciso liberar a porta na Security List da subnet pública da OCI:

1. No Console da OCI, navegue até: **Networking** → **Virtual Cloud Networks** → selecione a VCN → selecione a **subnet pública**.
2. Clique na **Security List** associada à subnet.
3. Clique em **Add Ingress Rules** e adicione:

| Campo | Valor |
| :--- | :--- |
| Source Type | CIDR |
| Source CIDR | `0.0.0.0/0` |
| IP Protocol | TCP |
| Destination Port Range | `9443` |
| Description | Portainer Web UI |

4. Clique em **Add Ingress Rules**.

> ⚠️ **Firewall do Ubuntu:** além da Security List da OCI (que é o firewall de **borda** da rede virtual), o Ubuntu na OCI vem com regras `iptables` padrão que podem bloquear portas. Execute na VM:
> ```bash
> sudo iptables -F
> sudo iptables-save | sudo tee /etc/iptables/rules.v4
> sudo reboot
> ```
> Essas regras dizem desabilitam todas as regras existentes. Sem isso, a Security List da OCI liberou o tráfego até a VM, mas o iptables do SO **descarta** na camada do host.

#### 1.3 Configuração inicial do Portainer

1. Abra no navegador: `https://<IP_PUBLICO_DA_VM>:9443`

   > ⚠️ O navegador vai alertar sobre certificado auto-assinado. Isso é esperado — o Portainer gera um certificado próprio na primeira execução. Aceite o risco (no Chrome: "Avançado" → "Prosseguir para..."). Resolveremos isso com um certificado válido no Cenário 4.

2. **Crie o usuário administrador:**
   - Username: `admin`
   - Password: escolha uma senha forte (mínimo 12 caracteres)

3. **Ative a licença Business Edition:**
   - Na tela seguinte, selecione a opção de licença gratuita (até 3 nós).
   - Ou crie uma conta em [portainer.io](https://www.portainer.io/take-3) para obter a chave de licença gratuita.

4. **Conecte o ambiente local:**
   - Selecione **"Get Started"** → o Portainer já detecta o Docker Engine local (graças ao volume do socket que montamos).
   - Você verá o environment **"local"** listado com status verde.

#### 1.4 Configurar o Registry do GHCR no Portainer

Para que o Portainer consiga baixar imagens do seu GHCR (caso o pacote seja privado), configure o registry:

1. No Portainer, vá em **Settings** → **Registries** → **Add registry**.
2. Selecione **Custom registry** e preencha:

| Campo | Valor |
| :--- | :--- |
| Name | `GitHub Container Registry` |
| Registry URL | `ghcr.io` |
| Authentication | ✅ habilitado |
| Username | `<seu_usuario_github>` |
| Password | O PAT (Personal Access Token) com escopo `read:packages` |

3. Clique em **Add registry**.

> 💡 Se o seu pacote no GHCR é **público**, essa configuração de autenticação não é estritamente necessária — mas é uma boa prática configurar de qualquer forma, pois o GHCR tem rate limits mais generosos para requisições autenticadas.

#### 1.5 Criar a Stack da aplicação

1. No Portainer, vá em **Stacks** → **Add stack**.
2. Dê o nome: `gotodolist` (ou o nome da sua aplicação).
3. Selecione **Web editor** e cole o conteúdo do docker-compose:

```yaml
services:
  db:
    image: postgres:17-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${DB_NAME:-gotodolist}
      POSTGRES_USER: ${DB_USER:-gotodolist}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-12345}
    mem_limit: 256M
    cpu_shares: 64
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

  api:
    image: ghcr.io/${GHCR_OWNER:-elton-bt}/gotodolist-api:${IMAGE_TAG:-latest}
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    mem_limit: 256M
    cpu_shares: 64
    environment:
      DB_HOST: ${DB_HOST:-db}
      DB_PORT: ${DB_PORT:-5432}
      DB_NAME: ${DB_NAME:-gotodolist}
      DB_USER: ${DB_USER:-gotodolist}
      DB_PASSWORD: ${DB_PASSWORD:-12345}
      DB_SSLMODE: ${DB_SSLMODE:-disable}
      CORS_ALLOW_ORIGIN: ${CORS_ALLOW_ORIGIN:-*}
    ports:
      - "${API_HOST_PORT:-8081}:8081"
    networks:
      - frontend_api
      - api_db
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.0:8081/health"]
      interval: 20s
      timeout: 5s
      retries: 5
      start_period: 15s

  frontend:
    image: ghcr.io/${GHCR_OWNER:-elton-bt}/gotodolist-frontend:${IMAGE_TAG:-latest}
    restart: unless-stopped
    mem_limit: 256M
    cpu_shares: 64
    depends_on:
      api:
        condition: service_healthy
    environment:
      GOTODOLIST_API_BASE_URL: ${GOTODOLIST_API_BASE_URL:-}
    ports:
      - "${FRONTEND_HOST_PORT:-8082}:8080"
    networks:
      - frontend_api

volumes:
  postgres-data:

networks:
  frontend_api:
  api_db:
```

- ⚠️ Substitua `<SEU_USUARIO>` pelo seu usuário real do GitHub (em **minúsculas** — o GHCR é case-sensitive e sempre usa lowercase).
- ⚠️ Você pode usar variáveis de ambiente no Portainer para definir `GHCR_OWNER`, `IMAGE_TAG`, `DB_NAME`, etc., ou deixar os defaults do compose. Também pode usar o **Web editor** do Portainer para definir variáveis de ambiente na interface bem como fazer o upload de um arquivo `.env` se preferir.

4. Clique em **Deploy the stack**.

#### 1.6 Liberar a porta 8082 e 8081 na Security List

Repita o mesmo processo do passo 1.2, mas agora para a porta **8080**:

**Security List da OCI:**

| Campo | Valor |
| :--- | :--- |
| Source CIDR | `0.0.0.0/0` |
| IP Protocol | TCP |
| Destination Port Range | `8082` |
| Description | Aplicação Web (GoToDoList) |

| Campo | Valor |
| :--- | :--- |
| Source CIDR | `0.0.0.0/0` |
| IP Protocol | TCP |
| Destination Port Range | `8081` |
| Description | API (GoToDoList) |


### Como observar/diagnosticar

1. **No Portainer:** vá em **Stacks** → `gotodolist` — você deve ver os três serviços (`app`, `api` e `postgres`) com status **running**.

2. **Logs no Portainer:** clique em um container → ícone de **Logs** — equivalente a `docker logs`, mas visual.

3. **No navegador:** acesse `http://<IP_PUBLICO_DA_VM>:8082` — a aplicação deve carregar.

4. **Via terminal (validação cruzada):**
   ```bash
   curl -s -o /dev/null -w "%{http_code}" http://localhost:8082
   # Esperado: 200
   ```

### Como validar

- [ ] Portainer BE acessível em `https://<IP>:9443`.
- [ ] Stack `gotodolist` com ambos os serviços em status **running** no Portainer.
- [ ] Aplicação acessível em `http://<IP>:8082` a partir do navegador local (fora da VM).
- [ ] Criou uma tarefa no GoToDoList e ela persistiu após atualizar a página (o banco está funcionando).

### Como usar a LLM aqui

> "Estou tentando acessar `https://<IP>:9443` do meu navegador e a conexão expira (timeout). Na VM, `curl -k https://localhost:9443` funciona. A Security List da OCI tem a porta 9443 liberada para `0.0.0.0/0`. Me ajude a diagnosticar: (a) quais camadas de firewall podem estar bloqueando entre o meu navegador e o container do Portainer, e (b) um comando que eu possa rodar na VM para confirmar se o `iptables` do Ubuntu está descartando o tráfego de entrada na porta 9443."

---

## Cenário 2 — CD Automatizado com Webhook do Portainer

### Causa raiz / Fundamento teórico

Nos Laboratórios 4 e 5, construímos os pipelines de **CI** (testa e valida o código) e **Release** (publica a imagem no GHCR). Falta a última peça do ciclo: o **Deploy Contínuo (CD)** — que pega a imagem recém-publicada e **atualiza automaticamente a aplicação em produção**.

O fluxo completo que vamos construir:

```
push para main
     │
     ▼
 ci.yml roda
(lint + testes + segurança)
     │
     ▼
 código validado ✅
     │
     ▼
git tag v1.2.0
     │
     ▼
 release.yml roda
(build + push imagem para GHCR)
     │
     ▼
 cd.yml roda
(chama webhook do Portainer)
     │
     ▼
Portainer faz pull da nova imagem
+ reinicia os containers da stack
     │
     ▼
Nova versão em produção 🚀
```

O **webhook** é uma URL secreta que o Portainer gera para cada stack. Quando essa URL recebe uma requisição HTTP POST, o Portainer:
1. Faz `docker pull` da imagem mais recente de cada serviço da stack.
2. Recria os containers com a nova imagem.
3. Mantém os volumes e redes intactos.

Isso é equivalente a alguém executar `docker compose pull && docker compose up -d` manualmente — mas disparado automaticamente pelo pipeline.

### Como configurar

#### 2.1 Criar o webhook da stack no Portainer

1. No Portainer, vá em **Stacks** → `gotodolist`.
2. Habilite o toggle **"Stack webhook"** (geralmente fica na parte inferior da configuração da stack, ou em **Stack details**).
3. O Portainer gera uma URL no formato:
   ```
   https://<IP_PUBLICO_DA_VM>:9443/api/stacks/webhooks/<TOKEN_UNICO>
   ```
4. **Copie essa URL** — ela será usada como secret no GitHub.

> 🔒 Essa URL **é um segredo**. Qualquer pessoa que a possua pode disparar um redeploy da sua stack. Nunca a cole em código-fonte, documentação pública ou mensagens em grupo. Ela vai como um **GitHub Secret** (passo seguinte).

> 💡 O webhook do Portainer usa o certificado auto-assinado na porta 9443. Para que o `curl` no GitHub Actions aceite esse certificado, usaremos a flag `-k` (insecure) no workflow. Na prática de produção, o ideal é que o Portainer esteja atrás de um reverse proxy com certificado válido (o que faremos no Cenário 4 — quando chegar nesse ponto você pode remover o `-k`).

#### 2.2 Configurar os secrets no repositório GitHub

1. No GitHub, acesse **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.
2. Crie o seguinte secret:

| Nome | Valor |
| :--- | :--- |
| `PORTAINER_WEBHOOK_URL` | A URL do webhook copiada no passo anterior |

#### 2.3 Criar o workflow `cd.yml`

Crie o arquivo `.github/workflows/cd.yml`:

```yaml
name: CD

on:
  workflow_run:
    workflows: ["Release"]
    types:
      - completed

jobs:
  deploy:
    name: Deploy via Portainer Webhook
    runs-on: ubuntu-latest
    if: ${{ github.event.workflow_run.conclusion == 'success' }}

    steps:
      - name: Aguardar propagação da imagem no GHCR
        run: sleep 30

      - name: Chamar webhook do Portainer
        run: |
          HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST -k \
            "${{ secrets.PORTAINER_WEBHOOK_URL }}")
          echo "HTTP Status: $HTTP_STATUS"
          if [ "$HTTP_STATUS" -ne 204 ]; then
            echo "❌ Webhook retornou status $HTTP_STATUS (esperado: 204)"
            exit 1
          fi
          echo "✅ Webhook chamado com sucesso — Portainer está re-deployando a stack"
```

#### 2.4 Entenda o workflow

| Seção | O que faz |
| :--- | :--- |
| `on: workflow_run` | Dispara **após** o workflow "Release" terminar (não roda a cada push) |
| `if: conclusion == 'success'` | Só executa se o Release **passou** — evita deploy de versões quebradas |
| `sleep 30` | Dá tempo para a imagem propagar no GHCR antes do Portainer tentar baixá-la |
| `curl -X POST -k` | Chama o webhook do Portainer; `-k` aceita o certificado auto-assinado |
| Validação do HTTP status | O webhook do Portainer retorna `204 No Content` em caso de sucesso |

> 💡 **Por que `workflow_run` em vez de colocar o deploy no `release.yml`?** Separar o CD em um workflow próprio traz benefícios:
> - **Rastreabilidade:** na aba Actions, cada etapa (CI, Release, CD) aparece como um workflow separado — fica claro onde falhou.
> - **Reusabilidade:** você pode disparar o CD manualmente (re-run) sem precisar criar uma nova tag.
> - **Desacoplamento:** pode desativar o CD sem afetar o CI ou o Release.

#### 2.5 Enviar o workflow e testar o fluxo completo

```bash
git add .github/workflows/cd.yml
git commit -m "ci: adicionar pipeline de CD com webhook do Portainer"
git push origin main
```

Agora, teste o fluxo completo:

```bash
# 1. Faça uma alteração visível na aplicação
#    (ex: mude o título da página, uma cor, uma mensagem)

# 2. Commit e push
git add .
git commit -m "feat: alterar título para testar CD"
git push origin main

# 3. Espere o CI passar, e a tag e release serem criadas automaticamente (caso você tenha utilizado o release-please no release.yml do Lab5). Se não, crie uma tag manualmente:
git tag v1.2.0
git push origin v1.2.0
```

### Como observar/diagnosticar

1. **Na aba Actions do GitHub**, acompanhe a sequência:
   - **CI** → ✅ (roda no push)
   - **Release** → ✅ (roda no push da tag e publica a imagem no GHCR)
   - **CD** → ✅ (roda após o Release completar)

2. **No Portainer**, vá em **Stacks** → `gotodolist` — observe que os containers foram recriados (o campo "Created" mostra um timestamp recente).

3. **No navegador**, acesse `http://<IP>:8082` — a alteração feita no código deve estar visível.

4. **Via terminal na VM:**
   ```bash
   # Verificar a imagem que está rodando
   docker inspect gotodolist-app-1 --format '{{.Config.Image}}'
   # Verificar quando o container foi criado
   docker inspect gotodolist-app-1 --format '{{.Created}}'
   ```

> ⚠️ **Erro comum — "CD disparou mas o Portainer não atualizou":** isso geralmente acontece quando o webhook funciona (retorna 204), mas o Portainer faz `pull` antes da imagem nova estar disponível no GHCR. A solução é aumentar o `sleep` no workflow ou, melhor, adicionar um step que verifica a existência da nova tag no GHCR antes de chamar o webhook:
> ```yaml
>       - name: Verificar imagem no GHCR
>         run: |
>           for i in $(seq 1 12); do
>             if docker manifest inspect ghcr.io/${{ github.repository }}:latest > /dev/null 2>&1; then
>               echo "✅ Imagem encontrada no GHCR"
>               break
>             fi
>             echo "⏳ Aguardando imagem... tentativa $i/12"
>             sleep 10
>           done
> ```

### Como validar

- [ ] O workflow `cd.yml` existe em `.github/workflows/` e aparece na aba Actions.
- [ ] Após criar uma nova tag, os três workflows rodam em sequência: CI → Release → CD.
- [ ] O CD chama o webhook com sucesso (status 204 nos logs do workflow).
- [ ] A aplicação em `http://<IP>:8082` mostra a alteração feita no código.
- [ ] No Portainer, os containers da stack foram recriados com a imagem nova.

### Como usar a LLM aqui

> "Meu workflow `cd.yml` disparou após o Release, mas o status HTTP retornado pelo webhook foi 403. O secret `PORTAINER_WEBHOOK_URL` está configurado corretamente. (a) Quais motivos podem causar um 403 no webhook do Portainer, e (b) como posso testar o webhook manualmente com `curl` de dentro da VM para isolar se o problema é no Portainer ou na rede?"

---

## Cenário 3 — Registrando um Domínio com Namecheap (GitHub Student Developer Pack)

### Causa raiz / Fundamento teórico

Acessar uma aplicação via `http://IP-PUBLICO-VM:8082` funciona, mas tem vários problemas:

- **Memorização:** ninguém decora endereços IP.
- **Porta alta:** a porta `8082` não é a padrão para HTTP (80) nem HTTPS (443). Muitas redes corporativas e de campus bloqueiam portas altas.
- **Sem HTTPS:** sem um domínio, não é possível obter um certificado TLS válido do Let's Encrypt (ele valida a propriedade do domínio). Sem HTTPS, dados trafegam em texto plano — inaceitável para qualquer aplicação que lide com informações de usuários.
- **Profissionalismo:** nenhuma aplicação séria é acessada por IP + porta alta.

O **DNS (Domain Name System)** resolve esse problema: ele traduz nomes legíveis (`meuapp.me`) em endereços IP (`143.47.105.32`). O **registro A** (A Record) é o tipo mais básico de registro DNS — ele simplesmente diz "este nome aponta para este IPv4".

O **Namecheap** é um registrador de domínios que, através do **GitHub Student Developer Pack**, oferece um domínio `.me` **gratuito por 1 ano** — perfeito para este laboratório.

### Como configurar

#### 3.1 Ativar o benefício do Namecheap no GitHub Student Developer Pack

1. Acesse [`https://education.github.com/pack`](https://education.github.com/pack).
2. Se ainda não tem o Student Pack ativado, clique em **"Get your pack"** e siga o processo de verificação (carteirinha estudantil ou e-mail institucional).
3. Na lista de benefícios, encontre o **Namecheap** e clique em **"Get access"**.
4. Você será redirecionado ao Namecheap com o benefício aplicado.

> 💡 O benefício inclui um domínio `.me` gratuito por 1 ano e um certificado SSL (que não usaremos, pois o Let's Encrypt é gratuito e renovável automaticamente). Se o `.me` não estiver disponível, outros TLDs podem ter promoções — mas o `.me` costuma ser o mais acessível para estudantes.

#### 3.2 Registrar o domínio

1. No Namecheap, busque um nome de domínio disponível (ex: `seunome-dev.me`, `seunome.me`).
2. Adicione ao carrinho e finalize o checkout (custo: $0,00 com o cupom do Student Pack).
3. Acesse **Dashboard** → **Domain List** → clique em **Manage** no domínio registrado.

#### 3.3 Configurar o A Record

1. Na página de gerenciamento do domínio, vá em **Advanced DNS**.
2. Remova quaisquer registros padrão que o Namecheap tenha adicionado (como registros `CNAME` para parking pages).
3. Adicione um novo registro:

| Type | Host | Value | TTL |
| :--- | :--- | :--- | :--- |
| A Record | `@` | `<IP_PUBLICO_DA_VM>` | Automatic |

- **`@`** significa o domínio raiz (ex: `meuapp.me` sem nenhum subdomínio).
- **Value** é o IP público da sua VM na OCI.

4. (Opcional) Adicione um segundo registro para o subdomínio `www`:

| Type | Host | Value | TTL |
| :--- | :--- | :--- | :--- |
| A Record | `www` | `<IP_PUBLICO_DA_VM>` | Automatic |

5. Clique em **Save All Changes**.

> ⏱️ **Propagação de DNS:** a alteração pode levar de **poucos minutos** a até **48 horas** para propagar globalmente, dependendo do TTL anterior e dos caches de DNS ao longo do caminho. Na prática, para um domínio recém-registrado, costuma ser bem rápido (1-10 minutos).

### Como observar/diagnosticar

Verifique se o DNS está resolvendo corretamente:

```bash
# Da sua máquina local (não da VM)
nslookup seudominio.me
# Ou com dig (mais detalhado):
dig seudominio.me +short
# Esperado: <IP_PUBLICO_DA_VM>

# Teste se a aplicação responde pelo domínio:
curl -s -o /dev/null -w "%{http_code}" http://seudominio.me:8082
# Esperado: 200
```

> 💡 Se `nslookup` retornar o IP correto mas o `curl` falhar, o DNS está funcionando — o problema está no firewall ou na aplicação. Se `nslookup` não retornar nada, a propagação ainda não chegou no seu resolver DNS. Tente usar um resolver público para testar:
> ```bash
> nslookup seudominio.me 8.8.8.8
> ```

### Como validar

- [ ] Domínio `.me` registrado no Namecheap com custo $0,00 (Student Pack).
- [ ] A Record configurado apontando `@` para o IP público da VM.
- [ ] `nslookup seudominio.me` retorna o IP correto.
- [ ] `http://seudominio.me:8082` abre a aplicação no navegador.

### Como usar a LLM aqui

> "Configurei o A Record no Namecheap há 30 minutos, mas `nslookup meudominio.me` ainda retorna 'NXDOMAIN'. Já confirmei que digitei o domínio corretamente no Namecheap. (a) Explique as possíveis causas de atraso na propagação DNS e como os caches de DNS intermediários funcionam, e (b) me dê um comando para consultar diretamente os nameservers autoritativos do Namecheap para verificar se o registro já está lá no lado deles."

---

## Cenário 4 — Reverse Proxy com Nginx Proxy Manager + HTTPS

### Causa raiz / Fundamento teórico

Mesmo com o domínio configurado, a aplicação ainda está acessível apenas por `http://seudominio.me:8082` — com dois problemas graves:

1. **Porta alta (8082):** o usuário precisa digitar a porta manualmente. O padrão HTTP é a porta 80 e HTTPS é a 443 — quando você acessa `https://github.com`, o navegador assume a porta 443 automaticamente.

2. **Sem criptografia (HTTP em vez de HTTPS):** todo o tráfego entre o navegador e o servidor é transmitido em texto plano. Qualquer pessoa na mesma rede (Wi-Fi do campus, por exemplo) pode interceptar os dados.

Um **reverse proxy** resolve ambos os problemas: ele fica na frente da aplicação, escutando nas portas padrão (80/443), e repassa o tráfego para o container interno na porta alta.

```
                                     VM da OCI
                              ┌────────────────────────────┐
                              │                            │
usuário ──HTTPS/443──▶ Nginx Proxy Manager ──HTTP/8080──▶ app (gotodolist)
                              │       │                    │
                              │       │──5432──▶ postgres  │
                              │       │                    │
                              │   certificado Let's Encrypt│
                              └────────────────────────────┘
```

O **Nginx Proxy Manager (NPM)** é uma interface web que simplifica a configuração de reverse proxy + HTTPS:
- Configura virtual hosts (proxy hosts) apontando domínios para containers internos.
- Obtém e **renova automaticamente** certificados TLS do Let's Encrypt.
- Tudo via interface gráfica — sem editar `nginx.conf` manualmente.

### Como configurar

#### 4.1 Liberar as portas 80 e 443 na Security List e no iptables

**Security List da OCI — adicionar duas regras de Ingress:**

| Source CIDR | Protocol | Port Range | Description |
| :--- | :--- | :--- | :--- |
| `0.0.0.0/0` | TCP | `80` | HTTP (redirect para HTTPS) |
| `0.0.0.0/0` | TCP | `443` | HTTPS (Nginx Proxy Manager) |


#### 4.2 Subir o Nginx Proxy Manager via Portainer

No Portainer, crie uma **nova stack** chamada `nginx-proxy-manager`:

1. Vá em **Stacks** → **Add stack**.
2. Nome: `nginx-proxy-manager`.
3. Cole o seguinte compose:

```yaml
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - npm_data:/data
      - npm_letsencrypt:/etc/letsencrypt
    restart: unless-stopped

volumes:
  npm_data:
  npm_letsencrypt:
```

| Porta | Significado |
| :--- | :--- |
| `80` | HTTP — recebe requisições e redireciona para HTTPS |
| `443` | HTTPS — serve o conteúdo criptografado |
| `81` | Painel de administração do Nginx Proxy Manager |

> ⚠️ A porta 81 é o painel admin do NPM. **Não libere a porta 81 na Security List para `0.0.0.0/0`** — isso exporia o painel de administração para a Internet inteira. Acesse o painel de duas formas seguras:
> - Via **SSH tunnel**: `ssh -L 8181:localhost:81 ubuntu@<IP_VM>` e acesse `http://localhost:8181` no navegador local.
> - Ou, temporariamente, libere a porta 81 na Security List **apenas para o seu IP** (descubra-o em [ifconfig.me](https://ifconfig.me)), configure o NPM, e depois **remova a regra**.

4. Clique em **Deploy the stack**.

#### 4.3 Liberar a porta 81 temporariamente e fazer login

**Opção A — SSH Tunnel (recomendada):**

```bash
# No seu terminal local (não na VM):
ssh -i ~/.ssh/id_ed25519 -L 8181:localhost:81 ubuntu@<IP_PUBLICO_DA_VM>
```

Acesse `http://localhost:8181` no navegador.

**Opção B — Liberar porta 81 na Security List (temporariamente):**

Adicione na Security List: Source `<SEU_IP>/32`, Protocol TCP, Port `81`, Description `NPM Admin (temporário)`.

Acesse `http://<IP_PUBLICO_DA_VM>:81` no navegador.

**Credenciais padrão do NPM (primeira vez):**

| Campo | Valor |
| :--- | :--- |
| Email | `admin@example.com` |
| Password | `changeme` |

Após o login, o NPM pedirá para alterar o email e a senha — **faça isso imediatamente**.

#### 4.4 Configurar o Proxy Host para a aplicação

1. No painel do NPM, vá em **Hosts** → **Proxy Hosts** → **Add Proxy Host**.
2. Na aba **Details**, preencha:

| Campo | Valor |
| :--- | :--- |
| Domain Names | `seudominio.me` (adicione também `www.seudominio.me` se configurou o A Record) |
| Scheme | `http` |
| Forward Hostname / IP | `<IP_INTERNO_DA_VM>` ou `host.docker.internal` ou o IP do container da app |
| Forward Port | `8082` |
| Block Common Exploits | ✅ |
| Websockets Support | ✅ (se a aplicação usar websockets) |

> 💡 **Qual IP usar no "Forward Hostname"?** Como o NPM roda em um container Docker e precisa se comunicar com o container da aplicação (que está em outra stack), o mais simples é usar o **IP da interface `docker0` do host**:
> ```bash
> # Na VM, descubra o IP do gateway Docker:
> ip addr show docker0 | grep "inet " | awk '{print $2}' | cut -d/ -f1
> # Resultado típico: 172.17.0.1
> ```
> Use esse IP como Forward Hostname. Isso funciona porque os containers podem alcançar o host via essa interface, e a porta `8082` está mapeada no host (`-p 8082:8080`).
>
> **Alternativa mais elegante:** coloque o NPM e a stack da aplicação na **mesma rede Docker**. Crie uma rede externa chamada `web`:
> ```bash
> docker network create web
> ```
> E adicione `networks: - web` nos dois compose files, usando `app` como Forward Hostname (o nome do serviço) e `8080` como Forward Port (a porta interna, não a do host).

3. Na aba **SSL**, preencha:

| Campo | Valor |
| :--- | :--- |
| SSL Certificate | Request a new SSL Certificate |
| Force SSL | ✅ |
| HTTP/2 Support | ✅ |
| Email Address for Let's Encrypt | seu email real (para notificações de expiração) |
| I Agree to the Let's Encrypt ToS | ✅ |

4. Clique em **Save**.

> ⏱️ O Let's Encrypt leva alguns segundos para validar o domínio e emitir o certificado. Se falhar com erro de validação, verifique:
> - O A Record está apontando para o IP correto da VM?
> - As portas 80 e 443 estão liberadas na Security List e no iptables?
> - O Nginx Proxy Manager está realmente escutando nas portas 80 e 443?
>   ```bash
>   ss -tlnp | grep -E ':80|:443'
>   ```

#### 4.5 (Opcional) Remover a porta 8082 e 8081 da Security List

Agora que o tráfego chega pela porta 443 (HTTPS) via Nginx Proxy Manager e é repassado internamente para a porta 8080 do container, **não é mais necessário** expor a porta 8082 e 8081 diretamente para a Internet.

1. Na Security List da OCI, **remova** a regra de Ingress da porta 8082 e 8081.


> 🔒 Essa é uma boa prática de segurança: **exponha apenas o mínimo necessário**. O tráfego agora flui exclusivamente por HTTPS na porta 443, passa pelo reverse proxy e chega ao container internamente. A porta 8080 continua acessível dentro da VM (para comunicação container-a-container), mas não está mais acessível pela Internet.

### Como observar/diagnosticar

1. **No navegador:** acesse `https://seudominio.me` — a aplicação deve carregar com o cadeado verde 🔒.

2. **Verifique o certificado:**
   - Clique no cadeado no navegador → "Certificate" → confirme que foi emitido por **Let's Encrypt** e é válido.
   - Via terminal:
     ```bash
     echo | openssl s_client -connect seudominio.me:443 -servername seudominio.me 2>/dev/null | openssl x509 -noout -subject -issuer -dates
     ```

3. **Verifique o redirect HTTP → HTTPS:**
   ```bash
   curl -I http://seudominio.me
   # Esperado: HTTP/1.1 301 Moved Permanently
   # Location: https://seudominio.me/
   ```

4. **No painel do NPM:** vá em **Proxy Hosts** — o host deve aparecer com status **Online** e o ícone de certificado verde.

### Como validar

- [ ] `https://seudominio.me` carrega a aplicação com cadeado verde 🔒.
- [ ] O certificado foi emitido pelo Let's Encrypt e é válido.
- [ ] `http://seudominio.me` redireciona automaticamente para `https://seudominio.me`.
- [ ] A porta 8080 **não** é mais acessível diretamente pela Internet (apenas via reverse proxy).
- [ ] A porta 81 (admin do NPM) **não** está acessível pela Internet.

### Como usar a LLM aqui

> "Ao tentar obter o certificado SSL no Nginx Proxy Manager, recebo o erro: `Error: Command failed: certbot certonly ... :: The server could not connect to the client to verify the domain`. As portas 80 e 443 estão liberadas na Security List da OCI. (a) Qual a diferença entre a validação HTTP-01 e DNS-01 do Let's Encrypt, e por que o HTTP-01 precisa que a porta 80 esteja realmente acessível de fora, e (b) como eu posso testar, de fora da VM, se a porta 80 está de fato respondendo?"

---

# BÔNUS & DESAFIOS AVANÇADOS

## Cenário 5 — Database as a Service (DBaaS): PostgreSQL Gerenciado na OCI

### Causa raiz / Fundamento teórico

Até agora, o PostgreSQL roda como um **container** na mesma VM que a aplicação. Isso funciona, mas em produção real traz riscos:

| Aspecto | Container Local | DBaaS (Banco Gerenciado) |
| :--- | :--- | :--- |
| **Backups** | Manual (você cria scripts de `pg_dump`) | Automáticos pelo provedor |
| **Alta disponibilidade** | Se a VM cair, o banco cai junto | Réplicas automáticas em outro hardware |
| **Patches de segurança** | Você atualiza manualmente a imagem | O provedor aplica patches automaticamente |
| **Escala** | Limitado aos recursos da VM | Escala vertical/horizontal pelo provedor |
| **Custo** | "Grátis" (usa recursos da VM) | Serviço pago (**sem** free tier disponível na OCI) |
| **Controle** | Total (você configura tudo) | Parcial (algumas configs são gerenciadas) |

O serviço **OCI Database with PostgreSQL** oferece PostgreSQL totalmente gerenciado, compatível com o protocolo padrão PostgreSQL (diferente do Autonomous Database, que usa o motor Oracle). Isso significa que sua aplicação pode trocar o `DATABASE_URL` do container local para o banco gerenciado **sem alterar uma linha de código**.

> ⚠️ **Nota sobre custos:** o serviço OCI Database with PostgreSQL **não faz parte do Always Free Tier**. Ele consome os créditos de trial (US$300 por 30 dias) ou é cobrado em contas Pay-As-You-Go. Para fins didáticos, crie a menor instância possível, use-a apenas durante o laboratório e **destrua o recurso ao terminar**. Este cenário é classificado como **bônus** exatamente por esse motivo.

### Como configurar

#### 5.1 Provisionar o PostgreSQL Gerenciado na OCI

1. No Console da OCI, navegue até: **Databases** → **PostgreSQL** → **Create DB System**.
2. Configure:

| Campo | Valor recomendado |
| :--- | :--- |
| DB system name | `tododb-managed` |
| Compartment | `disciplina-infra-ti` |
| PostgreSQL version | 17 (ou a mais recente disponível) |
| Shape | A menor disponível (ex: `PostgreSQL.VM.Standard.E4.Flex.2.32GB`) |
| Node count | 1 (para minimizar custos) |
| Storage | Mínimo disponível (ex: 50GB) |
| Admin username | `todouser` |
| Admin password | Escolha uma senha forte |
| Database name | `tododb` |
| VCN | A mesma VCN da sua VM |
| Subnet | **Subnet privada** (o banco não deve ficar exposto na Internet) |

> 🔒 O banco de dados deve estar na **subnet privada** — ele só precisa ser acessível pela VM (que está na subnet pública da mesma VCN). Nunca coloque um banco de dados em uma subnet pública com IP público.

3. Clique em **Create** e aguarde o provisionamento (~10-20 minutos).

4. Após o provisionamento, anote o **endpoint privado** (algo como `10.0.1.xxx:5432`) — esse é o IP interno do banco gerenciado dentro da VCN.

#### 5.2 Configurar a Security List da subnet privada

Para que a VM (na subnet pública) consiga se comunicar com o banco (na subnet privada), a Security List da subnet privada precisa permitir tráfego na porta 5432 vindo da subnet pública:

Na Security List da **subnet privada**, adicione uma regra de Ingress:

| Source CIDR | Protocol | Port Range | Description |
| :--- | :--- | :--- | :--- |
| `10.0.0.0/24` (CIDR da subnet pública) | TCP | `5432` | PostgreSQL da VM |

#### 5.3 Testar a conectividade a partir da VM

```bash
# Na VM, teste a conexão com o banco gerenciado
sudo apt install -y postgresql-client  # se ainda não tiver

psql -h <IP_PRIVADO_DO_DB> -U todouser -d tododb -c "SELECT version();"
```

Se a conexão funcionar, você verá a versão do PostgreSQL.

#### 5.4 Atualizar a stack no Portainer para usar o banco gerenciado

No Portainer, edite a stack `gotodolist` e altere para:

```yaml
api:
    image: ghcr.io/${GHCR_OWNER:-elton-bt}/gotodolist-api:${IMAGE_TAG:-latest}
    restart: unless-stopped
    mem_limit: 256M
    cpu_shares: 64
    environment:
      DB_HOST: ${DB_HOST:-db}
      DB_PORT: ${DB_PORT:-5432}
      DB_NAME: ${DB_NAME:-gotodolist}
      DB_USER: ${DB_USER:-gotodolist}
      DB_PASSWORD: ${DB_PASSWORD:-12345}
      DB_SSLMODE: ${DB_SSLMODE:-require}
      CORS_ALLOW_ORIGIN: ${CORS_ALLOW_ORIGIN:-*}
    ports:
      - "${API_HOST_PORT:-8081}:8081"
    networks:
      - frontend_api
      - api_db
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.0:8081/health"]
      interval: 20s
      timeout: 5s
      retries: 5
      start_period: 15s

# Note: o serviço 'postgres' e o volume 'pgdata' foram REMOVIDOS
# O banco agora é gerenciado pela OCI
```

Diferenças em relação à versão anterior. Modifique as variáveis de ambiente para apontar para o banco gerenciado:

| Antes (container) | Depois (DBaaS) |
| :--- | :--- |
| Host: `postgres` (nome do serviço) | Host: `<IP_PRIVADO_DO_DB>` (endpoint OCI) |
| `sslmode=disable` | `sslmode=require` (conexão criptografada obrigatória) |
| Serviço `postgres` no compose | Removido (banco é externo) |
| Volume `pgdata` | Removido (OCI gerencia o armazenamento) |
| `depends_on` | Removido (sem dependência local) |

> 💡 **`sslmode=require`** garante que a comunicação entre a aplicação e o banco gerenciado seja criptografada, mesmo dentro da VCN. Isso é uma boa prática de segurança — o tráfego de rede dentro de uma VCN, apesar de isolado logicamente, pode ser interceptado em cenários de comprometimento de outra VM na mesma rede.

Clique em **Update the stack** no Portainer.

### Como observar/diagnosticar

1. **No Portainer:** confirme que o serviço `app` está **running** e não há mais o serviço `postgres`.

2. **Na aplicação:** acesse `https://seudominio.me` — crie uma nova tarefa e confirme que ela persiste.

3. **No Console da OCI:** acesse **Databases** → **PostgreSQL** → `tododb-managed` → **Metrics** — observe as métricas de conexões ativas, queries e uso de CPU/memória do banco.

4. **Via terminal na VM:**
   ```bash
   # Verificar que não há container de postgres rodando localmente
   docker ps | grep postgres
   # Deve retornar vazio

   # Verificar que a app está conectada ao banco remoto
   docker logs gotodolist-app-1 2>&1 | tail -5
   ```

### Como validar

- [ ] PostgreSQL gerenciado provisionado no Console da OCI.
- [ ] Conectou ao banco gerenciado via `psql` a partir da VM.
- [ ] Stack atualizada no Portainer sem o serviço `postgres` local.
- [ ] Aplicação funcionando com dados persistindo no banco gerenciado.
- [ ] Métricas do banco visíveis no Console da OCI.

### Como usar a LLM aqui

> "Minha aplicação Go retorna o erro `pq: SSL is not enabled on the server` ao tentar conectar com `sslmode=require` no banco gerenciado da OCI. Mas quando uso `psql` com a mesma connection string, funciona. (a) Explique as diferentes opções de `sslmode` do PostgreSQL (disable, require, verify-ca, verify-full), em que camada cada uma atua e qual é a recomendada para conexões dentro de uma VCN, e (b) como posso verificar se o driver Go que minha aplicação usa realmente suporta `sslmode=require`."

---

## Desafio Avançado (opcional) — Uptime Kuma: Monitoramento de Disponibilidade

Suba o [Uptime Kuma](https://github.com/louislam/uptime-kuma) como uma nova stack no Portainer e configure-o para monitorar:

1. A URL `https://seudominio.me` (verificação HTTP a cada 60 segundos).
2. O endpoint do Portainer (`https://localhost:9443`, verificação interna).
3. A porta do PostgreSQL gerenciado (verificação TCP na porta 5432 do IP privado).

Configure uma notificação (por email, Telegram ou Discord) para ser alertado quando qualquer serviço ficar indisponível.

**Stack do Uptime Kuma para o Portainer:**

```yaml
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    ports:
      - "3001:3001"
    volumes:
      - uptime_data:/app/data
    restart: unless-stopped

volumes:
  uptime_data:
```

> 💡 O Uptime Kuma é o equivalente open-source e self-hosted do UptimeRobot. Ele roda na própria VM e monitora seus serviços de dentro — ideal para detectar problemas antes dos seus usuários. Você também pode expô-lo via Nginx Proxy Manager em um subdomínio como `status.seudominio.me`.

---

## Tabela-Resumo (Cheat Sheet)

| Sintoma observado | Causa provável | Primeiro comando de diagnóstico | Como corrigir |
| :--- | :--- | :--- | :--- |
| Timeout ao acessar `https://<IP>:9443` | Porta 9443 bloqueada na Security List ou no iptables do Ubuntu | `sudo iptables -L -n \| grep 9443` e conferir Security List no Console OCI | Adicionar regra de Ingress na Security List e `iptables -I INPUT` |
| Portainer mostra stack com erro `image not found` | Imagem no GHCR é privada e o registry não foi configurado no Portainer | Testar `docker pull ghcr.io/<user>/<app>:latest` na VM | Configurar o GHCR como Custom Registry no Portainer com PAT |
| Webhook retorna 403 | URL do webhook incorreta ou stack foi recriada (novo token) | Conferir a URL no Portainer → Stack → Stack webhook | Copiar a nova URL e atualizar o GitHub Secret |
| `cd.yml` rodou mas a versão não atualizou | Imagem antiga em cache; Portainer fez pull antes da nova imagem estar no GHCR | `docker inspect <container> --format '{{.Config.Image}}'` | Aumentar o `sleep` no `cd.yml` ou adicionar verificação de manifest |
| `nslookup` retorna IP correto mas HTTPS falha | Certificado ainda não emitido ou portas 80/443 bloqueadas | `curl -I http://seudominio.me` e verificar `ss -tlnp \| grep :80` | Liberar portas 80/443 na Security List e iptables; reemitir o certificado no NPM |
| Let's Encrypt falha com "could not connect" | Porta 80 bloqueada — validação HTTP-01 precisa que o Let's Encrypt acesse a porta 80 da VM | `curl http://<IP>:80` de fora da VM | Liberar porta 80 na Security List e no iptables |
| Aplicação com erro de conexão ao banco gerenciado | Security List da subnet privada bloqueando porta 5432, ou IP errado | `psql -h <IP_DB> -U todouser -d tododb` direto na VM | Adicionar regra de Ingress na Security List da subnet privada |
| NPM proxy host mostra "502 Bad Gateway" | Forward Hostname/Port incorretos no NPM, ou a app não está rodando | `curl http://<forward_host>:<forward_port>` de dentro do container NPM | Verificar o IP/porta corretos e usar a rede Docker adequada |

---

## Entregável

Preencham a tabela abaixo para **todos os cenários do núcleo (1 a 4)**. Cenários bônus contam como pontos extras se preenchidos também.

| Cenário | O que foi configurado/observado | Causa raiz ou motivação técnica | Comando de verificação utilizado | Resultado ou correção aplicada |
| :--- | :--- | :--- | :--- | :--- |
| 1 — Portainer + Stack na OCI | | | | |
| 2 — CD Automatizado com Webhook | | | | |
| 3 — Domínio com Namecheap | | | | |
| 4 — Reverse Proxy + HTTPS (NPM) | | | | |
| 5 — DBaaS PostgreSQL (bônus) | | | | |
| Desafio — Uptime Kuma (bônus) | | | | |

Além da tabela, **demonstre ao professor:**
1. A aplicação acessível via `https://seudominio.me` com cadeado verde.
2. O fluxo completo de CD: altere o código → push → CI → tag → Release → CD → nova versão em produção (automaticamente).
3. O painel do Portainer com as stacks rodando.

---

### Armadilhas conhecidas

- **iptables do Ubuntu na OCI:** este é o problema número 1 que os alunos enfrentam. A Security List da OCI é o firewall de **rede virtual**, mas o Ubuntu na OCI vem com regras iptables restritivas por padrão. Se uma porta está liberada na Security List mas não no iptables, o tráfego chega até a VM mas é descartado pelo SO. **Limpe as regras do iptables e desabilite o firewall.**
- **Portainer EE vs CE:** se subir o `portainer-ce` (Community) por engano, o webhook de stack **não está disponível** na versão CE. Certifique-se de usar `portainer-ee:lts`.
- **Imagens ARM vs AMD:** se a VM é `A1.Flex` (ARM), imagens construídas apenas para `amd64` **não rodam**. Você verá erro `exec format error`. A solução é voltar ao `release.yml` e adicionar multi-arch build (`linux/amd64,linux/arm64`).
- **Propagação DNS lenta na rede do campus:** resolvers DNS de redes corporativas/acadêmicas costumam ter caches agressivos. Testem com `nslookup dominio 8.8.8.8` (DNS público do Google) para confirmar que o registro existe, mesmo que o resolver local ainda não tenha atualizado.
- **Let's Encrypt rate limits:** em ambiente de teste, se o mesmo domínio solicitar mais de 5 certificados em uma semana, o Let's Encrypt pode recusar novas solicitações. Não ficarem recriando o proxy host repetidamente.
- **Porta 81 do NPM exposta:** Vocês tendem a liberar a porta 81 para `0.0.0.0/0` "para facilitar" e esquecem de remover a regra depois. O painel admin deve ser acessado via SSH tunnel ou IP restrito.
- **`workflow_run` não dispara:** o trigger `workflow_run` só funciona se o workflow `cd.yml` estiver na branch **padrão** do repositório (geralmente `main`). Se você criou o arquivo em outra branch, o CD não será disparado.
- **Credenciais do banco gerenciado (Cenário 5):** a senha do admin do PostgreSQL gerenciado é definida na criação e **não pode ser recuperada** depois. Se você esquecer, precisará destruir e recriar o recurso.
- **Custos do Cenário 5:** o PostgreSQL gerenciado da OCI consome créditos de trial. Se você tiver conta Always Free sem créditos, não conseguirá criar o recurso.
