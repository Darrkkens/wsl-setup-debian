# ============================================================
# Script Interativo de Pós-Instalação Debian/Ubuntu
# ============================================================
#
# Visão geral:
#   Este script fornece um pós-instalação interativo, baseado em menus,
#   para sistemas Debian/Ubuntu, com tratamento especial para WSL.
#   Permite instalar ou remover stacks de desenvolvimento, ferramentas
#   e utilitários do sistema via menus e checklists com whiptail.
#
# Funcionalidades:
#   - Instalação por presets para ambientes comuns (Web, Go, Python, SysAdmin, Full)
#   - Checklist manual para instalar/remover ferramentas individuais
#   - Barras de progresso (whiptail --gauge) para feedback visual
#   - Log em /var/log/postinstall-menu.log
#   - Detecção de WSL e tratamento especial (systemd, Docker, etc.)
#   - Configuração de locale e timezone
#   - Funções modulares de instalar/remover para:
#       - Linguagens (Java, Node.js, Go, Python, Rust, PHP)
#       - Bancos de dados (PostgreSQL, Redis, clientes DB)
#       - Servidores web (Nginx + Certbot)
#       - Ferramentas DevOps (Docker, Podman, Kubernetes, etc.)
#       - Produtividade e QoL (fzf, tmux, neovim, etc.)
#       - Segurança (SSH, GPG, UFW, Fail2ban)
#       - Diversão/estilo (lolcat, figlet, cowsay)
#
# Uso:
#   Execute como root ou com sudo:
#     sudo bash script.sh
#
#   Siga os menus interativos para selecionar presets ou escolher
#   manualmente o que instalar ou remover.
#
# Estrutura:
#   - Configuração base: Variáveis de locale, timezone, usuário, etc.
#   - Funções utilitárias: Log, verificação de root, existência de comandos, etc.
#   - Helpers de gauge: Gerenciamento de barra de progresso
#   - Módulos de instalar/remover: Funções para cada ferramenta/stack
#   - Presets: Instalações agrupadas para casos de uso comuns
#   - Menus: Menus interativos whiptail para seleção do usuário
#   - Execução principal: Pré-setup, locale/timezone, loop de menu
#
# Notas:
#   - Feito para Debian/Ubuntu, especialmente sob WSL (Windows Subsystem for Linux)
#   - Alguns recursos (ex: Docker Engine) têm avisos/tratamento especial no WSL
#   - Todas ações são logadas para troubleshooting
#   - Script é idempotente e seguro para re-execução; checa instalações existentes
#
# Autor: zwx
# Versão: 2.3
# Licença: MIT (ou conforme especificado pelo autor)
#
# ============================================================
