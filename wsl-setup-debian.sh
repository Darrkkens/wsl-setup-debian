set -euo pipefail

# =========================
# Config base
# =========================
TIMEZONE="America/Sao_Paulo"
LOCALE="pt_BR.UTF-8"
MAIN_USER="${SUDO_USER:-$USER}"
LOG_FILE="/var/log/postinstall-menu.log"
DEBIAN_FRONTEND=noninteractive

# =========================
# Util
# =========================
log()  { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Execute com sudo/root."
    exit 1
  fi
}

cmd_exists(){ command -v "$1" &>/dev/null; }

append_once(){
  local line="$1" file="$2"
  grep -Fxq "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

is_wsl(){ grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; }

trap 'err "Falha na linha $LINENO. Veja $LOG_FILE"' ERR
exec > >(tee -a "$LOG_FILE") 2>&1

# =========================
# Gauge helpers
# =========================
GAUGE_PIPE=""
GAUGE_BG=""

gauge_begin(){ # $1: título
  GAUGE_PIPE="$(mktemp -u)"
  mkfifo "$GAUGE_PIPE"
  ( whiptail --gauge "$1" 8 70 0 < "$GAUGE_PIPE"; rm -f "$GAUGE_PIPE" ) & GAUGE_BG=$!
  exec 3> "$GAUGE_PIPE"
  gauge_update 1 "Iniciando..."
}
gauge_update(){ echo -e "XXX\n${1}\n${2}\nXXX" >&3; }
gauge_end(){
  gauge_update 100 "Concluído!"
  exec 3>&- || true
  wait "$GAUGE_BG" 2>/dev/null || true
  GAUGE_PIPE=""; GAUGE_BG=""
}

gauge_apt_install(){ # $1: titulo, restantes: pacotes
  local title="$1"; shift || true
  gauge_begin "$title"
  gauge_update 10 "Atualizando índices APT..."
  apt-get update -y >/dev/null 2>&1 || true
  gauge_update 40 "Instalando pacotes..."
  [[ $# -gt 0 ]] && apt-get install -y "$@" >/dev/null 2>&1 || true
  gauge_update 85 "Limpando..."
  apt-get -y autoremove >/dev/null 2>&1 || true
  apt-get -y clean >/dev/null 2>&1 || true
  gauge_end
}

gauge_apt_purge(){ # $1: titulo, restantes: pacotes
  local title="$1"; shift || true
  gauge_begin "$title"
  gauge_update 15 "Removendo pacotes..."
  [[ $# -gt 0 ]] && apt-get purge -y "$@" >/dev/null 2>&1 || true
  gauge_update 65 "Auto-remove dependências..."
  apt-get -y autoremove >/dev/null 2>&1 || true
  gauge_update 90 "Limpando cache..."
  apt-get -y clean >/dev/null 2>&1 || true
  gauge_end
}

# =========================
# Pré-setup
# =========================
pre_setup(){
  gauge_begin "Preparando ambiente / dependências do menu..."
  gauge_update 15 "apt-get update"
  apt-get update -y >/dev/null 2>&1 || true
  gauge_update 60 "Instalando whiptail, curl, git..."
  apt-get install -y whiptail curl wget ca-certificates gnupg lsb-release \
    apt-transport-https unzip zip git jq build-essential >/dev/null 2>&1 || true
  gauge_update 95 "Finalizando pré-setup..."
  gauge_end
}

set_locale_tz(){
  if is_wsl; then
    warn "WSL detectado: pulando timedatectl. Ajuste de locale apenas."
  fi
  gauge_begin "Configurando locale ($LOCALE)"
  sed -i "s/^# *${LOCALE}/${LOCALE}/" /etc/locale.gen || true
  if ! grep -q "^${LOCALE}" /etc/locale.gen; then
    echo "${LOCALE} UTF-8" >> /etc/locale.gen
  fi
  gauge_update 40 "Gerando locale..."
  locale-gen >/dev/null 2>&1 || true
  gauge_update 80 "Aplicando locale..."
  update-locale LANG=${LOCALE} >/dev/null 2>&1 || true
  gauge_end
}

suggest_enable_systemd_wsl(){
  if is_wsl; then
    warn "Dica: para systemd no WSL, edite /etc/wsl.conf com:
[boot]
systemd=true

Depois, no Windows: wsl --shutdown  (e abra novamente a distro)."
  fi
}

# =========================
# Módulos - INSTALAR
# =========================
install_java(){
  local CHOICE
  CHOICE=$(whiptail --title "Java" --menu "Escolha a versão do OpenJDK:" 15 55 5 \
    "17" "LTS (estável)" \
    "21" "LTS (mais recente)" \
    3>&1 1>&2 2>&3) || return 0
  gauge_apt_install "Instalando OpenJDK ${CHOICE}..." "openjdk-${CHOICE}-jdk"
  java -version || true
}

install_node(){
  local CHOICE
  CHOICE=$(whiptail --title "Node.js" --menu "Escolha a versão:" 15 55 6 \
    "18" "LTS (legado)" \
    "20" "LTS (popular)" \
    "22" "LTS atual" \
    3>&1 1>&2 2>&3) || return 0

  gauge_begin "Instalando Node.js ${CHOICE}..."
  gauge_update 10 "Adicionando NodeSource..."
  curl -fsSL "https://deb.nodesource.com/setup_${CHOICE}.x" | bash - >/dev/null 2>&1
  gauge_update 40 "Instalando nodejs..."
  apt-get install -y nodejs >/dev/null 2>&1 || true
  gauge_update 65 "Instalando pnpm / yarn..."
  cmd_exists pnpm || npm i -g pnpm >/dev/null 2>&1 || true
  cmd_exists yarn || npm i -g yarn >/dev/null 2>&1 || true
  gauge_update 85 "CLIs úteis (TS, Nest, etc.)..."
  npm i -g @quasar/cli @vue/cli typescript ts-node @nestjs/cli http-server nodemon eslint prettier >/dev/null 2>&1 || true
  gauge_end

  node -v && npm -v || true
}

install_go(){
  local DEFAULT="1.23.1"
  local VERSION
  VERSION=$(whiptail --inputbox "Versão do Go (ex: 1.23.1):" 10 60 "$DEFAULT" 3>&1 1>&2 2>&3) || return 0
  [[ -z "$VERSION" ]] && VERSION="$DEFAULT"

  local arch goarch
  arch=$(dpkg --print-architecture)
  case "$arch" in amd64) goarch="amd64";; arm64) goarch="arm64";; *) err "Arquitetura não suportada: $arch"; return 1;; esac

  gauge_begin "Instalando Go $VERSION..."
  gauge_update 10 "Baixando tarball..."
  cd /tmp
  curl -fsSLO "https://go.dev/dl/go${VERSION}.linux-${goarch}.tar.gz"
  gauge_update 50 "Extraindo em /usr/local..."
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "go${VERSION}.linux-${goarch}.tar.gz"
  gauge_update 80 "Ajustando PATH/GOPATH..."
  append_once 'export PATH=$PATH:/usr/local/go/bin' /etc/profile
  append_once "export GOPATH=/home/${MAIN_USER}/go" "/home/${MAIN_USER}/.profile"
  append_once "export PATH=\$PATH:\$GOPATH/bin" "/home/${MAIN_USER}/.profile"
  chown -R "${MAIN_USER}:${MAIN_USER}" "/home/${MAIN_USER}/go" || true
  gauge_end
  go version || true
}

install_python(){
  gauge_apt_install "Instalando Python + ferramentas..." python3 python3-pip python3-venv python3-dev
  append_once 'alias venv="python3 -m venv .venv && . .venv/bin/activate"' "/home/${MAIN_USER}/.bashrc"
  python3 --version && pip3 --version || true
}

install_postgres(){
  local CHOICE
  CHOICE=$(whiptail --title "PostgreSQL" --menu "Escolha a versão:" 15 55 6 \
    "14" "" "15" "" "16" "recomendada" "17" "" 3>&1 1>&2 2>&3) || return 0

  gauge_begin "Instalando PostgreSQL ${CHOICE}..."
  gauge_update 10 "Adicionando repositório PGDG..."
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgres.gpg
  echo "deb http://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo $VERSION_CODENAME)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
  gauge_update 40 "apt-get update..."
  apt-get update -y >/dev/null 2>&1 || true
  gauge_update 75 "Instalando servidor e cliente..."
  apt-get install -y "postgresql-${CHOICE}" "postgresql-client-${CHOICE}" postgresql-contrib >/dev/null 2>&1 || true
  gauge_update 95 "Tentando iniciar serviço (sem systemd no WSL pode falhar)..."
  (systemctl enable --now postgresql || true) 2>/dev/null || true
  gauge_end
  psql --version || true
}

install_nginx_certbot(){
  gauge_begin "Instalando Nginx + Certbot..."
  gauge_update 25 "Instalando pacotes..."
  apt-get install -y nginx certbot python3-certbot-nginx >/dev/null 2>&1 || true
  gauge_update 70 "Hardening básico..."
  if ! grep -q "server_tokens off" /etc/nginx/nginx.conf; then
    sed -i 's|http {|http {\n    server_tokens off;|' /etc/nginx/nginx.conf
  fi
  gauge_update 90 "Testando/recarregando Nginx..."
  nginx -t >/dev/null 2>&1 && (systemctl reload nginx || true) 2>/dev/null || true
  gauge_end
}

install_redis(){
  gauge_apt_install "Instalando Redis..." redis
  (systemctl enable --now redis-server || true) 2>/dev/null || true
  redis-cli ping || true
}

install_php(){
  gauge_begin "Instalando PHP 8.2 + extensões + Composer..."
  gauge_update 20 "Instalando PHP e extensões..."
  apt-get install -y php php-cli php-fpm php-common php-curl php-xml php-mbstring php-zip php-gd php-intl php-pgsql php-mysql >/dev/null 2>&1 || true
  gauge_update 70 "Instalando Composer..."
  if ! cmd_exists composer; then
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" >/dev/null 2>&1 || true
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer >/dev/null 2>&1 || true
    rm -f composer-setup.php
  fi
  gauge_end
  php -v && composer --version || true
}

install_docker(){
  if ! whiptail --yesno "Você está no WSL2.\n\nRecomenda-se usar o Docker Desktop para Windows com integração WSL.\n\nAinda assim deseja instalar Docker Engine dentro do WSL?" 13 60; then
    warn "Pulando Docker Engine. Use Docker Desktop com integração WSL."
    return 0
  fi
  gauge_begin "Instalando Docker Engine..."
  gauge_update 15 "Configurando chave/repo Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
  gauge_update 40 "apt-get update..."
  apt-get update -y >/dev/null 2>&1 || true
  gauge_update 75 "Instalando docker-ce e plugins..."
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1 || true
  gauge_update 90 "Adicionando ${MAIN_USER} ao grupo docker..."
  usermod -aG docker "$MAIN_USER" || true
  (systemctl enable --now docker || true) 2>/dev/null || true
  gauge_end
  docker --version || true
  log "Docker instalado. Saia e entre novamente no shell (ou execute 'newgrp docker') para aplicar o grupo docker."
}

install_zsh(){
  gauge_begin "Instalando Zsh + oh-my-zsh..."
  gauge_update 40 "Instalando zsh..."
  apt-get install -y zsh >/dev/null 2>&1 || true
  gauge_update 70 "Instalando oh-my-zsh (não interativo)..."
  chsh -s /usr/bin/zsh "$MAIN_USER" || true
  sudo -u "$MAIN_USER" sh -c 'export RUNZSH=no; export CHSH=no; sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || true' >/dev/null 2>&1 || true
  gauge_end
}

qol_tools_basic(){
  gauge_apt_install "Instalando QoL básico..." bash-completion fzf ripgrep tmux htop vim net-tools rsync tree
  sudo -u "$MAIN_USER" git config --global init.defaultBranch main || true
  sudo -u "$MAIN_USER" git config --global pull.rebase false || true
  append_once "if [ -f /etc/bash_completion ]; then . /etc/bash_completion; fi" "/etc/bash.bashrc"
}

# =========================
# Módulos extras - INSTALAR
# =========================
install_network_diag(){ gauge_apt_install "Instalando ferramentas de rede/diagnóstico..." iproute2 dnsutils traceroute nmap tcpdump; }

install_qol_extended(){
  gauge_begin "Instalando QoL estendido..."
  gauge_update 30 "Instalando pacotes (neofetch, btop, bat, eza, neovim, micro)..."
  apt-get install -y neofetch btop bat eza neovim micro >/dev/null 2>&1 || true
  gauge_update 80 "Adicionando aliases..."
  append_once 'alias ll="ls -la"' "/home/${MAIN_USER}/.bashrc"
  append_once 'alias cat="batcat -pp"' "/home/${MAIN_USER}/.bashrc"
  append_once 'alias ls="eza --icons"' "/home/${MAIN_USER}/.bashrc"
  gauge_end
}

install_cli_productivity(){
  gauge_begin "Instalando ferramentas CLI (jq, yq, httpie, gh)..."
  gauge_update 20 "Instalando jq e httpie..."
  apt-get install -y jq httpie >/dev/null 2>&1 || true
  gauge_update 45 "Instalando yq..."
  if ! apt-get install -y yq >/dev/null 2>&1; then
    arch=$(dpkg --print-architecture); case "$arch" in amd64) yarch="amd64";; arm64) yarch="arm64";; *) yarch="amd64";; esac
    curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${yarch}" -o /usr/local/bin/yq
    chmod +x /usr/local/bin/yq
  fi
  gauge_update 75 "Instalando GitHub CLI (gh)..."
  if ! cmd_exists gh; then
    install -d /usr/share/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg status=none
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y gh >/dev/null 2>&1 || true
  fi
  gauge_end
}

install_devops_tools(){ gauge_apt_install "Instalando ferramentas de build/DevOps..." make cmake ninja-build podman podman-compose; }

install_k8s_tools(){
  gauge_begin "Instalando ferramentas Kubernetes..."
  gauge_update 15 "Instalando kubectl (repo oficial)..."
  if ! cmd_exists kubectl; then
    install -d /etc/apt/keyrings
    curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
    apt-get update -y >/dev/null 2>&1 || true
    if ! apt-get install -y kubectl >/dev/null 2>&1; then
      warn "Falhou via APT; instalando kubectl binário..."
      arch=$(dpkg --print-architecture); case "$arch" in amd64) karch="amd64";; arm64) karch="arm64";; *) karch="amd64";; esac
      LATEST_KUBECTL="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
      curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${LATEST_KUBECTL}/bin/linux/${karch}/kubectl"
      chmod +x /usr/local/bin/kubectl
    fi
  fi
  gauge_update 55 "Instalando Helm..."
  cmd_exists helm || (curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1)
  gauge_update 85 "Instalando k9s..."
  if ! cmd_exists k9s; then
    cd /tmp
    ver="$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | jq -r .tag_name)"
    arch=$(dpkg --print-architecture); case "$arch" in amd64) karch="x86_64";; arm64) karch="arm64";; *) karch="x86_64";; esac
    curl -fsSLO "https://github.com/derailed/k9s/releases/download/${ver}/k9s_Linux_${karch}.tar.gz"
    tar xzf "k9s_Linux_${karch}.tar.gz"
    install -m 0755 k9s /usr/local/bin/k9s
  fi
  gauge_end
}

install_rust(){
  gauge_begin "Instalando Rust (rustup)..."
  gauge_update 40 "Baixando/instalando rustup..."
  if ! cmd_exists rustup; then
    sudo -u "$MAIN_USER" sh -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y' >/dev/null 2>&1
    append_once 'source $HOME/.cargo/env' "/home/${MAIN_USER}/.bashrc"
  fi
  gauge_update 80 "Adicionando rustfmt e clippy..."
  sudo -u "$MAIN_USER" bash -lc 'rustup component add rustfmt clippy || true' >/dev/null 2>&1
  gauge_end
}

install_java_build(){ gauge_apt_install "Instalando Maven + Gradle..." maven gradle; }
install_db_clients(){ gauge_apt_install "Instalando clientes de banco..." postgresql-client mysql-client sqlite3 redis-tools; }
install_backup_tools(){ gauge_apt_install "Instalando ferramentas de backup..." rclone restic duplicity borgbackup; }
install_style_fun(){ gauge_apt_install "Instalando pacotes divertidos..." lolcat figlet cowsay; }

install_security_tools(){
  gauge_begin "Instalando ferramentas de segurança/SSH..."
  gauge_update 40 "Instalando pacotes..."
  apt-get install -y openssh-client keychain gnupg-agent gpg sshpass >/dev/null 2>&1 || true
  if ! is_wsl; then
    apt-get install -y ufw fail2ban >/dev/null 2>&1 || true
  else
    warn "WSL detectado: UFW/Fail2ban não instalados."
  fi
  gauge_end
}

# =========================
# Módulos - REMOVER (UNINSTALL)
# =========================
remove_java(){
  local CHOICE
  CHOICE=$(whiptail --title "Remover Java" --menu "Qual versão remover?" 12 50 3 \
    "17" "OpenJDK 17" \
    "21" "OpenJDK 21" \
    "ALL" "Todas (17 e 21)" \
    3>&1 1>&2 2>&3) || return 0
  case "$CHOICE" in
    17) gauge_apt_purge "Removendo OpenJDK 17..." openjdk-17-jdk ;;
    21) gauge_apt_purge "Removendo OpenJDK 21..." openjdk-21-jdk ;;
    ALL) gauge_apt_purge "Removendo OpenJDK 17/21..." openjdk-17-jdk openjdk-21-jdk ;;
  esac
}

remove_node(){
  gauge_apt_purge "Removendo Node.js + npm..." nodejs
  # mantém globais do npm caso existam, para evitar remover coisas do usuário
}

remove_go(){
  gauge_begin "Removendo Go..."
  gauge_update 30 "Apagando /usr/local/go..."
  rm -rf /usr/local/go || true
  gauge_update 70 "Opcional: remover GOPATH do usuário..."
  if whiptail --yesno "Deseja remover GOPATH em /home/${MAIN_USER}/go ?" 8 60; then
    rm -rf "/home/${MAIN_USER}/go" || true
  fi
  gauge_end
}

remove_python(){ gauge_apt_purge "Removendo Python toolchain..." python3-venv python3-dev python3-pip python3 || true; }

remove_postgres(){
  local CHOICE
  CHOICE=$(whiptail --title "Remover PostgreSQL" --menu "Qual versão remover?" 13 55 6 \
    "14" "" "15" "" "16" "" "17" "" "ALL" "Todas" \
    3>&1 1>&2 2>&3) || return 0
  case "$CHOICE" in
    14|15|16|17) gauge_apt_purge "Removendo PostgreSQL $CHOICE..." "postgresql-${CHOICE}" "postgresql-client-${CHOICE}" postgresql-contrib ;;
    ALL) gauge_apt_purge "Removendo PostgreSQL (todas)..." postgresql postgresql-client postgresql-contrib ;;
  esac
  if whiptail --yesno "Apagar dados do PostgreSQL em /var/lib/postgresql ? (Irreversível)" 9 65; then
    rm -rf /var/lib/postgresql || true
  fi
  rm -f /etc/apt/sources.list.d/pgdg.list /etc/apt/trusted.gpg.d/postgres.gpg || true
}

remove_nginx_certbot(){ gauge_apt_purge "Removendo Nginx + Certbot..." nginx certbot python3-certbot-nginx || true; }

remove_redis(){ gauge_apt_purge "Removendo Redis..." redis redis-server || true; }

remove_php(){
  gauge_apt_purge "Removendo PHP + extensões..." php php-cli php-fpm php-common php-curl php-xml php-mbstring php-zip php-gd php-intl php-pgsql php-mysql || true
  rm -f /usr/local/bin/composer || true
}

remove_docker(){
  if ! whiptail --yesno "Remover Docker Engine (pacotes)?\nVolumes/imagens podem ficar.\nDeseja continuar?" 10 60; then return 0; fi
  gauge_apt_purge "Removendo Docker Engine..." docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
  rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg || true
  if whiptail --yesno "Apagar /var/lib/docker (imagens/volumes) ? (Irreversível)" 9 65; then
    rm -rf /var/lib/docker || true
  fi
}

remove_zsh(){
  gauge_begin "Removendo Zsh + oh-my-zsh..."
  gauge_update 20 "Trocando shell padrão para bash..."
  chsh -s /bin/bash "$MAIN_USER" || true
  gauge_update 60 "Removendo zsh..."
  apt-get purge -y zsh >/dev/null 2>&1 || true
  gauge_update 85 "Removendo oh-my-zsh do usuário..."
  sudo -u "$MAIN_USER" rm -rf "/home/${MAIN_USER}/.oh-my-zsh" "/home/${MAIN_USER}/.zshrc" || true
  gauge_end
}

remove_qol_basic(){ gauge_apt_purge "Removendo QoL básico..." bash-completion fzf ripgrep tmux htop vim net-tools rsync tree || true; }

remove_network_diag(){ gauge_apt_purge "Removendo rede/diag..." iproute2 dnsutils traceroute nmap tcpdump || true; }

remove_qol_extended(){
  gauge_begin "Removendo QoL estendido..."
  gauge_update 30 "Removendo pacotes..."
  apt-get purge -y neofetch btop bat eza neovim micro >/dev/null 2>&1 || true
  gauge_update 70 "Limpando aliases (opcional, manterei por segurança)..."
  # Se quiser remover: edite manualmente ~/.bashrc
  gauge_end
}

remove_cli_productivity(){
  gauge_begin "Removendo CLI produtividade..."
  gauge_update 20 "Removendo jq, httpie, yq..."
  apt-get purge -y jq httpie yq >/dev/null 2>&1 || true
  gauge_update 60 "Removendo gh..."
  apt-get purge -y gh >/dev/null 2>&1 || true
  rm -f /etc/apt/sources.list.d/github-cli.list /usr/share/keyrings/githubcli-archive-keyring.gpg || true
  gauge_end
}

remove_devops_tools(){ gauge_apt_purge "Removendo DevOps..." make cmake ninja-build podman podman-compose || true; }

remove_k8s_tools(){
  gauge_begin "Removendo Kubernetes tools..."
  gauge_update 25 "Removendo kubectl..."
  apt-get purge -y kubectl >/dev/null 2>&1 || true
  rm -f /usr/local/bin/kubectl /etc/apt/sources.list.d/kubernetes.list /etc/apt/keyrings/kubernetes-archive-keyring.gpg || true
  gauge_update 65 "Removendo Helm..."
  apt-get purge -y helm >/dev/null 2>&1 || true
  rm -f /usr/local/bin/helm || true
  gauge_update 85 "Removendo k9s..."
  apt-get purge -y k9s >/dev/null 2>&1 || true
  rm -f /usr/local/bin/k9s || true
  gauge_end
}

remove_rust(){
  gauge_begin "Removendo Rust..."
  gauge_update 40 "Executando rustup self uninstall..."
  if cmd_exists rustup; then
    sudo -u "$MAIN_USER" bash -lc 'yes | rustup self uninstall' >/dev/null 2>&1 || true
  fi
  gauge_update 80 "Removendo cache/config ~/.cargo e ~/.rustup..."
  sudo -u "$MAIN_USER" rm -rf "/home/${MAIN_USER}/.cargo" "/home/${MAIN_USER}/.rustup" || true
  gauge_end
}

remove_db_clients(){ gauge_apt_purge "Removendo clientes de DB..." postgresql-client mysql-client sqlite3 redis-tools || true; }
remove_backup_tools(){ gauge_apt_purge "Removendo ferramentas de backup..." rclone restic duplicity borgbackup || true; }
remove_style_fun(){ gauge_apt_purge "Removendo pacotes divertidos..." lolcat figlet cowsay || true; }

remove_security_tools(){
  gauge_begin "Removendo ferramentas de segurança..."
  gauge_update 40 "Removendo pacotes..."
  apt-get purge -y openssh-client keychain gnupg-agent gpg sshpass >/dev/null 2>&1 || true
  if ! is_wsl; then
    apt-get purge -y ufw fail2ban >/dev/null 2>&1 || true
  fi
  gauge_update 85 "Limpando..."
  apt-get -y autoremove >/dev/null 2>&1 || true
  apt-get -y clean >/dev/null 2>&1 || true
  gauge_end
}

# =========================
# PRESETS (instalação)
# =========================
preset_dev_web(){ install_node; install_php; install_postgres; install_redis; qol_tools_basic; install_qol_extended; install_cli_productivity; install_network_diag; install_db_clients; }
preset_dev_go(){ install_go; install_postgres; install_redis; qol_tools_basic; install_qol_extended; install_cli_productivity; install_network_diag; install_db_clients; }
preset_dev_py(){ install_python; install_postgres; install_redis; qol_tools_basic; install_qol_extended; install_cli_productivity; install_network_diag; install_db_clients; }
preset_sysadmin(){ install_nginx_certbot; install_docker; install_devops_tools; qol_tools_basic; install_network_diag; install_security_tools; install_backup_tools; install_cli_productivity; }
preset_full(){
  install_java; install_java_build; install_node; install_go; install_python; install_postgres; install_nginx_certbot; install_redis; install_php; install_docker; install_zsh;
  qol_tools_basic; install_qol_extended; install_network_diag; install_cli_productivity; install_devops_tools; install_k8s_tools; install_rust; install_db_clients; install_backup_tools; install_style_fun; install_security_tools;
}

# =========================
# Menus
# =========================
presets_menu(){
  local CHOICE
  CHOICE=$(whiptail --title "Presets" --menu "Escolha um preset para instalar:" 18 60 7 \
    "1" "Dev Web (Node + PHP + PG + Redis + QoL)" \
    "2" "Dev Go (Go + PG + Redis + QoL)" \
    "3" "Dev Python (Python + PG + Redis + QoL)" \
    "4" "SysAdmin (Nginx/Certbot + Docker + QoL + Segurança)" \
    "5" "Full (quase tudo)" \
    "0" "Voltar" \
    3>&1 1>&2 2>&3) || return 0
  case "$CHOICE" in
    1) preset_dev_web ;;
    2) preset_dev_go ;;
    3) preset_dev_py ;;
    4) preset_sysadmin ;;
    5) preset_full ;;
    0) return 0 ;;
  esac
  whiptail --title "Preset concluído" --msgbox "Instalação do preset finalizada!\nLog: $LOG_FILE" 10 60
}

manual_install_menu(){
  while true; do
    local CHOICES
    CHOICES=$(whiptail --title "Instalação manual (Checklist)" --checklist \
"Selecione o que deseja instalar (ESPAÇO marca/desmarca, TAB navega, ENTER confirma):" 24 85 16 \
      "JAVA"        "OpenJDK (17/21)" OFF \
      "JAVA_BUILD"  "Maven + Gradle" OFF \
      "NODE"        "Node.js (18/20/22) + pnpm/yarn/CLIs" OFF \
      "GO"          "Go (versão informada)" OFF \
      "PYTHON"      "Python3 + pip + venv" OFF \
      "POSTGRES"    "PostgreSQL (14/15/16/17) + client" OFF \
      "NGINX"       "Nginx + Certbot" OFF \
      "REDIS"       "Redis" OFF \
      "PHP"         "PHP 8.2 + extensões + Composer" OFF \
      "DOCKER"      "Docker Engine (ou Docker Desktop)" OFF \
      "ZSH"         "Zsh + oh-my-zsh" OFF \
      "QOL_BASIC"   "QoL básico (fzf, ripgrep, tmux, etc.)" ON \
      "QOL_EXT"     "QoL estendido (bat, eza, neovim, micro)" ON \
      "NETWORK"     "Rede/diag (iproute2, nmap, tcpdump...)" ON \
      "CLI_PROD"    "Produtividade CLI (jq, yq, httpie, gh)" ON \
      "DEVOPS"      "Build/DevOps (make, cmake, ninja, podman)" OFF \
      "K8S"         "kubectl, helm, k9s" OFF \
      "RUST"        "rustup + rustfmt + clippy" OFF \
      "DB_CLIENTS"  "psql, mysql-client, sqlite3, redis-tools" ON \
      "BACKUP"      "rclone, restic, duplicity, borg" OFF \
      "FUN"         "lolcat, figlet, cowsay" OFF \
      "SECURITY"    "ssh/gnupg/keychain (+ ufw/fail2ban fora do WSL)" OFF \
      3>&1 1>&2 2>&3) || return 0

    read -r -a SELECTED <<< "$(sed 's/"//g' <<< "$CHOICES")"
    for item in "${SELECTED[@]}"; do
      case "$item" in
        JAVA)        install_java ;;
        JAVA_BUILD)  install_java_build ;;
        NODE)        install_node ;;
        GO)          install_go ;;
        PYTHON)      install_python ;;
        POSTGRES)    install_postgres ;;
        NGINX)       install_nginx_certbot ;;
        REDIS)       install_redis ;;
        PHP)         install_php ;;
        DOCKER)      install_docker ;;
        ZSH)         install_zsh ;;
        QOL_BASIC)   qol_tools_basic ;;
        QOL_EXT)     install_qol_extended ;;
        NETWORK)     install_network_diag ;;
        CLI_PROD)    install_cli_productivity ;;
        DEVOPS)      install_devops_tools ;;
        K8S)         install_k8s_tools ;;
        RUST)        install_rust ;;
        DB_CLIENTS)  install_db_clients ;;
        BACKUP)      install_backup_tools ;;
        FUN)         install_style_fun ;;
        SECURITY)    install_security_tools ;;
      esac
    done

    whiptail --title "Concluído" --msgbox "Instalações selecionadas finalizadas.\nLog: $LOG_FILE" 10 60
    if ! whiptail --yesno "Deseja voltar ao checklist e instalar mais itens?" 8 55; then break; fi
  done
}

manual_remove_menu(){
  while true; do
    local CHOICES
    CHOICES=$(whiptail --title "Remoção (Checklist)" --checklist \
"Selecione o que deseja REMOVER (ESPAÇO marca/desmarca, TAB navega, ENTER confirma):" 24 90 16 \
      "JAVA"        "OpenJDK (17/21)" OFF \
      "JAVA_BUILD"  "Maven + Gradle" OFF \
      "NODE"        "Node.js" OFF \
      "GO"          "Go (/usr/local/go e opcional GOPATH)" OFF \
      "PYTHON"      "Python toolchain" OFF \
      "POSTGRES"    "PostgreSQL (14/15/16/17) [pergunta dados]" OFF \
      "NGINX"       "Nginx + Certbot" OFF \
      "REDIS"       "Redis" OFF \
      "PHP"         "PHP + extensões + Composer" OFF \
      "DOCKER"      "Docker Engine [pergunta /var/lib/docker]" OFF \
      "ZSH"         "Zsh + oh-my-zsh (volta shell p/ bash)" OFF \
      "QOL_BASIC"   "QoL básico (fzf, ripgrep, tmux, etc.)" OFF \
      "QOL_EXT"     "QoL estendido (bat, eza, neovim, micro)" OFF \
      "NETWORK"     "Rede/diagnóstico (nmap, tcpdump...)" OFF \
      "CLI_PROD"    "Produtividade CLI (jq, yq, httpie, gh)" OFF \
      "DEVOPS"      "Build/DevOps (make, cmake, ninja, podman)" OFF \
      "K8S"         "kubectl, helm, k9s" OFF \
      "RUST"        "rustup + ~/.cargo ~/.rustup" OFF \
      "DB_CLIENTS"  "psql, mysql-client, sqlite3, redis-tools" OFF \
      "BACKUP"      "rclone, restic, duplicity, borg" OFF \
      "FUN"         "lolcat, figlet, cowsay" OFF \
      "SECURITY"    "ssh/gnupg/keychain (+ ufw/fail2ban fora do WSL)" OFF \
      3>&1 1>&2 2>&3) || return 0

    read -r -a SELECTED <<< "$(sed 's/"//g' <<< "$CHOICES")"
    for item in "${SELECTED[@]}"; do
      case "$item" in
        JAVA)        remove_java ;;
        JAVA_BUILD)  gauge_apt_purge "Removendo Maven + Gradle..." maven gradle ;;
        NODE)        remove_node ;;
        GO)          remove_go ;;
        PYTHON)      remove_python ;;
        POSTGRES)    remove_postgres ;;
        NGINX)       remove_nginx_certbot ;;
        REDIS)       remove_redis ;;
        PHP)         remove_php ;;
        DOCKER)      remove_docker ;;
        ZSH)         remove_zsh ;;
        QOL_BASIC)   remove_qol_basic ;;
        QOL_EXT)     remove_qol_extended ;;
        NETWORK)     remove_network_diag ;;
        CLI_PROD)    remove_cli_productivity ;;
        DEVOPS)      remove_devops_tools ;;
        K8S)         remove_k8s_tools ;;
        RUST)        remove_rust ;;
        DB_CLIENTS)  remove_db_clients ;;
        BACKUP)      remove_backup_tools ;;
        FUN)         remove_style_fun ;;
        SECURITY)    remove_security_tools ;;
      esac
    done

    whiptail --title "Concluído" --msgbox "Remoções selecionadas finalizadas.\nLog: $LOG_FILE" 10 60
    if ! whiptail --yesno "Deseja voltar ao checklist e REMOVER mais itens?" 8 64; then break; fi
  done
}

main_menu(){
  while true; do
    local CHOICE
    CHOICE=$(whiptail --title "Instalação WSL (Debian/Ubuntu) - v2.3" --menu \
"Escolha uma opção:" 18 72 7 \
      "1" "Presets (Dev Web, Dev Go, Dev Python, SysAdmin, Full) [INSTALAR]" \
      "2" "Checklist Manual [INSTALAR]" \
      "3" "Checklist Manual [REMOVER]" \
      "0" "Sair" \
      3>&1 1>&2 2>&3) || { log "Saindo."; exit 0; }
    case "$CHOICE" in
      1) presets_menu ;;
      2) manual_install_menu ;;
      3) manual_remove_menu ;;
      0) break ;;
    esac
  done
}

# =========================
# Execução
# =========================
need_root
pre_setup
set_locale_tz
suggest_enable_systemd_wsl
main_menu
log "Tudo pronto! (Log: $LOG_FILE)"
