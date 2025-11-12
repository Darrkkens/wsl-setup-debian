
# WSL Setup Debian - Script de Instalação Automatizada

Este script automatiza a configuração de um ambiente de desenvolvimento no WSL (Windows Subsystem for Linux) com Debian/Ubuntu, oferecendo instalação de ferramentas de desenvolvimento, servidores, e utilitários essenciais.

## 🔧 Sobre o set -euo pipefail

O script inicia com a linha set -euo pipefail, que é uma configuração crucial para tornar o script mais robusto e seguro:

### Explicação detalhada:

- **set -e** (errexit): Faz o script parar imediatamente se qualquer comando retornar código de erro diferente de zero
- **set -u** (nounset): Trata variáveis não definidas como erro, evitando bugs silenciosos
- **set -o pipefail**: Em pipelines (cmd1 | cmd2), considera o código de saída do primeiro comando que falhar, não apenas do último

### Por que isso é importante:

```bash
# Sem pipefail:
false | true    # Retorna 0 (sucesso) - apenas considera o 'true'

# Com pipefail:
false | true    # Retorna 1 (erro) - considera o 'false' que falhou
```

Esta configuração garante que erros não passem despercebidos e o script pare em situações problemáticas, tornando-o mais confiável.

## 📋 Funcionalidades

### Configurações Base
- **Timezone**: America/Sao_Paulo
- **Locale**: pt_BR.UTF-8
- **Frontend**: Não-interativo para instalações automáticas
- **Logging**: Todas as operações são registradas em /var/log/postinstall-menu.log

### Detecção de Ambiente
- Detecta automaticamente se está rodando no WSL
- Ajusta comportamento baseado no ambiente (ex: systemd no WSL)
- Verifica privilégios de root antes de executar

### Interface de Usuário
- Interface visual com whiptail (menus, checkboxes, progress bars)
- Barras de progresso para operações longas
- Mensagens coloridas no terminal:
  - 🟢 **[INFO]**: Informações gerais
  - 🟡 **[WARN]**: Avisos importantes
  - 🔴 **[ERR]**: Erros críticos

## 🛠 Ferramentas Disponíveis

### Linguagens de Programação
- **Java**: OpenJDK 17/21 + Maven/Gradle
- **Node.js**: Versões 18/20/22 + pnpm/yarn + CLIs úteis
- **Go**: Última versão com configuração de GOPATH
- **Python**: Python3 + pip + venv + ferramentas de desenvolvimento
- **Rust**: rustup + rustfmt + clippy
- **PHP**: PHP 8.2 + extensões + Composer

### Bancos de Dados e Cache
- **PostgreSQL**: Versões 14/15/16/17 com cliente
- **Redis**: Servidor e cliente
- **MySQL**: Cliente
- **SQLite**: Cliente

### Servidores e DevOps
- **Nginx**: Com Certbot para SSL
- **Docker**: Engine completo (com aviso sobre Docker Desktop)
- **Kubernetes**: kubectl, helm, k9s
- **Build Tools**: make, cmake, ninja-build
- **Containers**: podman, podman-compose

### Ferramentas de Produtividade
- **CLI Básico**: bash-completion, fzf, ripgrep, tmux, htop, vim
- **CLI Avançado**: bat, eza, neovim, micro, neofetch, btop
- **Utilitários**: jq, yq, httpie, GitHub CLI (gh)
- **Shell**: Zsh + oh-my-zsh

### Rede e Segurança
- **Diagnóstico**: iproute2, dnsutils, nmap, tcpdump, traceroute
- **SSH/GPG**: openssh-client, keychain, gnupg-agent
- **Firewall**: ufw, fail2ban (apenas fora do WSL)

### Backup e Diversão
- **Backup**: rclone, restic, duplicity, borgbackup
- **Diversão**: lolcat, figlet, cowsay

## 🚀 Como Usar

### Pré-requisitos
- WSL com Debian ou Ubuntu
- Acesso de root/sudo

### Execução
```bash
# Torne o script executável
chmod +x wsl-setup-debian.sh

# Execute com privilégios de root
sudo ./wsl-setup-debian.sh

# Execute dessa forma
sudo -E bash ./wsl-setup-debian.sh
```

### Opções de Instalação

#### 1. Presets Prontos
- **Dev Web**: Node.js + PHP + PostgreSQL + Redis + ferramentas QoL
- **Dev Go**: Go + PostgreSQL + Redis + ferramentas QoL
- **Dev Python**: Python + PostgreSQL + Redis + ferramentas QoL
- **SysAdmin**: Nginx + Docker + ferramentas DevOps + segurança
- **Full**: Instalação completa de quase todas as ferramentas

#### 2. Instalação Manual
Interface checkbox que permite selecionar exatamente quais ferramentas instalar.

#### 3. Remoção de Ferramentas
Sistema completo de desinstalação com limpeza de dependências e dados.

## 🔍 Características Técnicas

### Tratamento de Erros
- Captura erros e mostra linha onde ocorreu
- Redirecionamento de saída para log
- Função trap para controle de erros

### Funções Utilitárias
- **cmd_exists()**: Verifica se comando existe
- **append_once()**: Adiciona linha única em arquivos
- **is_wsl()**: Detecta ambiente WSL
- **Funções de gauge**: Barras de progresso visuais

### Instalação Inteligente
- Verifica se ferramentas já estão instaladas
- Adiciona repositórios oficiais quando necessário
- Configura variáveis de ambiente automaticamente
- Limpa cache e dependências não utilizadas

### Compatibilidade com WSL
- Detecta limitações do WSL (systemd, serviços)
- Oferece alternativas quando necessário
- Avisos específicos para Docker Desktop vs Docker Engine

## 📝 Logs e Monitoramento

Todas as operações são registradas em /var/log/postinstall-menu.log incluindo:
- Timestamps de todas as operações
- Saídas de comandos de instalação
- Erros e warnings
- Progresso das operações

## ⚠️ Avisos Importantes

### Docker no WSL
O script detecta WSL e recomenda usar Docker Desktop com integração WSL ao invés do Docker Engine nativo.

### systemd no WSL
Para habilitar systemd no WSL, edite /etc/wsl.conf:
```
[boot]
systemd=true
```
Depois execute wsl --shutdown no Windows e reinicie a distro.

### Backup de Configurações
Antes de usar a funcionalidade de remoção, faça backup de suas configurações importantes, pois algumas remoções são irreversíveis.

## 🔄 Versionamento

**Versão atual**: 2.3

O script é continuamente atualizado com novas ferramentas e melhorias. Verifique regularmente por atualizações.

## 🤝 Contribuições

Para melhorias ou correções, edite o script diretamente ou sugira modificações. O código é modular e facilmente extensível.

---

*Este script foi projetado para facilitar a configuração de ambientes de desenvolvimento no WSL, economizando tempo e garantindo instalações consistentes.*
