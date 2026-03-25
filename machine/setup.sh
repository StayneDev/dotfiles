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
      sudo apt update && sudo apt upgrade -y
      sudo apt install -y git curl zsh neofetch cmatrix flatpak
      # VSCode
      wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg > /dev/null
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
      sudo apt update && sudo apt install -y code
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
  flatpak install -y flathub com.discordapp.Discord
  flatpak install -y flathub com.valvesoftware.Steam
  flatpak install -y flathub org.mozilla.firefox
}

# =============================================================================
# 3. JDK 21
# =============================================================================
install_java() {
  echo -e "\n[3/7] Instalando JDK 21..."
  case $DISTRO in
    arch)    sudo pacman -S --noconfirm --needed jdk21-openjdk ;;
    debian)  sudo apt install -y openjdk-21-jdk ;;
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
# 7. FIREFOX — configuracao privacidade (sem senhas, sem formularios)
# =============================================================================
setup_firefox() {
  echo -e "\n[7/7] Configurando Firefox..."

  # Aguarda o perfil ser criado na primeira execucao
  FIREFOX_PROFILE=""

  # Tenta perfil nativo
  if [ -d "$HOME/.mozilla/firefox" ]; then
    FIREFOX_PROFILE=$(find "$HOME/.mozilla/firefox" -maxdepth 1 -name "*.default*" -type d | head -1)
  fi

  # Tenta perfil Flatpak
  if [ -z "$FIREFOX_PROFILE" ] && [ -d "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox" ]; then
    FIREFOX_PROFILE=$(find "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox" -maxdepth 1 -name "*.default*" -type d | head -1)
  fi

  if [ -z "$FIREFOX_PROFILE" ]; then
    echo "[AVISO] Perfil do Firefox nao encontrado. Abra o Firefox uma vez e re-execute esta funcao."
    echo "        Para re-executar: bash setup.sh --firefox"
    return
  fi

  # --- Bitwarden via policies.json (force_installed) ---
  # Funciona para Firefox nativo e Flatpak
  POLICIES_DIRS=(
    "/usr/lib/firefox/distribution"
    "/usr/lib64/firefox/distribution"
    "$HOME/.var/app/org.mozilla.firefox/etc/firefox/policies"
  )
  for DIR in "${POLICIES_DIRS[@]}"; do
    if sudo mkdir -p "$DIR" 2>/dev/null || mkdir -p "$DIR" 2>/dev/null; then
      POLICIES_FILE="$DIR/policies.json"
      cat > /tmp/firefox_policies.json <<'POLICIES'
{
  "policies": {
    "ExtensionSettings": {
      "{446900e4-71c2-419f-a6a7-df9c091e268b}": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi"
      }
    }
  }
}
POLICIES
      if [[ "$DIR" == /usr/* ]]; then
        sudo cp /tmp/firefox_policies.json "$POLICIES_FILE"
      else
        cp /tmp/firefox_policies.json "$POLICIES_FILE"
      fi
      echo "  [OK] Bitwarden configurado em: $POLICIES_FILE"
    fi
  done

  cat > "$FIREFOX_PROFILE/user.js" <<'EOF'
// --- Senhas e formularios ---
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("browser.formfill.enable", false);
user_pref("extensions.formautofill.addresses.enabled", false);
user_pref("extensions.formautofill.creditCards.enabled", false);

// --- Telemetria e rastreamento ---
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("app.shield.optoutstudies.enabled", false);

// --- Sugestoes e patrocinios ---
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
user_pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);

// --- Privacidade geral ---
user_pref("privacy.donottrackheader.enabled", true);
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
user_pref("geo.enabled", false);
user_pref("media.peerconnection.enabled", false);

// --- Comportamento ---
user_pref("browser.startup.page", 3);
user_pref("browser.aboutConfig.showWarning", false);
EOF

  echo "[OK] Firefox configurado em: $FIREFOX_PROFILE"
}

# =============================================================================
# 8. SSHPILOT
# =============================================================================
install_sshpilot() {
  echo -e "\n[sshpilot] Instalando sshpilot..."
  case $DISTRO in
    arch)
      yay -S --noconfirm sshpilot
      ;;
    debian)
      curl -fsSL https://mfat.github.io/sshpilot-ppa/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/sshpilot-ppa.gpg
      echo "deb [signed-by=/usr/share/keyrings/sshpilot-ppa.gpg arch=amd64] https://mfat.github.io/sshpilot-ppa any main" | sudo tee /etc/apt/sources.list.d/sshpilot-ppa.list
      sudo apt update && sudo apt install -y sshpilot
      ;;
    fedora)
      sudo dnf copr enable -y mahdif62/sshpilot
      sudo dnf install -y sshpilot
      ;;
  esac
  echo "  [OK] sshpilot instalado."
}

# =============================================================================
# 9. LOGINS RUNTIME — Discord, Steam, Tailscale
# =============================================================================
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
  mkdir -p "$VSCODE_SETTINGS_DIR"

  if [ -f "$SCRIPT_DIR/vscode-settings.json" ]; then
    cp "$SCRIPT_DIR/vscode-settings.json" "$VSCODE_SETTINGS_DIR/settings.json"
    echo "  [OK] Settings aplicados."
  fi

  if [ -f "$SCRIPT_DIR/vscode-extensions.txt" ]; then
    if ! command -v code &>/dev/null; then
      echo "  [AVISO] VSCode não encontrado. Instale primeiro com --base."
      return
    fi
    echo "  Instalando extensões..."
    while IFS= read -r ext; do
      [[ -z "$ext" || "$ext" == \#* ]] && continue
      code --install-extension "$ext" --force 2>/dev/null && echo "  [OK] $ext" || echo "  [ERRO] $ext"
    done < "$SCRIPT_DIR/vscode-extensions.txt"
    echo "  [OK] Extensões instaladas."
  fi
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
  echo "    --github        Git config + chave SSH + adicionar no GitHub"
  echo "    --firefox       Firefox privacidade + Bitwarden"
  echo ""
  echo "  Logins:"
  echo "    --discord       Abrir Discord para login"
  echo "    --steam         Abrir Steam para login"
  echo "    --tailscale     Autenticar Tailscale"
  echo "    --logins        Todos os logins em sequencia"
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
    setup_git_ssh
    setup_firefox
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
