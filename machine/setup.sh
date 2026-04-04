#!/bin/bash

# =============================================================================
# POST-FORMAT SETUP — multi-distro (Arch, Ubuntu/Debian, Fedora)
# =============================================================================

set -e

if [ "$EUID" -eq 0 ]; then
  echo "Execute como usuario comum (nao root)."
  exit 1
fi

# --- Deteccao de distro ---
detect_distro() {
  if command -v pacman &>/dev/null; then DISTRO="arch"
  elif command -v apt-get &>/dev/null; then DISTRO="debian"
  elif command -v dnf &>/dev/null; then DISTRO="fedora"
  else echo "Distro nao suportada." && exit 1
  fi
  echo "[INFO] Distro detectada: $DISTRO"
}

# =============================================================================
# 1. PACOTES BASE
# =============================================================================
install_base() {
  echo -e "\n[1/7] Instalando pacotes base..."

  case $DISTRO in
    arch)
      sudo pacman -Syu --noconfirm
      sudo pacman -S --noconfirm --needed \
        git curl zsh zsh-completions \
        neofetch cmatrix \
        tailscale \
        ttf-liberation ttf-nerd-fonts-symbols-common noto-fonts noto-fonts-emoji \
        power-profiles-daemon wireplumber \
        flatpak
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
      # Garante repos online — remove cdrom e adiciona bookworm se ausente
      sudo sed -i '/^deb cdrom:/d' /etc/apt/sources.list
      if ! grep -q "deb.debian.org" /etc/apt/sources.list; then
        cat <<'EOF' | sudo tee /etc/apt/sources.list > /dev/null
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF
        echo "  [OK] sources.list atualizado para repositorios online."
      fi
      sudo apt update && sudo apt upgrade -y
      sudo apt install -y git curl zsh neofetch cmatrix flatpak
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
      sudo dnf install -y git curl zsh neofetch cmatrix flatpak
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

  # Flatpak remote
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

# =============================================================================
# 2. APPS VIA FLATPAK (universal)
# =============================================================================
install_flatpak_apps() {
  echo -e "\n[2/7] Instalando apps via Flatpak..."
  sudo flatpak install -y flathub com.discordapp.Discord
  sudo flatpak install -y flathub com.valvesoftware.Steam
  # Firefox nao e instalado aqui — distros ja incluem versao nativa.
  # Flatpak e usado apenas como fallback via --firefox quando nativo ausente.
}

# =============================================================================
# 3. JDK 21
# =============================================================================
install_java() {
  echo -e "\n[3/7] Instalando JDK 21..."
  case $DISTRO in
    arch)    sudo pacman -S --noconfirm --needed jdk21-openjdk ;;
    debian)
      # openjdk-21 requer backports no Bookworm
      if ! apt-cache show openjdk-21-jdk &>/dev/null; then
        BACKPORTS="deb http://deb.debian.org/debian bookworm-backports main contrib non-free"
        if ! grep -qF "bookworm-backports" /etc/apt/sources.list; then
          echo "$BACKPORTS" | sudo tee -a /etc/apt/sources.list > /dev/null
          sudo apt update
        fi
      fi
      if apt-cache show openjdk-21-jdk &>/dev/null; then
        sudo apt install -y -t bookworm-backports openjdk-21-jdk
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
  echo -e "\n[4/7] Instalando nvm, Node e Claude Code..."

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
  echo -e "\n[5/7] Configurando terminal..."

  # Oh My Zsh
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi

  # Shell padrao para zsh
  if [ "$(getent passwd $USER | cut -d: -f7)" != "$(which zsh)" ]; then
    chsh -s "$(which zsh)"
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

  echo "[OK] Terminal configurado. Reinicie o terminal para aplicar."
}

# =============================================================================
# UTILITARIO — copia para clipboard (Wayland ou X11)
# =============================================================================
copy_to_clipboard() {
  if command -v wl-copy &>/dev/null; then
    echo "$1" | wl-copy
  elif command -v xclip &>/dev/null; then
    echo "$1" | xclip -selection clipboard
  elif command -v xsel &>/dev/null; then
    echo "$1" | xsel --clipboard --input
  fi
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
  echo -e "\n[6/7] Configurando Git e chave SSH..."

  git config --global user.name "StayneDev"
  git config --global user.email "makalyster.devops@gmail.com"
  git config --global init.defaultBranch main

  if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "makalyster.devops@gmail.com" -f "$HOME/.ssh/id_ed25519" -N ""
    eval "$(ssh-agent -s)"
    ssh-add "$HOME/.ssh/id_ed25519"
  fi

  PUB_KEY=$(cat "$HOME/.ssh/id_ed25519.pub")
  copy_to_clipboard "$PUB_KEY"

  echo ""
  echo "  ============================================================"
  echo "  CHAVE SSH GERADA (ja copiada para o clipboard):"
  echo "  ============================================================"
  echo "  $PUB_KEY"
  echo "  ============================================================"

  # Abre GitHub no browser para adicionar a chave
  xdg-open "https://github.com/settings/keys" 2>/dev/null &

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

  # Se perfil nao existe, abre Firefox para criar e aguarda
  local FIREFOX_PROFILE
  FIREFOX_PROFILE=$(_firefox_profile)
  if [ -z "$FIREFOX_PROFILE" ]; then
    echo "  [INFO] Perfil nao encontrado — abrindo Firefox para criacao inicial..."
    $FF_CMD &>/dev/null &
    pause "Firefox aberto. Aguarde carregar completamente e depois FECHE-O para continuar"
    FIREFOX_PROFILE=$(_firefox_profile)
  fi

  if [ -z "$FIREFOX_PROFILE" ]; then
    echo "  [ERRO] Perfil ainda nao encontrado. Abra o Firefox manualmente e re-execute: bash setup.sh --firefox"
    return 1
  fi

  echo "  [INFO] Perfil: $FIREFOX_PROFILE"

  # --- user.js — perfil de privacidade e seguranca ---
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  DOTFILES_RAW="https://raw.githubusercontent.com/StayneDev/dotfiles/main/machine"
  if [ -f "$SCRIPT_DIR/firefox-user.js" ]; then
    cp "$SCRIPT_DIR/firefox-user.js" "$FIREFOX_PROFILE/user.js"
  else
    curl -fsSL "$DOTFILES_RAW/firefox-user.js" -o "$FIREFOX_PROFILE/user.js"
  fi
  echo "  [OK] user.js aplicado (privacidade + seguranca)."

  # --- Bitwarden via policies.json (force_installed) ---
  # Detecta dinamicamente o diretorio de instalacao do Firefox nativo
  POLICIES_DIRS=()
  local FF_BIN
  FF_BIN=$(command -v firefox 2>/dev/null)
  if [ -n "$FF_BIN" ]; then
    local FF_REAL FF_DIR
    FF_REAL=$(readlink -f "$FF_BIN")
    FF_DIR=$(dirname "$FF_REAL")
    POLICIES_DIRS+=("$FF_DIR/distribution")
    # Cobre casos onde o binario e um wrapper (ex: /usr/bin -> /usr/lib/firefox-esr)
    local FF_LIB_DIR
    FF_LIB_DIR=$(find /usr/lib /usr/lib64 -maxdepth 1 -name "firefox*" -type d 2>/dev/null | head -5)
    while IFS= read -r DIR; do
      [[ -d "$DIR" ]] && POLICIES_DIRS+=("$DIR/distribution")
    done <<< "$FF_LIB_DIR"
  fi
  # Flatpak Firefox — apenas se instalado
  if flatpak list --app 2>/dev/null | grep -q org.mozilla.firefox; then
    POLICIES_DIRS+=("$HOME/.var/app/org.mozilla.firefox/etc/firefox/policies")
  fi
  # Remove duplicatas
  readarray -t POLICIES_DIRS < <(printf '%s\n' "${POLICIES_DIRS[@]}" | sort -u)

  local BITWARDEN_POLICY='{
  "policies": {
    "ExtensionSettings": {
      "{446900e4-71c2-419f-a6a7-df9c091e268b}": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi"
      }
    }
  }
}'
  echo "$BITWARDEN_POLICY" > /tmp/firefox_policies.json
  local POLICY_APPLIED=false
  for DIR in "${POLICIES_DIRS[@]}"; do
    if [[ "$DIR" == /usr/* || "$DIR" == /opt/* ]]; then
      if sudo mkdir -p "$DIR" 2>/dev/null && sudo cp /tmp/firefox_policies.json "$DIR/policies.json"; then
        echo "  [OK] Bitwarden policies.json em: $DIR"
        POLICY_APPLIED=true
      fi
    else
      if mkdir -p "$DIR" 2>/dev/null && cp /tmp/firefox_policies.json "$DIR/policies.json"; then
        echo "  [OK] Bitwarden policies.json em: $DIR"
        POLICY_APPLIED=true
      fi
    fi
  done

  if [ "$POLICY_APPLIED" = false ]; then
    echo "  [AVISO] Nao foi possivel aplicar policies.json automaticamente."
    echo "          Instale o Bitwarden manualmente em: https://addons.mozilla.org/firefox/addon/bitwarden-password-manager/"
  fi

  echo ""
  echo "  ============================================================"
  echo "  Firefox configurado. Proximos passos:"
  echo "  1. Execute: bash setup.sh --login-firefox"
  echo "  2. Bitwarden sera instalado automaticamente ao abrir o Firefox"
  echo "  3. Faca login no Bitwarden e importe suas configuracoes"
  echo "  4. So entao execute: bash setup.sh --github"
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

  # Verifica se policies.json foi aplicado (Bitwarden deveria instalar automaticamente)
  local POLICY_FOUND=false
  for DIR in /usr/lib/firefox*/distribution /usr/lib64/firefox*/distribution; do
    [ -f "$DIR/policies.json" ] && POLICY_FOUND=true && break
  done

  $FF_CMD &>/dev/null &
  sleep 2

  if [ "$POLICY_FOUND" = true ]; then
    echo ""
    echo "  ============================================================"
    echo "  Firefox aberto."
    echo "  >> Bitwarden sera instalado automaticamente (aguarde alguns segundos)"
    echo "  >> Se nao aparecer: clique no link abaixo para instalar com 1 clique"
    echo "     https://addons.mozilla.org/firefox/addon/bitwarden-password-manager/"
    echo "  >> Apos instalar, faca login no Bitwarden"
    echo "  >> Importe suas configuracoes/cofre se necessario"
    echo "  >> MINIMIZE o Firefox (nao feche)"
    echo "  ============================================================"
  else
    echo ""
    echo "  ============================================================"
    echo "  Firefox aberto."
    echo "  >> Policies nao detectadas — instale o Bitwarden manualmente:"
    echo "     https://addons.mozilla.org/firefox/addon/bitwarden-password-manager/"
    echo "  >> Apos instalar, faca login no Bitwarden"
    echo "  >> Execute --firefox novamente para reaplicar as policies"
    echo "  ============================================================"
    # Abre a pagina do addon como fallback
    sleep 1
    $FF_CMD "https://addons.mozilla.org/firefox/addon/bitwarden-password-manager/" &>/dev/null &
  fi

  pause "Pressione ENTER quando o Bitwarden estiver instalado e logado"
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
  echo -e "\n[Tailscale] Iniciando autenticacao Tailscale..."
  sudo tailscale up --qr 2>/dev/null || sudo tailscale up
  pause "Autentique o Tailscale no browser que foi aberto"
  if tailscale status &>/dev/null; then
    echo "  [OK] Tailscale conectado."
  else
    echo "  [AVISO] Tailscale nao confirmado. Execute: sudo tailscale up"
  fi
}

runtime_logins() {
  login_discord
  login_steam
  login_tailscale
}

# =============================================================================
# 10. VSCODE — extensões e settings
# =============================================================================
setup_vscode() {
  echo -e "\n[vscode] Aplicando settings e instalando extensões..."

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  VSCODE_SETTINGS_DIR="$HOME/.config/Code/User"
  DOTFILES_RAW="https://raw.githubusercontent.com/StayneDev/dotfiles/main/machine"
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
  echo -e "\n[10/10] Configurando Claude Code (skills e settings)..."
  bash <(curl -fsSL https://raw.githubusercontent.com/StayneDev/claude-config/main/install.sh)
  echo "  [OK] Claude config instalado."
}

# =============================================================================
# EXECUCAO
# =============================================================================

# =============================================================================
# AJUDA
# =============================================================================
show_help() {
  echo ""
  echo "Uso: bash setup.sh [opcao]"
  echo ""
  echo "  (sem opcao)       Executa o setup completo em sequencia"
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
case "$1" in
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
    detect_distro
    install_base
    install_flatpak_apps
    install_java
    install_node_and_claude
    install_sshpilot
    setup_terminal
    setup_firefox
    login_firefox
    setup_git_ssh
    setup_vscode
    install_claude_config
    runtime_logins
    echo ""
    echo "============================================================"
    echo "  SETUP CONCLUIDO"
    echo "============================================================"
    echo "  Tudo configurado. Reinicie o terminal para aplicar o zsh."
    echo "============================================================"
    ;;
  *)
    echo "Opcao desconhecida: $1"
    show_help
    exit 1
    ;;
esac
