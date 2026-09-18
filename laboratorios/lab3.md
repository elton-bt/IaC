# Laboratório 3 — Dominando Volumes Persistentes e Redes Customizadas no Docker

**Disciplina:** Infraestrutura de TI para Sistemas na Internet  
**Aula de referência:** Aula 07 (Persistência de Dados (Volumes) e Redes Customizadas no Docker)  
**Projeto usado como cobaia:** [`gotodolist`](https://github.com/elton-bt/gotodolist) (Go + PostgreSQL), imagem utilitária [`alpine`](https://hub.docker.com/_/alpine) e PostgreSQL 17.  
**Objetivo:** sair da teoria ("o que é um volume", "o que é uma bridge network") para a prática de **arquitetar persistência resiliente, isolar redes em camadas de segurança (DMZ vs Backend vs Banco), diagnosticar falhas de resolução de DNS interno e realizar backup e restauração de volumes sem derrubar o daemon do Docker** — exatamente como exigido em ambientes de produção.

---

## Como este laboratório está organizado

| Bloco | Cenários | Quando fazer |
| :--- | :--- | :--- |
| **Preparação** | Limpeza e verificação de imagens base | Sempre, primeiro (~15 min) |
| **Parte 1** | 1) O Teste da Efemeridade: Camada Gravável vs Named Volume<br>2) Default Bridge vs User-Defined Bridge (O Mistério do DNS Embutido)<br>3) Bind Mounts na Prática: Injeção de Scripts de Inicialização e Hot-Config<br>4) Isolamento Multi-Camadas (Segurança: DMZ vs Rede Interna do Banco)<br>5) O Antipadrão da Porta Exposta no Host vs Comunicação Segura Inter-Container | Em sala, tempo estimado ~100-110 min (cabe no bloco de "Laboratório Prático Guiado" da metodologia da disciplina) |
| **Parte 2** | 6) Backup e Restore de Volumes (O Padrão de Container Efêmero com `tar`)<br>7) Aliases de Rede e Resolução Round-Robin no DNS do Docker<br>8) Isolamento Absoluto com Rede `--internal` (Prevenção de Exfiltração de Dados)<br>Desafio Avançado: Snapshot Automatizado e Recuperação em Novo Volume | Para quem terminar rápido, ou como tarefa complementar/take-home |

Cada cenário segue sempre a mesma estrutura: **Causa raiz / Fundamento** → **Como provocar / Como configurar** → **Como observar/diagnosticar** → **Como corrigir / validar** → **Como usar a LLM aqui**.

---

## Como usar a LLM neste laboratório (leia isso primeiro)

Não use a LLM apenas para gerar comandos mágicos que você cola cegamente no terminal. Use este protocolo profissional de 4 passos:

1. **Cole a saída EXATA do comando de diagnóstico** (`docker inspect`, `docker logs`, `docker exec`, etc.) junto com a sua intenção: *"Tentei comunicar o container A com o container B usando o hostname X e obtive o erro Y"*.
2. **Peça à LLM duas coisas específicas:**
   - (a) Qual é a causa raiz no nível do subsistema do Docker (camada UnionFS/overlay2, namespaces de rede, firewall/iptables ou daemon de DNS `127.0.0.11`).
   - (b) **Um comando de inspeção que comprove a hipótese** antes de qualquer intervenção (por exemplo, inspecionar a seção `NetworkSettings` ou ler `/etc/resolv.conf` do container).
3. **Execute o comando de confirmação você mesmo** e analise a saída.
4. **Aplique a arquitetura correta** e valide com comandos determinísticos (não apenas "parece que funcionou").

---

## Preparação do Ambiente (compartilhada — fazer uma vez, ~15 min)

Antes de iniciar os testes, garantiremos que não há resquícios de laboratórios anteriores colidindo nomes de containers, portas ou volumes.

### 1. Clonar o repositório da disciplina (se ainda não tiver clonado)

```bash
git clone https://github.com/elton-bt/gotodolist.git
cd gotodolist
```

### 2. Limpar containers e redes antigas que possam colidir

```bash
# Para e remove containers que usaremos ao longo do laboratório
docker rm -f gotodolist-db db-padrao app-padrao db-isolado backend-api proxy-web 2>/dev/null || true

# Remove redes de teste se já existirem
docker network rm rede-publica rede-interna rede-minha-app 2>/dev/null || true
```

### 3. Pré-carregar imagens leves que usaremos

Para evitar esperas durante os exercícios, baixe as imagens oficiais necessárias:

```bash
docker pull postgres:17-alpine
docker pull alpine:latest
```

### 4. Checklist de baseline

- [ ] `docker info` executa sem erros de permissão (seu usuário pertence ao grupo `docker` ou você tem privilégios `sudo`).
- [ ] `docker images` lista `postgres:17-alpine` e `alpine:latest`.
- [ ] O diretório do projeto `gotodolist` está acessível.

---

# PARTE 1 — Persistência de Dados e Redes Customizadas

## Cenário 1 — O Teste da Efemeridade: Camada Gravável (*Writable Layer*) vs Named Volume

### Causa raiz / Fundamento teórico
Containers são concebidos pela computação em nuvem para serem **descartáveis** (*stateless* por padrão). Quando um container é instanciado a partir de uma imagem, o Docker cria uma fina camada gravável (*writable container layer*) no topo das camadas imutáveis da imagem usando um sistema de arquivos em camadas (como o **overlay2**). 

Se você executar um banco de dados dentro dessa camada padrão e o container for removido (`docker rm`), **todos os blocos de dados criados após o boot desaparecem permanentemente**. Para persistir dados além do ciclo de vida do container, o Docker fornece **Named Volumes**, que contornam o subsistema de união de arquivos (UnionFS) e gravam diretamente no sistema de arquivos do host em `/var/lib/docker/volumes/`.

---

### Parte A — Provocando a Catástrofe: O Container sem Volume

1. Suba um banco PostgreSQL **sem especificar volume nenhum** (apenas com as variáveis de ambiente obrigatórias):
   ```bash
   docker run -d \
     --name db-efemero \
     -e POSTGRES_USER=aluno \
     -e POSTGRES_PASSWORD=segredo \
     -e POSTGRES_DB=escola \
     postgres:17-alpine
   ```

2. Aguarde 3 segundos para o PostgreSQL iniciar e crie uma tabela com registros importantes via linha de comando:
   ```bash
   docker exec -it db-efemero psql -U aluno -d escola -c "
   CREATE TABLE alunos (id SERIAL PRIMARY KEY, nome VARCHAR(100), matricula INT);
   INSERT INTO alunos (nome, matricula) VALUES ('Carlos Drummond', 1001), ('Clarice Lispector', 1002);
   "
   ```

3. Confirme que os dados existem no container:
   ```bash
   docker exec -it db-efemero psql -U aluno -d escola -c "SELECT * FROM alunos;"
   ```
   *Saída esperada:* A tabela exibe os 2 alunos cadastrados.

4. **O Desastre:** Simule uma falha grave em produção — o container travou, foi deletado acidentalmente ou sofreu um deploy que recriou a instância:
   ```bash
   docker rm -f db-efemero
   ```

5. Recrie o container com o mesmo nome, mesma imagem e mesmas variáveis de ambiente:
   ```bash
   docker run -d \
     --name db-efemero \
     -e POSTGRES_USER=aluno \
     -e POSTGRES_PASSWORD=segredo \
     -e POSTGRES_DB=escola \
     postgres:17-alpine
   ```

6. Tente consultar os alunos novamente:
   ```bash
   docker exec -it db-efemero psql -U aluno -d escola -c "SELECT * FROM alunos;"
   ```
   *Resultado observado:*
   ```text
   ERROR:  relation "alunos" does not exist
   LINE 1: SELECT * FROM alunos;
   ```
   **Os dados foram irremediavelmente perdidos.** O novo container iniciou com uma camada de escrita zerada.

7. Remova o container efêmero de teste:
   ```bash
   docker rm -f db-efemero
   ```

---

### Parte B — A Solução Profissional: Persistência com Named Volume

Agora implementaremos a persistência gerenciada pelo Docker com um *Named Volume*.

1. Crie explicitamente um volume dedicado para os dados do PostgreSQL:
   ```bash
   docker volume create dados-postgres-escola
   ```

2. Inspecione os metadados do volume criado:
   ```bash
   docker volume inspect dados-postgres-escola
   ```
   Repare no campo `"Mountpoint"` (ex.: `/var/lib/docker/volumes/dados-postgres-escola/_data`). Esse é o caminho real no disco do host Linux onde os arquivos do PostgreSQL serão gravados diretamente, com I/O nativo e fora do overhead do overlay2!

3. Suba o container apontando o volume para o diretório padrão de dados do PostgreSQL (`/var/lib/postgresql/data`):
   ```bash
   docker run -d \
     --name db-persistente \
     -v dados-postgres-escola:/var/lib/postgresql/data \
     -e POSTGRES_USER=aluno \
     -e POSTGRES_PASSWORD=segredo \
     -e POSTGRES_DB=escola \
     postgres:17-alpine
   ```

4. Aguarde o banco inicializar e crie os registros novamente:
   ```bash
   docker exec -it db-persistente psql -U aluno -d escola -c "
   CREATE TABLE alunos (id SERIAL PRIMARY KEY, nome VARCHAR(100), matricula INT);
   INSERT INTO alunos (nome, matricula) VALUES ('Machado de Assis', 2001), ('Cecília Meireles', 2002);
   "
   ```

5. Valide que os registros estão presentes:
   ```bash
   docker exec -it db-persistente psql -U aluno -d escola -c "SELECT * FROM alunos;"
   ```

6. **O Teste da Destruição:** Exclua o container sem piedade com a flag `-f` (force):
   ```bash
   docker rm -f db-persistente
   ```

7. Recrie o container exatamente igual, montando o mesmo volume `dados-postgres-escola`:
   ```bash
   docker run -d \
     --name db-persistente \
     -v dados-postgres-escola:/var/lib/postgresql/data \
     -e POSTGRES_USER=aluno \
     -e POSTGRES_PASSWORD=segredo \
     -e POSTGRES_DB=escola \
     postgres:17-alpine
   ```

8. Execute a consulta de validação:
   ```bash
   docker exec -it db-persistente psql -U aluno -d escola -c "SELECT * FROM alunos;"
   ```
   *Resultado:* **Todos os dados continuam lá!** O container foi destruído e recriado, mas os dados persistiram no volume nomeado.

---

### Tabela Comparativa — Camada Gravável vs Named Volume

| Característica | Writable Layer (Padrão) | Named Volume (`docker volume`) |
| :--- | :--- | :--- |
| **Persistência ao remover container (`docker rm`)** | ❌ Perdida para sempre | ✅ Intacta no host |
| **Performance de Disco (I/O)** | Lenta (overhead do driver UnionFS/overlay2) | Nativa do sistema de arquivos Linux |
| **Localização no Host** | Fragmentada dentro do grafo do overlay2 | Diretório fixo gerenciado (`/var/lib/docker/volumes/`) |
| **Compartilhamento entre containers** | Impossível | Possível (múltiplos containers podem ler o volume) |
| **Uso recomendado** | Arquivos temporários de processo | Bancos de Dados (PostgreSQL, MySQL, MongoDB, Redis) |


---

## Cenário 2 — Default Bridge vs User-Defined Bridge: O Mistério do DNS Embutido

### Causa raiz / Fundamento teórico
Muitos desenvolvedores que começam no Docker aprendem a rodar containers soltos com `docker run` e assumem que eles conseguirão se comunicar chamando o nome um do outro (como `ping meu-backend` ou conectando na string `postgres://usuario:senha@db-postgres:5432`).

Porém, quando você não especifica a flag `--network`, o Docker anexa o container à rede padrão chamada **`bridge`** (gerenciada pela interface virtual de rede `docker0` no host). **Por decisão de projeto e razões históricas de compatibilidade, a rede bridge padrão NÃO POSSUI resolução automática de nomes por DNS.** 

Para ter resolução de nomes automática sem recorrer a IPs voláteis ou flags obsoletas como `--link`, é obrigatório criar uma **User-Defined Bridge Network** (`docker network create`). Nessas redes criadas pelo usuário, o Docker ativa um servidor DNS embutido no endereço especial `127.0.0.11`.

---

### Como provocar: Falha de Resolução na Rede Padrão

1. Suba dois containers na rede padrão do Docker (sem passar `--network`):
   ```bash
   # Container 1: Nosso banco na rede default
   docker run -d --name db-padrao \
     -e POSTGRES_PASSWORD=segredo \
     postgres:17-alpine

   # Container 2: Um container utilitário Alpine para testes
   docker run -d --name app-padrao \
     alpine:latest sleep 3600
   ```

2. Tente fazer o `app-padrao` resolver o nome e pingar o container `db-padrao`:
   ```bash
   docker exec -it app-padrao ping -c 2 db-padrao
   ```
   *Resultado observado:*
   ```text
   ping: bad address 'db-padrao'
   ```
   Ou no caso de utilitários como `getent` ou `curl`:
   ```text
   Name or service not known
   ```

3. Inspecione o `/etc/resolv.conf` do container na rede padrão:
   ```bash
   docker exec -it app-padrao cat /etc/resolv.conf
   ```
   Repare que ele herdou diretamente os servidores DNS da sua máquina host ou do roteador (ex: `nameserver 192.168.1.1` ou `nameserver 8.8.8.8`). O DNS do seu roteador obviamente não faz a menor ideia de quem é `db-padrao`!

---

### Como corrigir: Criando uma User-Defined Bridge

1. Crie uma rede própria gerenciada pelo usuário:
   ```bash
   docker network create rede-app-integrada
   ```

2. Inspecione a rede recém-criada:
   ```bash
   docker network inspect rede-app-integrada
   ```
   Observe a sub-rede criada (ex.: `172.18.0.0/16` ou `172.19.0.0/16`). O Docker gerencia a tabela de roteamento e o DNS interno dessa sub-rede isolada.

3. Conecte os dois containers existentes à nova rede:
   ```bash
   docker network connect rede-app-integrada db-padrao
   docker network connect rede-app-integrada app-padrao
   ```

4. Agora repita o teste de conectividade e resolução de nomes:
   ```bash
   docker exec -it app-padrao ping -c 2 db-padrao
   ```
   *Resultado:* **Sucesso instantâneo!**
   ```text
   64 bytes from 172.18.0.2: seq=0 ttl=64 time=0.082 ms
   64 bytes from 172.18.0.2: seq=1 ttl=64 time=0.076 ms
   ```

5. Investigue a prova real de como o Docker resolve isso — leia o `/etc/resolv.conf` do `app-padrao` novamente:
   ```bash
   docker exec -it app-padrao cat /etc/resolv.conf
   ```
   *Saída observada:*
   ```text
   nameserver 127.0.0.11
   options ndots:0
   ```
   O IP `127.0.0.11` é o **Docker Embedded DNS Server**. Toda requisição de nome passa primeiro por ele. Se a requisição for pelo nome de um container na mesma rede, o Docker responde com o IP interno correspondente. Se for um endereço externo (como `google.com`), ele repassa para o DNS do host.

6. Limpeza dos containers deste cenário:
   ```bash
   docker rm -f db-padrao app-padrao
   docker network rm rede-app-integrada
   ```

---

### Tabela de Comparação — Redes no Docker

| Característica | Default Bridge (`bridge`) | User-Defined Bridge (`docker network create`) |
| :--- | :--- | :--- |
| **Resolução DNS automática por nome** | ❌ Não (`ping container` falha com `bad address`) | ✅ Sim (resolvido por `127.0.0.11`) |
| **Isolamento de tráfego** | Baixo (todos os containers sem `--network` caem aqui) | Alto (somente containers explicitamente conectados conversam) |
| **Conexão/Desconexão dinâmica em runtime** | ❌ Não (exige recriar container) | ✅ Sim (`docker network connect/disconnect`) |
| **Segurança em ambientes de produção** | ⚠️ Desaconselhada para stacks multi-serviço | ✅ Padrão recomendado pela documentação do Docker |

### Como usar a LLM aqui
Pergunte à LLM: *"Por que o Docker optou historicamente por desativar o DNS embutido na rede bridge padrão e como a flag legada `--link` funcionava alterando o arquivo `/etc/hosts`?"*. Peça para ela destacar as limitações de concorrência e IPs fixos que tornaram o `--link` obsoleto.

---

## Cenário 3 — Bind Mounts na Prática: Injeção de Scripts de Inicialização e Hot-Config

### Causa raiz / Fundamento teórico
Enquanto **Named Volumes** são ideais para persistência opaca de dados gerados por bancos (onde você raramente precisa editar arquivos pelo host diretamente), os **Bind Mounts** (`-v /caminho/no/host:/caminho/no/container`) mapeiam exatamente uma pasta ou arquivo do host para dentro do container.

Em infraestrutura, o principal caso de uso para Bind Mounts em bancos de dados é o **provisionamento automático**: as imagens oficiais do PostgreSQL contêm um recurso nativo em que qualquer script `.sql` ou `.sh` depositado no diretório `/docker-entrypoint-initdb.d/` é executado **automaticamente na primeira inicialização do banco** (quando o diretório de dados está vazio).

---

### Como configurar e executar

1. Crie uma pasta de trabalho local no seu host para guardar as configurações:
   ```bash
   mkdir -p infra-scripts
   ```

2. Crie um script SQL de inicialização em `infra-scripts/01-init.sql`:
   ```bash
   cat << 'EOF' > infra-scripts/01-init.sql
   -- Script executado automaticamente no primeiro boot do Postgres
   CREATE TABLE tarefas_padrao (
       id SERIAL PRIMARY KEY,
       descricao VARCHAR(255) NOT NULL,
       concluida BOOLEAN DEFAULT FALSE,
       criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
   );

   INSERT INTO tarefas_padrao (descricao, concluida) VALUES
   ('Revisar slides da Aula 07 sobre redes e volumes', true),
   ('Comprovar que bind mount injetou este registro', false),
   ('Praticar destruição e restauração de containers', false);
   EOF
   ```

3. Crie também um arquivo de teste de configuração customizada do PostgreSQL em `infra-scripts/custom.conf` (ajustando o fuso horário ou nível de log):
   ```bash
   cat << 'EOF' > infra-scripts/custom.conf
   timezone = 'America/Recife'
   log_min_duration_statement = 0
   EOF
   ```

4. Suba o container combinando:
   - Um **Named Volume** para persistir os dados brutos (`dados-com-init`).
   - Um **Bind Mount** mapeando a pasta local `$(pwd)/infra-scripts` para `/docker-entrypoint-initdb.d/` em modo leitura (`:ro` - read-only):
   ```bash
   docker run -d \
     --name db-provisionado \
     -v dados-com-init:/var/lib/postgresql/data \
     -v "$(pwd)/infra-scripts:/docker-entrypoint-initdb.d:ro" \
     -e POSTGRES_USER=aluno \
     -e POSTGRES_PASSWORD=segredo \
     -e POSTGRES_DB=escola \
     postgres:17-alpine
   ```

5. Observe os logs de inicialização do PostgreSQL para confirmar a execução do script:
   ```bash
   docker logs db-provisionado | grep "01-init.sql"
   ```
   *Saída observada:*
   ```text
   /usr/local/bin/docker-entrypoint.sh: running /docker-entrypoint-initdb.d/01-init.sql
   CREATE TABLE
   INSERT 0 3
   ```

6. Inspecione o banco via `psql` para comprovar que a tabela já nasceu populada:
   ```bash
   docker exec -it db-provisionado psql -U aluno -d escola -c "SELECT id, descricao, concluida FROM tarefas_padrao;"
   ```
   *Resultado:* As 3 tarefas foram criadas automaticamente na subida inicial!

7. **Atenção — A Armadilha de reinicialização:** Se você alterar o arquivo `infra-scripts/01-init.sql` agora e reiniciar o container (`docker restart db-provisionado`), o script **NÃO** será executado de novo. Por quê? Porque o PostgreSQL verifica que o diretório `/var/lib/postgresql/data` já contém um cluster de banco inicializado. O `/docker-entrypoint-initdb.d/` só executa quando o volume de dados está **completamente vazio**.

8. Limpeza deste cenário:
   ```bash
   docker rm -f db-provisionado
   docker volume rm dados-com-init
   rm -rf infra-scripts
   ```

---

### ⚠️ Anti-padrão: Permissões de Arquivo em Bind Mounts
No Linux, um Bind Mount preserva o UID/GID do arquivo do host. Se um container rodar como usuário não-root (como o usuário `postgres` de UID 70 ou `node` de UID 1000) e tentar escrever em uma pasta mapeada que pertence a `root:root` no host, a aplicação quebra com `EACCES: permission denied` ou `Permission denied`. Named volumes evitam esse problema porque o daemon do Docker inicializa o volume com o UID/GID correto especificado pela imagem.

### Como usar a LLM aqui
Peça à LLM: *"Explique o risco de segurança de mapear arquivos do host para dentro do container com Bind Mount sem a flag `:ro` (read-only), especialmente se o container rodar como usuário root"*.

---

## Cenário 4 — Isolamento Multi-Camadas (Segurança: DMZ vs Rede Interna do Banco)

### Causa raiz / Fundamento teórico
Em arquiteturas corporativas e nas normas de segurança em nuvem (como CIS Benchmarks e PCI-DSS), **o banco de dados nunca deve residir na mesma rede acessível aos clientes externos**. Se um atacante explorar uma vulnerabilidade (como RCE - *Remote Code Execution*) no servidor web de borda, ele não deve ter rota direta de rede para a porta do banco de dados.

Com o Docker, implementamos essa segregação criando **duas redes bridge customizadas**:
1. `dmz-publica`: onde vivem o Proxy reverso / Frontend e o Backend.
2. `banco-privada`: onde vivem **exclusivamente** o Backend e o PostgreSQL.

O container do **Backend** atua como uma ponte (*dual-homed*), tendo duas placas de rede virtuais (uma em cada rede). O container do Frontend/Proxy nunca consegue alcançar o banco de dados.

```
       [ Usuário / Internet ]
                 │
                 ▼ (Porta 80)
      ┌─────────────────────┐
      │  proxy-web / front  │ (Conectado APENAS à rede dmz-publica)
      └──────────┬──────────┘
                 │
   ══════════════╪══════════════════════════════ [ REDE: dmz-publica ]
                 │
      ┌──────────┴──────────┐
      │     backend-api     │ (Conectado a AMBAS as redes: dmz + banco)
      └──────────┬──────────┘
                 │
   ══════════════╪══════════════════════════════ [ REDE: banco-privada ]
                 │
      ┌──────────┴──────────┐
      │     db-isolado      │ (Conectado APENAS à rede banco-privada)
      │ (porta 5432 oculta) │
      └─────────────────────┘
```

---

### Como configurar o isolamento passo a passo

1. Crie as duas redes segregadas:
   ```bash
   docker network create dmz-publica
   docker network create banco-privada
   ```

2. Suba o container do banco de dados conectado **estritamente** à `banco-privada`:
   ```bash
   docker run -d \
     --name db-isolado \
     --network banco-privada \
     -e POSTGRES_USER=aluno \
     -e POSTGRES_PASSWORD=segredo \
     -e POSTGRES_DB=escola \
     postgres:17-alpine
   ```

3. Suba um container simulando o **Frontend/Proxy de borda** conectado **apenas** à `dmz-publica`:
   ```bash
   docker run -d \
     --name proxy-web \
     --network dmz-publica \
     alpine:latest sleep 3600
   ```

4. Suba o container do **Backend**, inicialmente conectado à `dmz-publica`:
   ```bash
   docker run -d \
     --name backend-api \
     --network dmz-publica \
     alpine:latest sleep 3600
   ```

5. Conecte o `backend-api` também à `banco-privada` (agora ele possui duas interfaces de rede):
   ```bash
   docker network connect banco-privada backend-api
   ```

---

### Como observar e testar a segurança

1. **Teste 1: O Frontend/Proxy tenta alcançar o banco de dados diretamente**
   ```bash
   docker exec -it proxy-web ping -c 2 db-isolado
   ```
   *Resultado observado:*
   ```text
   ping: bad address 'db-isolado'
   ```
   O DNS embutido da rede `dmz-publica` nem sequer sabe da existência do nome `db-isolado`. O banco está totalmente invisível e inacessível para o container de borda!

2. **Teste 2: O Backend tenta alcançar o banco de dados**
   ```bash
   docker exec -it backend-api ping -c 2 db-isolado
   ```
   *Resultado observado:*
   ```text
   64 bytes from ...: seq=0 ttl=64 time=0.078 ms
   ```
   O Backend resolve o nome e comunica-se com sucesso com o banco.

3. **Teste 3: O Frontend tenta alcançar o Backend**
   ```bash
   docker exec -it proxy-web ping -c 2 backend-api
   ```
   *Resultado observado:*
   ```text
   64 bytes from ...: seq=0 ttl=64 time=0.065 ms
   ```
   O Frontend consegue falar com o Backend normalmente através da rede `dmz-publica`.

4. **Inspecione a tabela de interfaces de rede do Backend:**
   ```bash
   docker exec -it backend-api ip -br addr
   ```
   *Saída observada:* O container possui `eth0` (com IP na sub-rede da `dmz-publica`) e `eth1` (com IP na sub-rede da `banco-privada`)!

5. Limpeza deste cenário:
   ```bash
   docker rm -f proxy-web backend-api db-isolado
   docker network rm dmz-publica banco-privada
   ```

---

### Como usar a LLM aqui
Peça à LLM para simular o papel de um invasor: *"Se um invasor conseguir executar código arbitrário dentro do container `proxy-web`, ele consegue varrer ou capturar tráfego do container `db-isolado`? Qual isolamento do kernel Linux (namespaces / iptables) impede esse acesso?"*.

---

## Cenário 5 — O Antipadrão da Porta Exposta no Host vs Comunicação Segura Inter-Container

### Causa raiz / Fundamento teórico
Este é o erro conceitual mais frequente entre desenvolvedores que migram de ambientes locais para Docker:
> *"Para o backend conseguir falar com o banco de dados no container, eu preciso colocar `-p 5432:5432` no comando do PostgreSQL."*

**Isso é falso e perigoso.** 
- A flag `-p 5432:5432` (**publicação de portas**) cria regras no `iptables` do host que abrem a porta em `0.0.0.0`, expondo o banco para **toda a rede local, Wi-Fi da faculdade e qualquer pessoa na internet** que alcance o IP da sua máquina.
- Quando dois containers compartilham uma rede Docker (`User-Defined Bridge`), eles conversam diretamente através das interfaces virtuais na porta padrão do serviço (porta 5432 interna), **sem precisar de nenhuma publicação no host**!

Agora vamos comprovar isso conectando a aplicação real da disciplina ([`gotodolist`](https://github.com/elton-bt/gotodolist)) a um banco que tem **zero portas abertas no host**.

---

### Como executar o cenário real com o `gotodolist`

1. Crie a rede de aplicação e o volume de dados:
   ```bash
   docker network create rede-gotodolist
   docker volume create dados-gotodolist
   ```

2. Suba o PostgreSQL **SEM a flag `-p`** (note que não há nenhum `-p 5432:5432`):
   ```bash
   docker run -d \
     --name gotodolist-db \
     --network rede-gotodolist \
     -v dados-gotodolist:/var/lib/postgresql/data \
     -e POSTGRES_USER=gotodolist \
     -e POSTGRES_PASSWORD=umasenhaqualquer \
     -e POSTGRES_DB=gotodolist \
     postgres:17-alpine
   ```

3. **Comprove no host que a porta 5432 está COMPLETAMENTE FECHADA:**
   Abra um terminal no seu host e execute:
   ```bash
   ss -tulpn | grep 5432
   ```
   *Saída observada:* Vazia! Nenhum processo no host está escutando na porta 5432.
   
   Tente conectar pelo host via `nc` ou `/dev/tcp`:
   ```bash
   cat < /dev/tcp/127.0.0.1/5432
   ```
   *Resultado esperado:* `bash: connect: Connection refused`. O banco de dados está invisível para o mundo exterior!

4. Agora vamos compilar e empacotar o backend Go do `gotodolist` em uma imagem Docker conectada à mesma rede.  
   Verifique se está na raiz do repositório `gotodolist`:
   ```bash
   pwd # deve terminar em gotodolist
   ```

5. Crie um `Dockerfile.backend-lab` temporário na raiz do projeto para subir a API:
   ```dockerfile
   cat << 'EOF' > Dockerfile.backend-lab
   FROM golang:1.26-alpine AS builder
   WORKDIR /app
   COPY go.mod go.sum ./
   RUN go mod download
   COPY . .
   RUN CGO_ENABLED=0 GOOS=linux go build -o /app/server ./desacoplado/backend

   FROM alpine:latest
   WORKDIR /app
   COPY --from=builder /app/server /app/server
   EXPOSE 8081
   ENTRYPOINT ["/app/server"]
   EOF
   ```

6. Construa a imagem da API:
   ```bash
   docker build -f Dockerfile.backend-lab -t gotodolist-api:lab .
   ```

7. Suba o container da API conectado à **mesma rede** `rede-gotodolist`, apontando a variável `DB_HOST=gotodolist-db` (o nome do container do banco!):
   ```bash
   docker run -d \
     --name gotodolist-backend \
     --network rede-gotodolist \
     -p 8081:8081 \
     -e APP_PORT=8081 \
     -e DB_HOST=gotodolist-db \
     -e DB_PORT=5432 \
     -e DB_NAME=gotodolist \
     -e DB_USER=gotodolist \
     -e DB_PASSWORD=umasenhaqualquer \
     -e DB_SSLMODE=disable \
     -e CORS_ALLOW_ORIGIN='*' \
     gotodolist-api:lab
   ```

8. Observe os logs do backend Go:
   ```bash
   docker logs gotodolist-backend
   ```
   *Saída esperada:*
   ```text
   level=INFO msg="conectado ao banco com sucesso"
   level=INFO msg="servidor rodando na porta :8081"
   ```

9. Faça uma requisição HTTP pelo seu host para validar o funcionamento ponta a ponta:
   ```bash
   curl -i http://localhost:8081/health
   ```
   *Resultado observado:* `HTTP/1.1 200 OK` e `{"status":"ok"}`!

10. Cadastre uma tarefa via API para comprovar a gravação efetiva no banco interno:
    ```bash
    curl -X POST http://localhost:8081/api/tasks \
      -H "Content-Type: application/json" \
      -d '{"title": "Validar banco seguro sem porta exposta no host"}'
    
    # Listar tarefas
    curl http://localhost:8081/api/tasks
    ```

11. Confirme diretamente dentro do banco que o registro existe:
    ```bash
    docker exec -it gotodolist-db psql -U gotodolist -d gotodolist -c "SELECT id, title FROM tasks;"
    ```

---

### Fechamento do Conceito
- A porta `8081` da API **precisa** de `-p 8081:8081` porque usuários e navegadores precisam acessá-la a partir do host.
- A porta `5432` do banco **NÃO** deve ter `-p 5432:5432` porque apenas a API precisa falar com o banco, e ambos já residem na mesma rede virtual privada do Docker.
- Essa prática fecha portas de ataque e segue o princípio do menor privilégio em segurança defensiva de infraestrutura.

### Como usar a LLM aqui
Peça à LLM: *"Explique o que acontece com as regras da tabela `nat` do `iptables` do Linux quando usamos a flag `-p 5432:5432` no Docker e por que serviços de varredura como o Shodan conseguem encontrar bancos de dados expostos acidentalmente dessa forma"*.

---

# PARTE 2 — Backup, Restore e Disaster Recovery de Volumes

## Cenário 6 — Backup e Restore de Volumes: O Padrão de Container Efêmero com `tar`

### Causa raiz / Motivação técnica
Como fazemos backup de um volume gerenciado pelo Docker (`/var/lib/docker/volumes/...`) em um servidor de produção se os arquivos pertencem a usuários do sistema restritos e o Docker desencoraja acessar diretamente o diretório do daemon?

A documentação oficial do Docker estabelece um padrão elegante e reproduzível chamado **Docker Volume Backup Pattern**:
- Criamos um container temporário e descartável (`alpine`) com a flag `--rm`.
- Montamos o volume que queremos salvar em `/data`.
- Montamos o diretório atual do host em `/backup`.
- Executamos uma instrução compactando os dados com `tar -czvf /backup/meu-backup.tar.gz -C /data .`.
- Ao terminar a compactação, o container é destruído automaticamente e o arquivo `.tar.gz` permanece no host!

---

### Executando o Backup

1. Garanta que o container do banco está parado antes do snapshot para consistência dos arquivos de log WAL (ou faça o backup a frio):
   ```bash
   docker stop gotodolist-db
   ```

2. Execute o comando de backup com container efêmero:
   ```bash
   docker run --rm \
     -v dados-gotodolist:/volume-origem:ro \
     -v "$(pwd):/destino-backup" \
     alpine:latest \
     tar -czf /destino-backup/backup-gotodolist.tar.gz -C /volume-origem .
   ```

3. Verifique o arquivo gerado no host:
   ```bash
   ls -lh backup-gotodolist.tar.gz
   ```
   O arquivo compactado contém toda a estrutura física do banco PostgreSQL!

---

### Simulando a Recuperação de Desastre (Disaster Recovery)

1. Destrua completamente o container e o volume original:
   ```bash
   docker rm -f gotodolist-db
   docker volume rm dados-gotodolist
   ```
   *Se tentássemos rodar o banco agora, todas as tarefas teriam sumido.*

2. Crie um novo volume limpo para a restauração:
   ```bash
   docker volume create dados-gotodolist-restaurado
   ```

3. Execute o container efêmero de restauração para descompactar o arquivo no novo volume:
   ```bash
   docker run --rm \
     -v dados-gotodolist-restaurado:/volume-destino \
     -v "$(pwd):/origem-backup:ro" \
     alpine:latest \
     tar -xzf /origem-backup/backup-gotodolist.tar.gz -C /volume-destino
   ```

4. Suba um novo container apontando para o volume restaurado:
   ```bash
   docker run -d \
     --name gotodolist-db-recuperado \
     --network rede-gotodolist \
     -v dados-gotodolist-restaurado:/var/lib/postgresql/data \
     -e POSTGRES_USER=gotodolist \
     -e POSTGRES_PASSWORD=umasenhaqualquer \
     -e POSTGRES_DB=gotodolist \
     postgres:17-alpine
   ```

5. Verifique se os dados da tarefa inserida no Cenário 5 sobreviveram à catástrofe:
   ```bash
   docker exec -it gotodolist-db-recuperado psql -U gotodolist -d gotodolist -c "SELECT id, title FROM tasks;"
   ```
   *Resultado:* **Recuperação de desastres realizada com sucesso total!**

6. Limpeza do arquivo de backup:
   ```bash
   rm -f backup-gotodolist.tar.gz
   ```

### Como usar a LLM aqui
Peça à LLM: *"Qual é a diferença de consistência entre fazer backup físico de arquivos de dados do PostgreSQL copiando os blocos com `tar` (cold backup) versus gerar um dump lógico transacional com o comando `pg_dump` enquanto o banco está rodando em produção?"*.

---

## Cenário 7 — Aliases de Rede e Resolução Round-Robin no DNS do Docker

### Causa raiz / Motivação
Em arquiteturas escaláveis, muitas vezes precisamos subir múltiplas instâncias idênticas de uma API ou serviço e queremos que os clientes internos distribuam o tráfego de forma equilibrada sem precisarmos instalar um balanceador dedicado no início.

O servidor DNS interno do Docker (`127.0.0.11`) suporta a flag `--network-alias`. Quando dois ou mais containers compartilham o mesmo alias de rede, o DNS embutido responde com a lista de IPs de todos os containers e rotaciona a ordem da resposta a cada consulta (**DNS Round-Robin**).

---

### Como testar na prática

1. Crie uma rede de teste:
   ```bash
   docker network create rede-balanceada
   ```

22. Suba dois containers web simples compartilhando o mesmo alias de rede `servico-api`:
   ```bash
   # Instância 1
   docker run -d --name worker-1 \
     --network rede-balanceada \
     --network-alias servico-api \
     nginx:alpine sh -c "echo '<h1>Sou o Worker 1</h1>' > /usr/share/nginx/html/index.html && nginx -g 'daemon off;'"

   # Instância 2
   docker run -d --name worker-2 \
     --network rede-balanceada \
     --network-alias servico-api \
     nginx:alpine sh -c "echo '<h1>Sou o Worker 2</h1>' > /usr/share/nginx/html/index.html && nginx -g 'daemon off;'"
   ```

3. Suba um container cliente para disparar consultas DNS sucessivas usando o comando `nslookup` (ou `ping`):
   ```bash
   docker run --rm --network rede-balanceada alpine:latest nslookup servico-api
   ```
   *Repare na resposta:* Ele retorna dois IPs diferentes associados ao mesmo nome `servico-api`!

4. Execute uma consulta repetida para ver a alternância de respostas:
   ```bash
   docker run --rm --network rede-balanceada alpine:latest sh -c "
     for i in \$(seq 1 10); do
       wget -qO- http://servico-api
       sleep 1
     done
   "
   ```
   *Resultado observado:* As requisições alternam entre `Sou o Worker 1` e `Sou o Worker 2`.

5. Limpeza:
   ```bash
   docker rm -f worker-1 worker-2
   docker network rm rede-balanceada
   ```

---

## Cenário 8 — Isolamento Absoluto com Rede `--internal` (Prevenção de Vazamento de Dados)

### Causa raiz / Motivação
Por padrão, uma User-Defined Bridge permite que containers façam conexões de saída (*egress*) para a internet através do NAT (*Network Address Translation*) da máquina host. 

No entanto, em ambientes que tratam dados ultrassensíveis (bancos de dados financeiros, prontuários de saúde), você quer garantir que **mesmo que o container do banco seja comprometido, ele não consiga abrir conexões reversas para servidores de comando e controle na internet**.

O Docker permite criar redes com a flag `--internal`:
```bash
docker network create --internal rede-estritamente-fechada
```

---

### Como comprovar o isolamento de saída

1. Crie uma rede puramente interna:
   ```bash
   docker network create --internal rede-estritamente-fechada
   ```

2. Suba um container de teste nessa rede:
   ```bash
   docker run -d --name cofre-dados \
     --network rede-estritamente-fechada \
     alpine:latest sleep 3600
   ```

3. Tente fazer um ping ou requisição HTTP para a internet:
   ```bash
   docker exec -it cofre-dados ping -c 2 8.8.8.8
   ```
   *Resultado observado:*
   ```text
   PING 8.8.8.8 (8.8.8.8): 56 data bytes
   ping: sendto: Network unreachable
   ```
   O Docker não cria a rota padrão de gateway para o host nem regras de mascaramento (NAT) para essa rede. O container está 100% incomunicável com o mundo exterior.

4. Agora crie outro container na mesma rede interna:
   ```bash
   docker run -d --name cofre-app \
     --network rede-estritamente-fechada \
     alpine:latest sleep 3600
   ```

5. Teste a comunicação entre os dois containers internos:
   ```bash
   docker exec -it cofre-app ping -c 2 cofre-dados
   ```
   *Resultado observado:* **Comunicação interna 100% funcional!** Eles conversam livremente entre si, mas nenhum pacote escapa para a internet.

6. Limpeza:
   ```bash
   docker rm -f cofre-dados cofre-app
   docker network rm rede-estritamente-fechada
   ```

---

## Tabela-Resumo (Cheat Sheet)

| Sintoma observado | Causa provável no Docker | Primeiro comando de diagnóstico | Como corrigir |
| :--- | :--- | :--- | :--- |
| Dados sumiram após `docker rm` | Container rodou na camada efêmera (*writable layer*) | `docker inspect <container> --format '{{json .Mounts}}'` | Montar Named Volume (`-v meu-volume:/var/lib/...`) |
| `ping: bad address 'nome-container'` | Container na rede `bridge` padrão (sem DNS embutido) | `docker inspect <container> --format '{{.NetworkSettings.Networks}}'` | Criar e conectar em rede customizada (`docker network create`) |
| `Permission denied` ao escrever em pasta montada | Conflito de UID/GID em Bind Mount do host | `ls -ld <pasta-host>` e `docker exec <container> id` | Ajustar permissões no host (`chown`) ou usar Named Volume |
| `Network unreachable` ao acessar a internet | Container anexado a uma rede criada com `--internal` | `docker network inspect <rede>` (checar `"Internal": true`) | Usar rede bridge comum se precisar de saída para internet |
| Conexão recusada tentando falar com container na mesma rede | Serviço não está escutando na interface `0.0.0.0` ou porta errada | `docker exec <container> ss -tulpn` | Garantir que o processo interno escute em `0.0.0.0` e não `127.0.0.1` |
| Erro de concorrência ou bloqueio de banco de dados | Dois containers montando o mesmo volume de dados simultaneamente | `docker ps -q | xargs docker inspect` | Evitar que duas instâncias de banco disputem o mesmo diretório de dados |

---

## Entregável (para a nota N1 — Desafios de Laboratório)

Preencham a tabela abaixo para **todos os cenários de 1 a 5**.

| Cenário | Sintoma ou Erro Observado | Causa Raiz Técnica | Comando de Inspeção Utilizado | Solução Arquitetural Aplicada |
| :--- | :--- | :--- | :--- | :--- |
| 1 — Efemeridade (sem volume) | | | | |
| 1 — Persistência (Named Volume) | | | | |
| 2 — DNS na Bridge Default | | | | |
| 2 — DNS na User-Defined Bridge | | | | |
| 3 — Bind Mount & Injeção SQL | | | | |
| 4 — Isolamento DMZ vs Banco | | | | |
| 5 — Banco sem porta no Host | | | | |
| 6 — Backup de Volume com tar  | | | | |
| 7 — Aliases & Round-Robin  | | | | |
| 8 — Rede `--internal`  | | | | |

---

### Armadilhas conhecidas
- **WSL2 no Windows:** Os volumes nomeados ficam dentro do VHDX da distribuição Linux (`\\wsl$\Ubuntu\var\lib\docker\volumes`), o que garante excelente performance de I/O. Porém, se os alunos usarem Bind Mount apontando para o sistema de arquivos do Windows (`/mnt/c/...`), a performance de I/O do banco de dados cai drasticamente devido à camada de tradução do 9P protocol. Sempre manter os projetos dentro da árvore Linux nativa (`~/...`).
- **Limpeza de Volumes:** `docker rm -f` não remove volumes associados por padrão! Para remover o volume junto com o container, é necessário usar `docker rm -v`. Vocês devem inspecionar os volumes com `docker volume ls` para não acumularem "volumes órfãos" no disco do laboratório (`docker volume prune`).
- **Postgres e Reexecução de Scripts:** Regra do entrypoint do PostgreSQL: scripts em `/docker-entrypoint-initdb.d/` só rodam na primeira vez que o cluster é criado. Se o volume já tiver arquivos, o Postgres ignora o diretório. 

