# Infraestrutura como Código (IaC) - Laboratórios e Práticas

Repositório com códigos, scripts e configurações práticas voltadas para o aprendizado e aplicação dos conceitos de **Infraestrutura como Código (IaC)**, automação de ambientes, gerenciamento de configuração, conteinerização, orquestração e computação em nuvem.

Este material faz parte das atividades e laboratórios práticos da disciplina de **Infraestrutura de TI** (IFPE - Campus Belo Jardim / Residência Tecnológica Moura Tech), estruturado de forma didática e progressiva: desde scripts básicos de automação até orquestração em cluster e provisionamento em nuvem pública.

---

## 🛠️ Tecnologias e Ferramentas Utilizadas

- **Shell Scripting (Bash):** Automação sequencial de provisionamento e execução remota via SSH.
- **Vagrant & VirtualBox:** Criação, versionamento e gerenciamento de máquinas virtuais locais (IaaS local).
- **Ansible:** Gerenciamento de configuração, automação idempotente com comandos *ad-hoc* e *playbooks* YAML.
- **Docker & Docker Compose:** Criação de imagens de contêineres (*Dockerfiles*, *multi-stage builds*) e orquestração de múltiplos serviços.
- **Docker Swarm:** Orquestração de contêineres em cluster (*manager* e *workers*), réplicas de serviços, redes virtuais e balanceamento de carga.
- **Microsoft Azure (Azure CLI):** Provisionamento de recursos na nuvem pública em modelos **IaaS** (Máquinas Virtuais e *Scale Sets*) e **PaaS** (*App Services* e *Static Web Apps*).

---

## 📁 Estrutura do Repositório

Abaixo está o detalhamento de cada diretório e módulo do repositório:

```text
IaC/
├── 0_install_nginx.sh                         # Script Bash para deploy local automatizado de aplicação React com Nginx
├── 1_install_nginx_nodes.sh                   # Automação via SSH para provisionar Nginx em lista de servidores remotos
├── server.js                                  # Servidor HTTP simples em Node.js/Express para testes de conectividade
├── 01_Vagrant/                                # Módulo 1: Introdução ao Vagrant (VM Ubuntu com placa em bridge)
├── 02_Vagrant/                                # Módulo 2: Customização de hardware virtual (CPU/RAM) e Synced Folders
├── 03_Vagrant/                                # Módulo 3: Multi-machine com SOs heterogêneos (Ubuntu + CentOS)
├── 04_Vagrant/                                # Módulo 4: Provisionamento automatizado com Shell Script inline
├── 05_Vagrant/                                # Módulo 5: Laboratório completo de Ansible (Nó de controle + 3 nós gerenciados)
├── 05.1_Vagrant/                              # Módulo 5.1: Integração nativa do provisionador Ansible dentro do Vagrant
├── 06_Vagrant/                                # Módulo 6: Ambiente Docker, Dockerfiles, comandos práticos e Docker Compose
├── 07_Vagrant/                                # Módulo 7: Cluster Docker Swarm multi-nó com stack e load balancer
└── Azure/                                     # Módulo 8: Automação e provisionamento na nuvem Microsoft Azure (CLI)
```

---

## 📚 Detalhamento dos Módulos

### 1. Automação com Shell Scripts
- **[`0_install_nginx.sh`](0_install_nginx.sh):** Atualiza o sistema, instala Nginx, Node.js e ferramentas essenciais, clona o repositório de uma aplicação React (`react-example-app`), compila os artefatos estáticos e publica no diretório `/var/www/html/`.
- **[`1_install_nginx_nodes.sh`](1_install_nginx_nodes.sh):** Lê uma lista com IPs e usuários (`serverFile`) e executa o provisionamento remoto via SSH com autenticação por chave privada, configurando também as regras de firewall (`ufw`).

### 2. Vagrant (Ambientes Locais e Multi-Machine)
- **[`01_Vagrant/`](01_Vagrant/):** Criação de uma máquina virtual Ubuntu 22.04 LTS (`ubuntu/jammy64`) conectada em modo `public_network` (bridge).
- **[`02_Vagrant/`](02_Vagrant/):** Ajuste de capacidade de hardware (1024 MB de RAM, 2 vCPUs) no VirtualBox e mapeamento de diretório compartilhado host-guest (`synced_folder`).
- **[`03_Vagrant/`](03_Vagrant/):** Configuração multi-máquinas em um único `Vagrantfile`, provisionando simultaneamente uma máquina Ubuntu (`srvweb01`) e uma máquina CentOS 7 (`srvweb02`).
- **[`04_Vagrant/`](04_Vagrant/):** Provisionamento automatizado direto no Vagrant via Shell Script inline (`config.vm.provision "shell"`), configurando rede privada com IP estático e fazendo o build/deploy automático da aplicação web.

### 3. Ansible (Gerenciamento de Configuração)
- **[`05_Vagrant/`](05_Vagrant/):** Laboratório com topologia de 4 VMs interligadas em rede privada (`192.168.56.0/24`):
  - `ansible`: Nó de controle (Ansible instalado, geração automática de par de chaves SSH e distribuição pública).
  - `srvweb01`: Nó gerenciado (Ubuntu 22.04).
  - `srvweb02`: Nó gerenciado (Debian 11 Bullseye).
  - `srvbd`: Nó gerenciado (CentOS 7).
  - **Inventário e Configuração:** [`hosts`](05_Vagrant/hosts) e [`ansible.cfg`](05_Vagrant/ansible.cfg).
  - **Comandos Ad-hoc:** [`ansible-comandos-adhoc.ini`](05_Vagrant/ansible-comandos-adhoc.ini) com exemplos práticos dos módulos `ping`, `shell`, `package`, `service` e `copy`.
  - **Playbooks Progressivos:**
    - [`01playbook-tranfere-arquivo.yml`](05_Vagrant/01playbook-tranfere-arquivo.yml): Cópia de arquivos com módulo `copy`.
    - [`02playbook-instala-pacotes.yml`](05_Vagrant/02playbook-instala-pacotes.yml): Uso de loops (`loop`) e módulo `apt`.
    - [`03playbook-static.yml`](05_Vagrant/03playbook-static.yml): Condicionais (`when`), clonagem de repositório Git e gerenciamento de serviço Nginx.
    - [`04playbook-react.yml`](05_Vagrant/04playbook-react.yml): Pipeline completo de deploy de aplicação React (instalação de dependências via NPM, build da aplicação, cópia remota para Nginx e inicialização do serviço).
- **[`05.1_Vagrant/`](05.1_Vagrant/):** Demonstração do provisionador Ansible nativo do Vagrant (`config.vm.provision "ansible"`), executando o playbook [`deploy_playbook.yml`](05.1_Vagrant/deploy_playbook.yml) diretamente no ciclo de vida da máquina.

### 4. Docker e Docker Compose
- **[`06_Vagrant/`](06_Vagrant/):** VM Ubuntu com Docker Engine e Docker Compose pré-instalados via script de provisionamento.
  - **Cheat Sheet Docker:** [`comandos_docker.ini`](06_Vagrant/comandos_docker.ini) contendo comandos essenciais para ciclo de vida de contêineres, inspeção de métricas, binds, volumes, gerenciamento de imagens e publicação no Docker Hub.
  - **Dockerfiles Práticos (`dockerfiles/`):**
    - `static/`: Imagem baseada em Ubuntu vs. imagem enxuta baseada em Alpine Linux.
    - `react/`: Build e limpeza em camada única.
    - `multistage/`: Padrão profissional de **Multi-stage Build** (estágio de compilação em Ubuntu/Node e estágio final de produção em Nginx Alpine leve).
  - **Docker Compose:** [`docker-compose.yml`](06_Vagrant/docker-compose.yml) orquestrando uma aplicação Todo em Node.js (`app/`) com banco de dados MySQL 5.7 e volume persistente.

### 5. Docker Swarm (Orquestração em Cluster)
- **[`07_Vagrant/`](07_Vagrant/):** Ambiente completo simulando um cluster de produção:
  - `master`: Nó gerenciador (*Manager*) que executa `docker swarm init` e gera dinamicamente o script de adesão [`worker.sh`](07_Vagrant/worker.sh).
  - `node01` e `node02`: Nós trabalhadores (*Workers*) que entram automaticamente no cluster.
  - **Stack de Serviços (`docker-compose.yml`):**
    - `app`: Serviço web escalado com **3 réplicas**, limites de recursos (CPU e memória) e política de reinicialização.
    - `mysql`: Banco de dados fixado no nó manager (`node.role == manager`) com volume compartilhado.
    - `loadbalancer`: Balanceador Nginx na porta 80 fixado no manager, integrando redes isoladas `frontend` e `backend`.

### 6. Nuvem com Microsoft Azure (Azure CLI)
- **[`Azure/`](Azure/):** Automação de infraestrutura em nuvem usando Azure CLI:
  - [`01_cria-vm-azure.azcli`](Azure/01_cria-vm-azure.azcli): Provisionamento de VM Linux (IaaS), liberação de portas e execução de comandos remotos (`az vm run-command`).
  - [`02_instala_IIS_e_implanta_site_conjunto_escalas_vms.azcli`](Azure/02_instala_IIS_e_implanta_site_conjunto_escalas_vms.azcli): Criação de *Virtual Machine Scale Sets* (VMSS) com balanceador de carga (`Load Balancer`) e extensão de script customizado.
  - [`03_staticweb_abc.azcli`](Azure/03_staticweb_abc.azcli): Deploy de site estático no serviço PaaS *Azure Static Web Apps* conectado a repositório do GitHub.
  - [`app_web_ex1_paas.azcli`](Azure/app_web_ex1_paas.azcli): Criação de plano de serviço *App Service Plan* e implantação de aplicação web PaaS via GitHub.
  - [`script-vm-scale-set`](Azure/script-vm-scale-set): Configuração declarativa via `cloud-config` (cloud-init) para inicializar instâncias do Scale Set com proxy reverso Nginx e aplicação Express.

---

## 🚀 Como Utilizar

### Pré-requisitos
Para reproduzir os laboratórios localmente, recomenda-se possuir instalados:
- [VirtualBox](https://www.virtualbox.org/) (versão 6.1 ou superior)
- [Vagrant](https://www.vagrantup.com/) (versão 2.3 ou superior)
- [Docker](https://www.docker.com/) e [Docker Compose](https://docs.docker.com/compose/) (opcional para testes diretos no host)
- [Azure CLI](https://learn.microsoft.com/pt-br/cli/azure/install-azure-cli) (para os laboratórios de nuvem)

### Executando os Laboratórios Vagrant
Navegue até a pasta do laboratório desejado (por exemplo, `01_Vagrant` ou `05_Vagrant`):

```bash
# Entrar no diretório do laboratório
cd 01_Vagrant

# Inicializar e provisionar as máquinas virtuais
vagrant up

# Acessar a máquina virtual via Vagrant SSH
vagrant ssh
# (Para ambientes multi-machine, especifique o nome da máquina: ex: vagrant ssh srvweb01)

# Desligar as máquinas
vagrant halt

# Destruir as máquinas e liberar espaço em disco
vagrant destroy -f
```

#### 🔑 Acessando via SSH tradicional com a Chave Privada do Vagrant
Além do atalho `vagrant ssh`, você pode acessar as máquinas virtuais utilizando o cliente `ssh` nativo do seu terminal ou qualquer ferramenta externa (como VS Code Remote SSH, Termius ou scripts externos).

O Vagrant gera automaticamente um par de chaves SSH exclusivo para cada máquina virtual criada, armazenando a chave privada no diretório local `.vagrant/`.

1. **Inspecionar as configurações de conexão geradas:**
   ```bash
   vagrant ssh-config
   ```
   *Esse comando exibe o IP (`HostName`), porta (`Port`), usuário (`User`) e o caminho exato da chave privada (`IdentityFile`).*

2. **Conectar diretamente via comando `ssh` nativo:**
   - **Para máquinas únicas (ex: `01_Vagrant`, `04_Vagrant`, `06_Vagrant`):**
     ```bash
     # Conexão pelo IP da rede privada (ex: IP 192.168.56.200 do 06_Vagrant):
     ssh -i .vagrant/machines/default/virtualbox/private_key vagrant@192.168.56.200

     # Ou através da porta encaminhada no localhost (normalmente 2222):
     ssh -i .vagrant/machines/default/virtualbox/private_key -p 2222 vagrant@127.0.0.1
     ```

   - **Para ambientes multi-máquinas (ex: `05_Vagrant`, `07_Vagrant`):**
     O caminho substitui `default` pelo nome atribuído à máquina no `Vagrantfile`:
     ```bash
     # Exemplo: conectando no nó 'ansible' (192.168.56.30) do laboratório 05:
     ssh -i .vagrant/machines/ansible/virtualbox/private_key vagrant@192.168.56.30

     # Exemplo: conectando no nó 'master' (192.168.56.100) do cluster Swarm no 07:
     ssh -i .vagrant/machines/master/virtualbox/private_key vagrant@192.168.56.100
     ```

> 💡 **Dica:** Se você costuma recriar as máquinas virtuais com frequência (`vagrant destroy` e `vagrant up`), o IP pode ter o host key alterado. Para evitar avisos de chave modificada, adicione as opções:  
> `ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i <caminho_da_chave> vagrant@<ip>`

### Executando Playbooks no Laboratório Ansible (`05_Vagrant`)
Acesse a máquina de controle:
```bash
cd 05_Vagrant
vagrant up
vagrant ssh ansible
```
Dentro do nó de controle:
```bash
# Testar conectividade com todos os nós gerenciados
ansible all -m ping

# Executar um playbook de exemplo
ansible-playbook /vagrant/04playbook-react.yml
```

### Executando o Cluster Docker Swarm (`07_Vagrant`)
```bash
cd 07_Vagrant
vagrant up
vagrant ssh master
```
No nó master:
```bash
# Verificar os nós ativos no cluster
sudo docker node ls

# Fazer o deploy da stack de serviços
sudo docker stack deploy -c /vagrant/docker-compose.yml minha-stack

# Listar os serviços em execução e réplicas
sudo docker stack services minha-stack
```

---

## 👨‍🏫 Autor e Créditos

Material organizado para as atividades da disciplina de **Infraestrutura de TI / IaC** ministrada pelo **Prof. Elton Torres** ([@elton-bt](https://github.com/elton-bt)).
