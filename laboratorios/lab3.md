### 🧪 Laboratório Prático da Aula 04: Banco Persistente + Backend em Rede Isolada

1. **Criar a rede e o volume:**
   ```bash
   docker network create rede-minha-app
   docker volume create dados-postgres
   ```
2. **Subir o Banco de Dados PostgreSQL conectado à rede e ao volume:**
   ```bash
   docker run -d \
     --name db-postgres \
     --network rede-minha-app \
     -v dados-postgres:/var/lib/postgresql/data \
     -e POSTGRES_USER=aluno \
     -e POSTGRES_PASSWORD=segredo \
     -e POSTGRES_DB=escola \
     postgres:16-alpine
   ```
3. **Criar uma tabela e inserir dados via linha de comando:**
   ```bash
   docker exec -it db-postgres psql -U aluno -d escola -c "
   CREATE TABLE alunos (id SERIAL PRIMARY KEY, nome VARCHAR(100));
   INSERT INTO alunos (nome) VALUES ('Maria Silva'), ('Jose Santos');
   "
   ```
4. **O Teste da Destruição (Simulando uma Falha):**
   ```bash
   docker rm -f db-postgres   # Container foi deletado!
   # Recriando o container exatamente igual apontando para o mesmo volume:
   docker run -d \
     --name db-postgres \
     --network rede-minha-app \
     -v dados-postgres:/var/lib/postgresql/data \
     -e POSTGRES_USER=aluno \
     -e POSTGRES_PASSWORD=segredo \
     -e POSTGRES_DB=escola \
     postgres:16-alpine
   # Consultar os dados novamente:
   docker exec -it db-postgres psql -U aluno -d escola -c "SELECT * FROM alunos;"
   ```
   *Resultado:* Os dados continuam intactos!