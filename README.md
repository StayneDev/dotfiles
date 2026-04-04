# dotfiles

> Setup pós-formatação para Arch, Debian/Ubuntu e Fedora.

## Status

`Produção`

## Stack

| Componente | Papel |
|---|---|
| Bash | Script de setup principal |
| Zsh + Oh My Zsh | Shell padrão (tema bira) |
| Flatpak | Apps universais (Discord, Steam, Firefox) |
| VSCode | Editor com settings e extensões versionadas |

## Pré-requisitos

- `curl` — pré-instalado na maioria das distros modernas
  - Fallback: `sudo apt install curl` / `sudo pacman -S curl` / `sudo dnf install curl`
- Usuário comum com `sudo` disponível — não executar como root

## Setup

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/StayneDev/dotfiles/main/machine/setup.sh)
```

O script detecta a distro automaticamente e executa tudo em sequência, incluindo a instalação do `git`.

### Módulos individuais

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

> `--github` pausa e aguarda você adicionar a chave SSH no GitHub antes de continuar.
> `--firefox` requer que o Firefox tenha sido aberto ao menos uma vez.
> Reinicie o terminal após `--terminal` para o zsh ser aplicado.

## Estrutura

```
machine/
  setup.sh                # script principal
  vscode-settings.json    # settings do VSCode
  vscode-extensions.txt   # lista de extensões

ssh/                      # configs de SSH
sshpilot/                 # configs do sshpilot
```

## Links

- [Issues](../../issues)
- [Roadmap](/opt/infra-backup/docs/roadmap.md)
