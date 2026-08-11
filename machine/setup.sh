#!/bin/bash

# =============================================================================
# POST-FORMAT SETUP — multi-distro (Arch, Ubuntu/Debian, Fedora)
# =============================================================================

set -e

if [ "$EUID" -eq 0 ]; then
  echo "Execute como usuario comum (nao root)."
  exit 1
fi

# --- Origem dos assets (clonado x streamed) ---
# Clonado: perfis.sh, perfis/*.perfil e os assets do firefox/vscode estão ao
# lado deste script. Streamed (`bash <(curl ...)`): BASH_SOURCE é um FIFO
# (/dev/fd/NN) e não existe diretório irmão — sem isto o source abaixo morre
# sob `set -e`, o FIFO fecha e o curl da chamada reporta "(23) Failure writing
# output to destination", que esconde a causa real.
#
# O tarball do ref traz TODOS os assets de uma vez (~28K), então não há lista
# de arquivos aqui para divergir do que o repo realmente tem (um perfil novo
# entra sozinho). BOOTSTRAP_REF deve casar com o ref do one-liner.
BOOTSTRAP_REF="${BOOTSTRAP_REF:-main}"
DOTFILES_RAW="https://raw.githubusercontent.com/StayneDev/bootstrap-workstation/$BOOTSTRAP_REF/machine"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

if [ ! -f "$SCRIPT_DIR/perfis.sh" ]; then
  echo "[INFO] Modo streamed — baixando assets do ref '$BOOTSTRAP_REF'"
  BOOTSTRAP_TMP="$(mktemp -d)"
  trap 'rm -rf "$BOOTSTRAP_TMP"' EXIT
  curl -fsSL "https://codeload.github.com/StayneDev/bootstrap-workstation/tar.gz/refs/heads/$BOOTSTRAP_REF" \
    | tar xz -C "$BOOTSTRAP_TMP" --strip-components=1 \
    || { echo "[ERRO] Falha ao baixar os assets do ref '$BOOTSTRAP_REF'." >&2; exit 1; }
  SCRIPT_DIR="$BOOTSTRAP_TMP/machine"
  [ -f "$SCRIPT_DIR/perfis.sh" ] \
    || { echo "[ERRO] perfis.sh ausente no tarball de '$BOOTSTRAP_REF'." >&2; exit 1; }
fi

# --- Perfis, respostas e conferência (#21, #22, #24) ---
source "$SCRIPT_DIR/perfis.sh"

# --- Deteccao de distro ---
# DISTRO escolhe o gerenciador de pacotes; DISTRO_ID diz QUAL distro e. Os dois
# sao necessarios porque Debian e Ubuntu compartilham o apt mas nao os
# repositorios — tratar Ubuntu como Debian mistura as duas arvores (ver o
# guarda em install_base).
detect_distro() {
  if command -v pacman &>/dev/null; then DISTRO="arch"
  elif command -v apt-get &>/dev/null; then DISTRO="debian"
  elif command -v dnf &>/dev/null; then DISTRO="fedora"
  else echo "Distro nao suportada." && exit 1
  fi
  DISTRO_ID="$( . /etc/os-release 2>/dev/null && echo "$ID" )"
  echo "[INFO] Distro detectada: $DISTRO (${DISTRO_ID:-desconhecida})"
}

# =============================================================================
# DEPENDENCIAS DO MOTOR — as que o orquestrador invoca e ninguem instalava
# =============================================================================
# Achado no aceite #26, cruzando o que os scripts do motor chamam contra o que
# este script instalava:
#   python3    — a trava-de-forma E python. Sem ela o portao principal degrada em
#                silencio ("mecanismo falhou — escrita liberada SEM validacao").
#                Funcionava por sorte da distro, nao por desenho.
#   gh         — o fecho-de-sprint recusa sem ele, e o PR virou obrigatorio no
#                ADR-20260802. Sem gh, a passagem develop→main e inexecutavel.
#   shellcheck — o lint da maquinaria NUNCA foi avaliado em maquina nenhuma.
#   jq         — leitura de JSON.
#
# UMA POR VEZ, e tolerante: `gh` nao existe nos repos do Debian puro, e um
# `apt install` com pacote ausente aborta sob `set -e` — o run inteiro morreria
# por causa de uma ferramenta acessoria. Falta se ANUNCIA (U2), nao mata.
instalar_dependencias_do_motor() {
  echo -e "\n[provisionar] Dependencias do motor (python3, gh, shellcheck, jq)..."
  local faltou=()
  local p
  for p in python3 gh shellcheck jq; do
    local pkg="$p"
    case "$DISTRO:$p" in
      arch:gh)         pkg="github-cli" ;;
      fedora:shellcheck) pkg="ShellCheck" ;;
    esac
    if command -v "$p" &>/dev/null; then
      echo "  [ok] $p ja presente."
      continue
    fi
    case $DISTRO in
      arch)   sudo pacman -S --noconfirm --needed "$pkg" ;;
      debian) sudo apt install -y "$pkg" ;;
      fedora) sudo dnf install -y "$pkg" ;;
    esac 2>/dev/null
    command -v "$p" &>/dev/null && echo "  [OK] $p instalado." || faltou+=("$p")
  done
  if [ ${#faltou[@]} -gt 0 ]; then
    echo "  [AVISO] nao instalei: ${faltou[*]}"
    echo "          o motor funciona degradado — veja o que cada uma custa no"
    echo "          cabecalho de instalar_dependencias_do_motor neste arquivo."
  fi
}

# =============================================================================
# 1. PACOTES BASE
# =============================================================================
install_base() {
  echo -e "\n[provisionar] Instalando pacotes base..."

  case $DISTRO in
    arch)
      sudo pacman -Syu --noconfirm
      sudo pacman -S --noconfirm --needed \
        git curl zsh zsh-completions \
        neofetch cmatrix \
        tailscale \
        ttf-liberation ttf-nerd-fonts-symbols-common noto-fonts noto-fonts-emoji \
        power-profiles-daemon wireplumber \
        flatpak xclip wl-clipboard
      # yay
      if ! command -v yay &>/dev/null; then
        sudo pacman -S --noconfirm --needed base-devel
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        cd /tmp/yay && makepkg -si --noconfirm && cd - && rm -rf /tmp/yay
      fi
      # VSCode
      yay -S --noconfirm visual-studio-code-bin
      ;;
    debian)
      # Garante repos online — remove cdrom e adiciona bookworm se ausente.
      # SO no Debian de verdade: no Ubuntu o /etc/apt/sources.list e vazio de
      # proposito (os repos vivem em sources.list.d/ubuntu.sources, deb822), o
      # grep abaixo nao acha nada e isto sobrescrevia o arquivo com bookworm
      # numa maquina noble — misturando as duas arvores. Falha alto por falta de
      # chave GPG; com a chave presente, instalaria pacote Debian sobre Ubuntu.
      if [ "$DISTRO_ID" = "debian" ]; then
        sudo sed -i '/^deb cdrom:/d' /etc/apt/sources.list
        if ! grep -q "deb.debian.org" /etc/apt/sources.list; then
          cat <<'EOF' | sudo tee /etc/apt/sources.list > /dev/null
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF
          echo "  [OK] sources.list atualizado para repositorios online."
        fi
      fi
      sudo apt update && sudo apt upgrade -y
      # xclip/wl-clipboard: a fase autenticar imprime a chave SSH e promete
      # clipboard. Sem eles a promessa e falsa numa maquina virgem.
      # As quatro que o MOTOR precisa e que ninguem instalava (aceite #26):
      #   python3    — a trava-de-forma E python. Sem ela o portao principal
      #                degrada em silencio ("mecanismo falhou, escrita liberada").
      #                Funcionava por sorte da distro, nao por desenho.
      #   gh         — o fecho-de-sprint recusa sem ele; o PR obrigatorio pelo
      #                ADR-20260802 ficava inexecutavel em maquina nova.
      #   shellcheck — o lint da maquinaria NUNCA foi avaliado, em maquina
      #                nenhuma. Ponto cego permanente ate agora.
      #   jq         — leitura de JSON nos scripts.
      sudo apt install -y git curl zsh neofetch cmatrix flatpak xclip wl-clipboard
      instalar_dependencias_do_motor
      # VSCode — usa curl (wget pode nao estar disponivel)
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg > /dev/null
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
      VSCODE_UPDATE=$(sudo apt update 2>&1 || true)
      if echo "$VSCODE_UPDATE" | grep -q "NO_PUBKEY"; then
        echo "  [AVISO] Chave GPG do VSCode invalida — removendo repo e pulando instalacao."
        sudo rm -f /etc/apt/sources.list.d/vscode.list /usr/share/keyrings/microsoft.gpg
        sudo apt update
      else
        sudo apt install -y code
      fi
      # Tailscale
      curl -fsSL https://tailscale.com/install.sh | sh
      ;;
    fedora)
      sudo dnf upgrade -y
      sudo dnf install -y git curl zsh neofetch cmatrix flatpak xclip wl-clipboard
      instalar_dependencias_do_motor
      # VSCode
      sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
      sudo tee /etc/yum.repos.d/vscode.repo > /dev/null <<EOF
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
      sudo dnf install -y code
      # Tailscale
      curl -fsSL https://tailscale.com/install.sh | sh
      ;;
  esac

  [ "$DISTRO" = "arch" ] && instalar_dependencias_do_motor

  # Flatpak remote
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

# =============================================================================
# 2. APPS VIA FLATPAK (universal)
# =============================================================================
# Discord e Steam são camada PESSOAL (perfis/pessoal.perfil) — separados na #21
# para o manifesto poder incluí-los ou não. install_flatpak_apps ficou como união.
install_discord() {
  echo -e "\n[provisionar] Instalando Discord (Flatpak)..."
  sudo flatpak install -y flathub com.discordapp.Discord
}
install_steam() {
  echo -e "\n[provisionar] Instalando Steam (Flatpak)..."
  sudo flatpak install -y flathub com.valvesoftware.Steam
}
install_flatpak_apps() {
  install_discord
  install_steam
  # Firefox nao e instalado aqui — distros ja incluem versao nativa.
  # Flatpak e usado apenas como fallback via --firefox quando nativo ausente.
}

# =============================================================================
# BRAVE ORIGIN (#23) — o Brave minimalista; gratuito no Linux
# =============================================================================
install_brave_origin() {
  echo -e "\n[provisionar] Instalando Brave Origin..."
  if command -v brave-origin &>/dev/null || command -v brave-browser-origin &>/dev/null; then
    echo "  [OK] Brave Origin já instalado."
    return 0
  fi
  case $DISTRO in
    debian)
      # laptop-updates.brave.com/latest/origin/<qualquer coisa> serve o
      # instalador WINDOWS — linux64, linux, amd64 e deb todos redirecionam para
      # BraveOriginSetup.exe com HTTP 200. Como o status é 200, o `curl -f` não
      # acusa nada e o apt recebia um PE32 chamado .deb ("Invalid archive
      # signature"). Não existe caminho Linux nesse canal.
      #
      # O caminho Linux é o repo apt oficial, onde brave-origin é pacote de
      # verdade (Depends: brave-keyring) e quem confere a assinatura é o apt —
      # em vez de nós conferirmos content-type na mão.
      local KEYRING=/usr/share/keyrings/brave-browser-archive-keyring.gpg
      local LISTA=/etc/apt/sources.list.d/brave-browser-release.list
      sudo curl -fsSL "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg" \
        -o "$KEYRING" || {
        echo "  [AVISO] falha ao baixar o keyring da Brave — repo nao configurado."
        echo "          Instale manualmente de https://brave.com/origin/ e re-execute."
        return 1
      }
      echo "deb [signed-by=$KEYRING arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" \
        | sudo tee "$LISTA" >/dev/null
      sudo apt update || { echo "  [AVISO] apt update falhou apos add do repo Brave."; return 1; }
      if sudo apt install -y brave-origin; then
        echo "  [OK] Brave Origin instalado do repo apt oficial."
        # a policy tem que existir ANTES do primeiro run: o Brave le
        # /etc/brave/policies/managed na inicializacao
        policy_bitwarden_brave
      else
        echo "  [AVISO] apt nao instalou brave-origin."
        echo "          Instale manualmente de https://brave.com/origin/ e re-execute."
        return 1
      fi
      ;;
    arch|fedora)
      echo "  [AVISO] Brave Origin: instalação automatizada só em Debian/Ubuntu por ora."
      echo "          Baixe em https://brave.com/origin/ — portabilidade não é prioridade (antessala, item 4)."
      return 1
      ;;
  esac
}

# =============================================================================
# CLONE DA INFRA (perfil infra) — posto de controle: clone, não merge
# =============================================================================
clone_infra() {
  echo -e "\n[fechar] Clonando bootstrap-infra (privado — exige auth)..."
  local INFRA_DIR="$HOME/Documentos/repos/bootstrap-infra"
  mkdir -p "$HOME/Documentos/repos"
  if [ ! -d "$INFRA_DIR/.git" ]; then
    git clone git@github.com:StayneDev/bootstrap-infra.git "$INFRA_DIR"
  fi
  echo "  [OK] posto de controle da infra pronto em $INFRA_DIR."
}

# =============================================================================
# 3. JDK 21
# =============================================================================
install_java() {
  echo -e "\n[provisionar] Instalando JDK 21..."
  case $DISTRO in
    arch)    sudo pacman -S --noconfirm --needed jdk21-openjdk ;;
    debian)
      # openjdk-21 requer backports no Bookworm. No Ubuntu ele esta no repo
      # padrao e "-t bookworm-backports" nem existe — por isso o alvo do apt so
      # entra quando os backports foram de fato adicionados.
      local APT_ALVO=()
      if [ "$DISTRO_ID" = "debian" ] && ! apt-cache show openjdk-21-jdk &>/dev/null; then
        BACKPORTS="deb http://deb.debian.org/debian bookworm-backports main contrib non-free"
        if ! grep -qF "bookworm-backports" /etc/apt/sources.list; then
          echo "$BACKPORTS" | sudo tee -a /etc/apt/sources.list > /dev/null
          sudo apt update
        fi
        APT_ALVO=(-t bookworm-backports)
      fi
      if apt-cache show openjdk-21-jdk &>/dev/null; then
        sudo apt install -y "${APT_ALVO[@]}" openjdk-21-jdk
      else
        echo "  [AVISO] openjdk-21 nao disponivel — instalando openjdk-17."
        sudo apt install -y openjdk-17-jdk
      fi
      ;;
    fedora)  sudo dnf install -y java-21-openjdk-devel ;;
  esac
}

# =============================================================================
# 4. NODE (nvm) + CLAUDE CODE
# =============================================================================
install_node_and_claude() {
  echo -e "\n[provisionar] Instalando nvm, Node e Claude Code..."

  export NVM_DIR="$HOME/.nvm"
  if [ ! -d "$NVM_DIR" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
  fi
  source "$NVM_DIR/nvm.sh"

  nvm install --lts
  nvm use --lts

  npm install -g @anthropic-ai/claude-code
}

# =============================================================================
# 5. TERMINAL — Zsh + Oh My Zsh + tema bira
# =============================================================================
setup_terminal() {
  echo -e "\n[configurar] Configurando terminal..."

  # Oh My Zsh
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi

  # Shell padrao para zsh.
  # `chsh` sem sudo passa por PAM e PEDE A SENHA — no meio do run, sem anuncio.
  # Em stdin nao-interativo ele falha com "PAM: Authentication failure", e o
  # [OK] logo abaixo saia mesmo assim: o usuario terminava o bootstrap em bash
  # achando que estava em zsh (aceite #26, 2026-08-02). sudo ja e pre-requisito
  # de tudo aqui, entao usa-lo remove o prompt em vez de adicionar um.
  if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]; then
    sudo chsh -s "$(command -v zsh)" "$USER" || true
  fi

  # .zshrc
  cat > "$HOME/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="bira"
plugins=(git)
source $ZSH/oh-my-zsh.sh

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Angular CLI autocompletion
[ "$(command -v ng)" ] && source <(ng completion script)

export PATH="$HOME/.local/bin:$PATH"
EOF

  # Constata em vez de declarar: o passo so diz OK sobre o que sobreviveu.
  if [ "$(getent passwd "$USER" | cut -d: -f7)" = "$(command -v zsh)" ]; then
    echo "[OK] Terminal configurado (shell de login = zsh). Reinicie o terminal para aplicar."
  else
    echo "  [AVISO] Oh My Zsh e .zshrc prontos, mas o shell de LOGIN continua"
    echo "          $(getent passwd "$USER" | cut -d: -f7) — o chsh nao pegou."
    echo "          Resolve com: sudo chsh -s \"\$(command -v zsh)\" \"$USER\""
  fi
}

# =============================================================================
# UTILITARIO — copia para clipboard (Wayland ou X11)
# =============================================================================
# Devolve 0 se COPIOU de fato, 1 se nao havia ferramenta. Quem chama decide o
# que dizer — antes esta funcao falhava em silencio e a mensagem afirmava
# "ja copiada para o clipboard" numa maquina virgem, onde nenhum dos tres
# existe. O operador dava Ctrl+V e nao vinha nada (aceite #26, 2026-08-02).
copy_to_clipboard() {
  if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy &>/dev/null; then
    printf '%s' "$1" | wl-copy && return 0
  elif command -v xclip &>/dev/null; then
    printf '%s' "$1" | xclip -selection clipboard && return 0
  elif command -v xsel &>/dev/null; then
    printf '%s' "$1" | xsel --clipboard --input && return 0
  elif command -v wl-copy &>/dev/null; then
    printf '%s' "$1" | wl-copy && return 0
  fi
  return 1
}

# =============================================================================
# UTILITARIO — pausa com mensagem
# =============================================================================
pause() {
  echo ""
  echo "  >>> $1"
  read -rp "      Pressione ENTER quando terminar..."
  echo ""
}

# =============================================================================
# 6. GIT + SSH + GITHUB (runtime)
# =============================================================================
setup_git_ssh() {
  echo -e "\n[autenticar] Configurando Git e chave SSH..."

  # identidade = chave divergente entre camadas (#21): vem das respostas do
  # perfil quando existem; os literais antigos ficam como default do operador
  local GIT_NAME GIT_EMAIL
  GIT_NAME="$(resposta git_name 2>/dev/null)"; GIT_NAME="${GIT_NAME:-StayneDev}"
  GIT_EMAIL="$(resposta git_email 2>/dev/null)"; GIT_EMAIL="${GIT_EMAIL:-makalyster.devops@gmail.com}"
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main

  if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$HOME/.ssh/id_ed25519" -N ""
    eval "$(ssh-agent -s)"
    ssh-add "$HOME/.ssh/id_ed25519"
  fi

  PUB_KEY=$(cat "$HOME/.ssh/id_ed25519.pub")
  local CLIP_MSG
  if copy_to_clipboard "$PUB_KEY"; then
    CLIP_MSG="ja copiada para o clipboard — cole com Ctrl+V"
  else
    CLIP_MSG="COPIE A MAO da linha abaixo (sem ferramenta de clipboard nesta maquina)"
  fi

  echo ""
  echo "  ============================================================"
  echo "  CHAVE SSH GERADA ($CLIP_MSG):"
  echo "  ============================================================"
  echo "  $PUB_KEY"
  echo "  ============================================================"

  # Abre GitHub no browser para adicionar a chave (so se houver display)
  [ -n "$DISPLAY" ] && xdg-open "https://github.com/settings/keys" 2>/dev/null &

  pause "Cole a chave SSH no GitHub (github.com/settings/keys) e clique em 'Add SSH key'"

  # Testa conexao
  echo "  Testando conexao SSH com GitHub..."
  if ssh -T git@github.com -o StrictHostKeyChecking=no 2>&1 | grep -q "successfully authenticated"; then
    echo "  [OK] GitHub autenticado com sucesso."
  else
    echo "  [AVISO] Conexao nao confirmada. Verifique se a chave foi adicionada corretamente."
  fi
}

# =============================================================================
# 7. FIREFOX — privacidade, segurança e Bitwarden
# =============================================================================

# --- Bitwarden por policy, nos dois navegadores -----------------------------
# Largar o XPI em <perfil>/extensions instala mas NAO fixa: o botao nasce
# escondido na gaveta de extensoes e o operador tem que fixar a mao. Policy
# resolve as duas coisas de uma vez e e o unico caminho que existe no Brave,
# onde nao da para largar arquivo no perfil.
_BITWARDEN_FF_ID="{446900e4-71c2-419f-a6a7-df9c091e268b}"
_BITWARDEN_CRX_ID="nngceckbapebfimnlniiiahkandclblb"

policy_bitwarden_firefox() {
  sudo mkdir -p /etc/firefox/policies
  sudo tee /etc/firefox/policies/policies.json >/dev/null <<EOF
{
  "policies": {
    "ExtensionSettings": {
      "$_BITWARDEN_FF_ID": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi",
        "default_area": "navbar"
      }
    }
  }
}
EOF
  # O Firefox do Ubuntu e snap e so le /etc/firefox se o plug etc-firefox
  # estiver conectado. Desconectado, a policy e ignorada EM SILENCIO — por isso
  # a checagem e o aviso nomeado (U2). Em snap connections, plug desconectado
  # aparece com "-" na coluna Slot.
  if command -v snap &>/dev/null && snap list firefox &>/dev/null; then
    if snap connections firefox 2>/dev/null | awk '$2=="firefox:etc-firefox" && $3=="-"' | grep -q .; then
      sudo snap connect firefox:etc-firefox 2>/dev/null \
        && echo "  [OK] plug firefox:etc-firefox conectado." \
        || echo "  [AVISO] firefox:etc-firefox desconectado — a policy sera IGNORADA pelo snap."
    fi
  fi
  echo "  [OK] Bitwarden por policy no Firefox (instala e fixa na navbar)."
}

policy_bitwarden_brave() {
  sudo mkdir -p /etc/brave/policies/managed
  sudo tee /etc/brave/policies/managed/bitwarden.json >/dev/null <<EOF
{
  "ExtensionSettings": {
    "$_BITWARDEN_CRX_ID": {
      "installation_mode": "force_installed",
      "update_url": "https://clients2.google.com/service/update2/crx",
      "toolbar_pin": "force_pinned"
    }
  }
}
EOF
  echo "  [OK] Bitwarden por policy no Brave (instala e fixa na toolbar)."
}

# Detecta qual Firefox esta disponivel e retorna o comando para abri-lo
_firefox_cmd() {
  if command -v firefox &>/dev/null; then
    echo "firefox"
  elif flatpak list --app 2>/dev/null | grep -q org.mozilla.firefox; then
    echo "flatpak run org.mozilla.firefox"
  else
    echo ""
  fi
}

# Detecta o diretorio do perfil ativo (nativo primeiro, Flatpak como fallback)
_firefox_profile() {
  local profile=""
  if [ -d "$HOME/.mozilla/firefox" ]; then
    profile=$(find "$HOME/.mozilla/firefox" -maxdepth 1 -name "*.default*" -type d | head -1)
  fi
  if [ -z "$profile" ] && [ -d "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox" ]; then
    profile=$(find "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox" -maxdepth 1 -name "*.default*" -type d | head -1)
  fi
  # Ubuntu 24.04: firefox nativo é SNAP e o perfil mora em ~/snap (achado do dev-QA #25)
  if [ -z "$profile" ] && [ -d "$HOME/snap/firefox/common/.mozilla/firefox" ]; then
    profile=$(find "$HOME/snap/firefox/common/.mozilla/firefox" -maxdepth 1 -name "*.default*" -type d | head -1)
  fi
  echo "$profile"
}

setup_firefox() {
  echo -e "\n[firefox] Configurando Firefox..."

  local FF_CMD
  FF_CMD=$(_firefox_cmd)

  if [ -z "$FF_CMD" ]; then
    echo "  [ERRO] Firefox nao encontrado (nativo nem Flatpak)."
    echo "         Instale o Firefox e re-execute: bash setup.sh --firefox"
    return 1
  fi

  # --- Bitwarden por policy ANTES de qualquer launch ---
  # O Firefox le /etc/firefox/policies na INICIALIZACAO. Escrever a policy depois
  # de abri-lo deixava a instalacao da extensao na dependencia de o operador
  # fechar e reabrir — e o passo seguinte so pedia ENTER. Aqui funcionou por
  # corrida de timing (aceite #26, 2026-08-02), o que e pior que falhar.
  policy_bitwarden_firefox

  # Se perfil nao existe, abre Firefox para criar e aguarda
  local FIREFOX_PROFILE
  FIREFOX_PROFILE=$(_firefox_profile)
  if [ -z "$FIREFOX_PROFILE" ]; then
    echo "  [INFO] Perfil nao encontrado — abrindo Firefox para criacao inicial..."
    $FF_CMD &>/dev/null &
    pause "Firefox aberto. Aguarde carregar completamente e depois FECHE-O para continuar"
    # snap firefox demora no primeiro launch (seed) — espera ATIVA pelo perfil,
    # ate 90s, em vez de confiar no timing do ENTER (achado do dev-QA #25)
    local tent=0
    FIREFOX_PROFILE=$(_firefox_profile)
    while [ -z "$FIREFOX_PROFILE" ] && [ $tent -lt 45 ]; do
      sleep 2; tent=$((tent+1))
      FIREFOX_PROFILE=$(_firefox_profile)
    done
  fi

  if [ -z "$FIREFOX_PROFILE" ]; then
    echo "  [ERRO] Perfil ainda nao encontrado. Abra o Firefox manualmente e re-execute: bash setup.sh --firefox"
    return 1
  fi

  echo "  [INFO] Perfil: $FIREFOX_PROFILE"

  # --- user.js — perfil de privacidade e seguranca ---
  # SCRIPT_DIR e DOTFILES_RAW vêm do topo, já resolvidos para o ref corrente.
  if [ -f "$SCRIPT_DIR/firefox-user.js" ]; then
    cp "$SCRIPT_DIR/firefox-user.js" "$FIREFOX_PROFILE/user.js"
  else
    curl -fsSL "$DOTFILES_RAW/firefox-user.js" -o "$FIREFOX_PROFILE/user.js"
  fi
  echo "  [OK] user.js aplicado (privacidade + seguranca)."

  echo ""
  echo "  ============================================================"
  echo "  Firefox configurado — Bitwarden instalado e fixado na toolbar."
  echo "  A fase 3 (autenticar) abre o Firefox para voce logar no cofre e"
  echo "  so depois gera a chave SSH. Nao ha nada a rodar a mao aqui."
  echo "  ============================================================"
}

# =============================================================================
# 8. SSHPILOT
# =============================================================================
install_sshpilot() {
  echo -e "\n[sshpilot] Instalando sshpilot..."
  case $DISTRO in
    arch)
      # Arch tem libadwaita atualizada — instala via AUR
      yay -S --noconfirm sshpilot
      ;;
    debian|fedora)
      # Debian Bookworm tem libadwaita 1.2.x (requer >= 1.4) — usa Flatpak autocontido
      # Fedora: Flatpak evita conflitos de versao de lib entre releases
      sudo flatpak install -y flathub io.github.mfat.sshpilot
      ;;
  esac
  echo "  [OK] sshpilot instalado."
}

# =============================================================================
# 9. LOGINS RUNTIME — Discord, Steam, Tailscale
# =============================================================================
# =============================================================================
# UTILITARIO — remover Firefox nativo e instalar Flatpak
# =============================================================================
remove_native_firefox() {
  echo -e "\n[firefox] Removendo Firefox nativo e instalando Flatpak..."
  case $DISTRO in
    arch)
      sudo pacman -Rns --noconfirm firefox 2>/dev/null || echo "  [INFO] firefox nativo nao encontrado via pacman."
      ;;
    debian)
      sudo apt remove -y --purge firefox-esr firefox 2>/dev/null || true
      sudo apt autoremove -y
      ;;
    fedora)
      sudo dnf remove -y firefox 2>/dev/null || true
      ;;
  esac
  # Remove perfil nativo (backup antes)
  if [ -d "$HOME/.mozilla/firefox" ]; then
    mv "$HOME/.mozilla/firefox" "$HOME/.mozilla/firefox.bak.$(date +%Y%m%d%H%M%S)"
    echo "  [OK] Perfil nativo movido para backup em ~/.mozilla/firefox.bak.*"
  fi
  flatpak install -y flathub org.mozilla.firefox
  echo "  [OK] Firefox Flatpak instalado. Execute --firefox para configurar."
}

login_firefox() {
  echo -e "\n[Firefox] Abrindo Firefox para login no Bitwarden..."
  local FF_CMD
  FF_CMD=$(_firefox_cmd)
  if [ -z "$FF_CMD" ]; then
    echo "  [ERRO] Firefox nao encontrado. Instale e re-execute."
    return 1
  fi

  # A policy (policy_bitwarden_firefox) instala e fixa na navbar no startup do
  # Firefox — nao ha mais passo de "fixe o icone" nem pagina da AMO para abrir.
  $FF_CMD &>/dev/null &
  echo ""
  echo "  ============================================================"
  echo "  Firefox aberto. O icone do Bitwarden ja esta na toolbar."
  echo ""
  echo "  O QUE FAZER:"
  echo "  1. Clique no icone do Bitwarden na toolbar"
  echo "  2. Clique em 'Criar conta' ou 'Fazer login'"
  echo "  3. Entre com seu email e senha mestre"
  echo "  4. Se o cofre nao sincronizar, clique em 'Sincronizar cofre'"
  echo ""
  echo "  Se o icone NAO estiver la, a policy nao foi aplicada — procure o"
  echo "  [AVISO] de firefox:etc-firefox no log da fase configurar."
  echo "  ============================================================"

  pause "Pressione ENTER quando estiver logado no Bitwarden"
}

login_discord() {
  echo -e "\n[Discord] Abrindo Discord para login..."
  flatpak run com.discordapp.Discord &>/dev/null &
  pause "Faca login no Discord e feche-o (ou minimize) quando terminar"
}

login_steam() {
  echo -e "\n[Steam] Abrindo Steam para login..."
  flatpak run com.valvesoftware.Steam &>/dev/null &
  pause "Faca login no Steam e feche-o (ou minimize) quando terminar"
}

login_tailscale() {
  echo -e "\n[Tailscale] Autenticacao via auth key..."
  echo ""
  local FF_CMD; FF_CMD=$(_firefox_cmd)
  [ -n "$DISPLAY" ] && [ -n "$FF_CMD" ] && $FF_CMD "https://login.tailscale.com/admin/machines/new-linux" &>/dev/null &
  echo "  ============================================================"
  echo "  1. Acesse: https://login.tailscale.com/admin/machines/new-linux"
  echo "  2. Clique em 'Generate auth key'"
  echo "  3. Marque 'Reusable' se quiser usar em mais de uma maquina"
  echo "  4. Cole a chave abaixo (formato: tskey-auth-...)"
  echo "  ============================================================"
  read -rp "  Auth key: " TAILSCALE_KEY
  if [ -n "$TAILSCALE_KEY" ]; then
    sudo tailscale up --authkey="$TAILSCALE_KEY"
    if tailscale status &>/dev/null; then
      echo "  [OK] Tailscale conectado."
    else
      echo "  [AVISO] Tailscale nao confirmado. Verifique a chave e tente: sudo tailscale up --authkey=<key>"
    fi
  else
    echo "  [AVISO] Nenhuma chave informada. Execute manualmente: sudo tailscale up --authkey=<key>"
  fi
}

# Devolve 0 quando a conta esta autenticada. `claude auth status` sai em JSON com
# `loggedIn`, entao isto e CONSTATAVEL — nao precisa de fe.
_claude_logado() {
  command -v claude &>/dev/null || return 1
  claude auth status 2>/dev/null | grep -q '"loggedIn": *true'
}

login_claude() {
  echo -e "\n[Claude Code] Iniciando login..."
  if ! command -v claude &>/dev/null; then
    echo "  [AVISO] Claude Code nao encontrado. Instale primeiro com --node."
    return 1
  fi

  # Idempotencia (U8): re-execucao nao reabre login de quem ja esta dentro.
  if _claude_logado; then
    echo "  [OK] ja autenticado ($(claude auth status 2>/dev/null | grep -oP '"email":\s*"\K[^"]+' || echo 'conta ativa'))."
    return 0
  fi

  # AQUI ESTAVA O TRAVAMENTO. A linha era `claude /login`, e `/login` NAO e
  # subcomando: a assinatura do CLI e `claude [options] [command] [prompt]`, entao
  # `/login` caia como PROMPT e o binario abria a sessao interativa inteira com
  # aquilo digitado. O bootstrap nao travava — ficava preso em primeiro plano
  # dentro do REPL do Claude, e so voltava quando o operador saisse dele. Como
  # todos os outros logins deste script jogam o app para segundo plano e pedem
  # ENTER, este era o unico que tomava o terminal, e ninguem esperava isso.
  # O comando dedicado existe: `claude auth login` (achado no aceite #26).
  if [ ! -t 0 ]; then
    echo ""
    echo "  [AVISO] login do Claude Code exige terminal interativo — pulando."
    echo "          rode depois, num terminal de verdade:  claude auth login"
    return 0
  fi
  echo ""
  echo "  ============================================================"
  echo "  Sera aberto o fluxo de autenticacao no browser."
  echo "  >> Faca login com sua conta Anthropic"
  echo "  >> Autorize o acesso quando solicitado"
  echo "  ============================================================"
  claude auth login || true

  # Constata em vez de perguntar: o ENTER do operador nao prova login nenhum.
  if _claude_logado; then
    echo "  [OK] autenticado."
  else
    echo '  [AVISO] claude auth status ainda diz que nao ha sessao.'
    echo "          rode a mao quando puder:  claude auth login"
  fi
}

runtime_logins() {
  login_discord
  login_steam
  login_tailscale
  login_claude
}

# =============================================================================
# 10. VSCODE — extensões e settings
# =============================================================================
setup_vscode() {
  echo -e "\n[vscode] Aplicando settings e instalando extensões..."

  # SCRIPT_DIR e DOTFILES_RAW vêm do topo, já resolvidos para o ref corrente.
  VSCODE_SETTINGS_DIR="$HOME/.config/Code/User"
  mkdir -p "$VSCODE_SETTINGS_DIR"

  # settings.json — local ou fallback via curl
  if [ -f "$SCRIPT_DIR/vscode-settings.json" ]; then
    cp "$SCRIPT_DIR/vscode-settings.json" "$VSCODE_SETTINGS_DIR/settings.json"
  else
    curl -fsSL "$DOTFILES_RAW/vscode-settings.json" -o "$VSCODE_SETTINGS_DIR/settings.json"
  fi
  echo "  [OK] Settings aplicados."

  # vscode-extensions.txt — local ou fallback via curl
  EXTENSIONS_FILE="$SCRIPT_DIR/vscode-extensions.txt"
  if [ ! -f "$EXTENSIONS_FILE" ]; then
    EXTENSIONS_FILE="/tmp/vscode-extensions.txt"
    curl -fsSL "$DOTFILES_RAW/vscode-extensions.txt" -o "$EXTENSIONS_FILE"
  fi

  if ! command -v code &>/dev/null; then
    echo "  [AVISO] VSCode não encontrado. Instale primeiro com --base."
    return
  fi
  echo "  Instalando extensões..."
  while IFS= read -r ext; do
    [[ -z "$ext" || "$ext" == \#* ]] && continue
    code --install-extension "$ext" --force 2>/dev/null && echo "  [OK] $ext" || echo "  [ERRO] $ext"
  done < "$EXTENSIONS_FILE"
  echo "  [OK] Extensões instaladas."
}

# =============================================================================
# 11. CLAUDE CONFIG (skills, settings — repo dedicado)
# =============================================================================
install_claude_config() {
  echo -e "\n[fechar] Configurando Claude Code (orquestrador)..."
  # Era um PAR de repos entre 2026-08-01 e 2026-08-05 — acervo mais maquinaria,
  # que precisavam cair lado a lado no caminho relativo exato. A divisão foi
  # revogada (ADR-20260805-revogacao-do-par, no repo do orquestrador) e clonar
  # um repo é estritamente mais simples que garantir a adjacência de dois: era
  # essa adjacência que o `install.sh` do par tratava como bootstrap incompleto.
  # O diretório se chama O.N.A desde o batismo de 2026-08-07; o repo no GitHub
  # ainda responde pelo nome antigo e redireciona. O settings.json versionado
  # aponta para $ORQ_RAIZ/O.N.A, então o nome do DIRETÓRIO é o que importa —
  # clonar com o nome velho deixa os 7 ganchos apontando para caminho que não
  # existe, e o carregador falha no primeiro token da sessão.
  local ORQ_DIR="$HOME/Documentos/repos/O.N.A"
  # repo privado — clone via SSH (requer --github feito antes)
  mkdir -p "$HOME/Documentos/repos"
  if [ ! -d "$ORQ_DIR/.git" ]; then
    git clone git@github.com:StayneDev/orquestrador-normativo-agente.git "$ORQ_DIR"
  fi
  bash "$ORQ_DIR/install.sh"
  echo "  [OK] Orquestrador instalado."

  # A SONDA DO O.N.A HUB — sem ela a frota é cega para esta máquina, e o painel
  # mostra o estado de quem empurrou por último em vez do conjunto. O agregador
  # vive no CT 102; o TOKEN é segredo compartilhado e NÃO entra em repo (Segredos).
  echo -e "\n[fechar] Instalando a sonda do O.N.A HUB..."
  local HUB_DIR="$HOME/Documentos/projetos/O.N.A-HUB"
  mkdir -p "$HOME/Documentos/projetos"
  if [ ! -d "$HUB_DIR/.git" ]; then
    git clone git@github.com:StayneDev/O.N.A-HUB.git "$HUB_DIR"
  fi
  if [ -n "${ORQ_AGREGADOR:-}" ] && [ -n "${ORQ_TOKEN:-}" ]; then
    bash "$HUB_DIR/install.sh" "$ORQ_AGREGADOR" "$ORQ_TOKEN" sonda
    # serviço de usuário morre no logout sem isto — a sonda tem de sobreviver a reboot
    loginctl enable-linger "$USER" 2>/dev/null || true
    echo "  [OK] Sonda instalada e com linger."
  else
    echo "  [PENDENTE] sonda NÃO instalada: exporte ORQ_AGREGADOR e ORQ_TOKEN e rode"
    echo "             bash $HUB_DIR/install.sh <url> <token> sonda && loginctl enable-linger $USER"
    echo "             (o token é segredo e por isso não mora aqui — ver [[Segredos]])"
  fi
}

# =============================================================================
# FASES (U15) — provisionar → configurar → autenticar → fechar
# =============================================================================
# A passagem entre fases é VERIFICADA, nunca comentário: cada fase abre com o
# gate que prova a anterior, lendo o estado real da máquina (não a memória de
# execução — "rodei" não é "está"). Gate reprovado recusa na entrada e CONDUZ:
# diz exatamente o comando que resolve. Decidido na antessala
# (docs/Decisões/ADR-20260801-antessala-bootstrap-do-par-e-da-infra.md, issue #20).

gate_provisionado() {
  local faltas=()
  local b
  for b in git curl zsh flatpak; do
    command -v "$b" &>/dev/null || faltas+=("$b")
  done
  if [ ${#faltas[@]} -gt 0 ]; then
    echo "[gate] provisionar incompleto — faltam: ${faltas[*]}"
    echo "[gate] rode antes: bash setup.sh --fase provisionar"
    return 1
  fi
}

gate_configurado() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "[gate] configurar incompleto — terminal não configurado (oh-my-zsh ausente)"
    echo "[gate] rode antes: bash setup.sh --fase configurar"
    return 1
  fi
}

gate_autenticado() {
  if ! ssh -T git@github.com -o StrictHostKeyChecking=no -o BatchMode=yes 2>&1 | grep -q "successfully authenticated"; then
    echo "[gate] autenticar incompleto — GitHub não responde à chave SSH desta máquina"
    echo "[gate] rode antes: bash setup.sh --fase autenticar"
    return 1
  fi
}

fase_provisionar() {
  echo -e "\n══════ FASE 1/4 — PROVISIONAR (tudo que é público) ══════"
  detect_distro
  install_base
  install_flatpak_apps
  install_java
  install_node_and_claude
  install_sshpilot
}

fase_configurar() {
  gate_provisionado || return 1
  echo -e "\n══════ FASE 2/4 — CONFIGURAR ══════"
  setup_terminal
  setup_vscode
  setup_firefox
}

fase_autenticar() {
  gate_configurado || return 1
  echo -e "\n══════ FASE 3/4 — AUTENTICAR (interativa por natureza) ══════"
  login_firefox          # Bitwarden primeiro: é o cofre de onde o resto sai
  setup_git_ssh          # chave SSH + GitHub — destrava os clones privados
  login_tailscale
  login_claude
}

fase_fechar() {
  gate_autenticado || return 1
  echo -e "\n══════ FASE 4/4 — FECHAR (clones privados + verificação) ══════"
  install_claude_config  # clona o par e roda o install.sh do motor, que verifica
  echo ""
  echo "============================================================"
  echo "  FASES CONCLUÍDAS"
  echo "  Logins de apps pessoais (à parte, por perfil): --discord --steam"
  echo "  Reinicie o terminal para aplicar o zsh."
  echo "============================================================"
}

rodar_fase() {
  case "$1" in
    provisionar) fase_provisionar ;;
    configurar)  fase_configurar ;;
    autenticar)  fase_autenticar ;;
    fechar)      fase_fechar ;;
    *) echo "Fase desconhecida: $1 (use: provisionar | configurar | autenticar | fechar)"; return 1 ;;
  esac
}

# =============================================================================
# AJUDA
# =============================================================================
show_help() {
  echo ""
  echo "Uso: bash setup.sh [opcao]"
  echo ""
  echo "  (sem opcao)       Menu de perfil (pergunta UMA vez, grava respostas) + 4 fases"
  echo ""
  echo "  Perfis (manifesto em perfis/*.perfil; composicao: perfil = minimo + camada):"
  echo "    --perfil <nome>      headless: minimo | pessoal | profissional | infra"
  echo "    --conferir [nome]    conferencia declarado x real do perfil"
  echo ""
  echo "  Fases (a passagem e verificada — fase sem pre-requisito recusa e conduz):"
  echo "    --fase provisionar   1/4: tudo que e publico (base, flatpak, java, node, sshpilot)"
  echo "    --fase configurar    2/4: terminal, vscode, firefox (exige provisionar)"
  echo "    --fase autenticar    3/4: bitwarden, ssh/github, tailscale, claude (exige configurar)"
  echo "    --fase fechar        4/4: clones privados do par + verificacao (exige autenticar)"
  echo ""
  echo "  Instalacao:"
  echo "    --base          Pacotes base (git, curl, zsh, vscode...)"
  echo "    --flatpak       Apps Flatpak (Discord, Steam, Firefox)"
  echo "    --java          JDK 21"
  echo "    --node          nvm + Node LTS + Claude Code"
  echo "    --sshpilot      sshpilot (AUR / APT / COPR)"
  echo "    --vscode        Settings e extensões do VSCode"
  echo "    --claude        Claude skills, settings e sync automático"
  echo ""
  echo "  Configuracao:"
  echo "    --terminal      Zsh + Oh My Zsh + tema bira"
  echo "    --firefox       Firefox privacidade + Bitwarden (fazer antes de --github)"
  echo "    --github        Git config + chave SSH + adicionar no GitHub (requer Bitwarden)"
  echo ""
  echo "  Logins:"
  echo "    --login-firefox        Abrir Firefox para login + Bitwarden
    --remove-native-firefox Remover Firefox nativo e instalar via Flatpak"
  echo "    --discord       Abrir Discord para login"
  echo "    --steam         Abrir Steam para login"
  echo "    --tailscale     Autenticar Tailscale"
  echo "    --logins        Todos os logins em sequencia (discord, steam, tailscale)"
  echo ""
}

# =============================================================================
# EXECUCAO
# =============================================================================
# Guard de source: os testes (testes/fases.sh) carregam as funções com `source`
# sem disparar o dispatch — executar direto continua funcionando igual.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0 2>/dev/null || true
fi

case "$1" in
  --fase)       rodar_fase "$2" ;;
  --perfil)     rodar_perfil "$2" ;;   # headless: com respostas gravadas, não pergunta nada
  --conferir)   conferir_perfil "${2:-$(resposta perfil)}" ;;
  --base)       detect_distro; install_base ;;
  --flatpak)    install_flatpak_apps ;;
  --java)       detect_distro; install_java ;;
  --node)       install_node_and_claude ;;
  --sshpilot)   detect_distro; install_sshpilot ;;
  --terminal)   setup_terminal ;;
  --github)     setup_git_ssh ;;
  --firefox)    setup_firefox ;;
  --login-firefox) login_firefox ;;
  --remove-native-firefox) detect_distro; remove_native_firefox ;;
  --discord)    login_discord ;;
  --steam)      login_steam ;;
  --tailscale)  login_tailscale ;;
  --logins)     runtime_logins ;;
  --vscode)     setup_vscode ;;
  --claude)     install_claude_config ;;
  --help|-h)    show_help ;;
  "")
    # Interativo UMA VEZ (#22): o menu escolhe o perfil e colhe as divergentes
    # no início; grava nas respostas; o resto roda sozinho pelas 4 fases com
    # gates (#20). Re-execução lê as respostas e não pergunta (U8).
    PERFIL_ESCOLHIDO=$(menu_perfil) || exit 1
    rodar_perfil "$PERFIL_ESCOLHIDO"
    ;;
  *)
    echo "Opcao desconhecida: $1"
    show_help
    exit 1
    ;;
esac
