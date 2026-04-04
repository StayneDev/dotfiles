# dotfiles

Setup pós-formatação para Arch, Debian/Ubuntu e Fedora.

## Instalação

O método padrão usa `curl` — não requer `git` nem clonar o repositório antes.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/StayneDev/dotfiles/main/machine/setup.sh)
```

O script detecta a distro automaticamente e instala tudo em sequência, incluindo `git`.

> `curl` vem pré-instalado na grande maioria das distros modernas.
> Se não estiver disponível: `sudo apt install curl` / `sudo pacman -S curl` / `sudo dnf install curl`

---

## Módulos individuais

Para instalar partes específicas:

```bash
SETUP="bash <(curl -fsSL https://raw.githubusercontent.com/StayneDev/dotfiles/main/machine/setup.sh)"

eval "$SETUP" --base        # pacotes base (git, curl, zsh, VSCode, Tailscale)
eval "$SETUP" --flatpak     # Discord, Steam, Firefox via Flatpak
eval "$SETUP" --java        # JDK 21
eval "$SETUP" --node        # nvm + Node LTS + Claude Code
eval "$SETUP" --sshpilot    # sshpilot
eval "$SETUP" --terminal    # Zsh + Oh My Zsh + tema bira
eval "$SETUP" --github      # git config + chave SSH + adicionar no GitHub
eval "$SETUP" --firefox     # privacidade + Bitwarden
eval "$SETUP" --vscode      # settings + extensões
eval "$SETUP" --claude      # claude-config (skills e settings)
```

### Logins

```bash
eval "$SETUP" --tailscale   # autentica Tailscale
eval "$SETUP" --discord     # abre Discord para login
eval "$SETUP" --steam       # abre Steam para login
```

---

## Estrutura

```
machine/
  setup.sh                # script principal
  vscode-settings.json    # settings do VSCode
  vscode-extensions.txt   # lista de extensões

ssh/                      # configs de SSH
sshpilot/                 # configs do sshpilot
```

---

## Observações

- Execute como **usuário comum**, não como root
- `--github` pausa e aguarda você adicionar a chave SSH no GitHub antes de continuar
- `--firefox` requer que o Firefox tenha sido aberto ao menos uma vez
- Reinicie o terminal após `--terminal` para o zsh ser aplicado
- `--vscode` baixa os arquivos de configuração diretamente do repositório quando executado via curl
