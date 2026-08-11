# bootstrap-workstation

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
- `tar` — parte do sistema base nas três distros; usado pelo one-liner para
  buscar os assets (`perfis/*.perfil`, dotfiles) que não viajam no stream
- Usuário comum com `sudo` disponível — não executar como root

## Setup

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/StayneDev/bootstrap-workstation/main/machine/setup.sh)
```

Sem argumento, o script abre o **menu de perfil** — pergunta tudo UMA vez no
início (perfil + chaves divergentes, ex.: identidade git), grava as respostas em
`~/.config/bootstrap-workstation/respostas` e roda sozinho as **4 fases** com
passagem verificada:

```
provisionar (públicos) → configurar → autenticar (interativa) → fechar (privados + conferência)
```

Re-executar é seguro e não pergunta de novo (idempotente): o que está feito diz
"ok", só o que falta roda. Fase sem pré-requisito recusa na entrada e diz o
comando que resolve.

### Perfis

| Perfil | O que entrega |
|---|---|
| `minimo` | base + terminal + o orquestrador clonado e ligado (aparece em todos) |
| `pessoal` | minimo + Discord, Steam, Brave Origin |
| `profissional` | minimo + Java, VSCode, sshpilot, Brave Origin — sem programas pessoais |
| `infra` | minimo + posto de controle da infra (clona o `bootstrap-infra` privado) |

Headless (sem menu): `bash setup.sh --perfil profissional` · conferência avulsa:
`bash setup.sh --conferir` · fase avulsa: `bash setup.sh --fase autenticar`.

## Teste em VM (aceite do operador)

A VM **303** (`ubuntu-bootstrap-teste`, Proxmox) existe para isto: Ubuntu 24.04
desktop recém-formatado, **sem suspensão/soneca**, com snapshot `recem-formatado`.

1. Voltar ao estado virgem (sempre que quiser recomeçar):
   `ssh root@proxmox 'qm rollback 303 recem-formatado && qm start 303'`
2. Abrir o console da VM na web do Proxmox → login `makina` / senha `bootstrap`.
3. Abrir um terminal na VM e rodar **o comando mínimo** (branch em teste):

```bash
BOOTSTRAP_REF=develop bash <(curl -fsSL https://raw.githubusercontent.com/StayneDev/bootstrap-workstation/develop/machine/setup.sh)
```

4. Escolher o perfil no menu e seguir a condução. O critério de entrega é o da
   antessala: o processo conduz até o fim **sem atrito** (ADR-20260801, Decisão).

### Módulos individuais

```bash
SETUP="bash <(curl -fsSL https://raw.githubusercontent.com/StayneDev/bootstrap-workstation/main/machine/setup.sh)"

eval "$SETUP" --base        # pacotes base (git, curl, zsh, VSCode, Tailscale)
eval "$SETUP" --flatpak     # Discord, Steam, Firefox via Flatpak
eval "$SETUP" --java        # JDK 21
eval "$SETUP" --node        # nvm + Node LTS + Claude Code
eval "$SETUP" --sshpilot    # sshpilot
eval "$SETUP" --terminal    # Zsh + Oh My Zsh + tema bira
eval "$SETUP" --github      # git config + chave SSH + adicionar no GitHub
eval "$SETUP" --firefox     # privacidade + Bitwarden
eval "$SETUP" --vscode      # settings + extensões
eval "$SETUP" --claude      # O.N.A — o vault (ganchos e settings)
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
