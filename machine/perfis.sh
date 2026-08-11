#!/usr/bin/env bash
# perfis.sh — manifestos, respostas, execução por perfil e conferência (issues #21, #22, #24).
# Carregada pelo setup.sh via source. Perfil é DADO (perfis/*.perfil), não código.
#
# Formato do manifesto:
#   herda <perfil>            — composição em camadas; o herdado vem primeiro
#   passo <fase> <nome>       — fase ∈ provisionar|configurar|autenticar|fechar
#   divergente <chave>        — chave que diverge entre camadas: pergunta-se UMA vez
#
# Interativo UMA VEZ (U8): respostas colhidas no início vão para o arquivo de
# respostas; re-execução lê e não pergunta. --perfil X é o caminho headless.

PERFIS_DIR="${PERFIS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/perfis}"
RESPOSTAS="${RESPOSTAS:-$HOME/.config/bootstrap-workstation/respostas}"

# ── manifesto → passos (resolve herança, preserva ordem, deduplica) ──────────
resolver_perfil() { # $1=nome → linhas "fase nome"
  local nome="$1" arq="$PERFIS_DIR/$1.perfil" linha
  [ -f "$arq" ] || { echo "[perfil] '$nome' não existe em $PERFIS_DIR (tem: $(ls "$PERFIS_DIR" 2>/dev/null | sed 's/.perfil//' | tr '\n' ' '))" >&2; return 1; }
  while IFS= read -r linha; do
    case "$linha" in
      herda\ *)       resolver_perfil "${linha#herda }" || return 1 ;;
      passo\ *)       echo "${linha#passo }" ;;
    esac
  done < "$arq" | awk '!vistos[$0]++'
}

divergentes_do_perfil() { # $1=nome → chaves (com herança)
  local arq="$PERFIS_DIR/$1.perfil" linha
  [ -f "$arq" ] || return 1
  while IFS= read -r linha; do
    case "$linha" in
      herda\ *)      divergentes_do_perfil "${linha#herda }" ;;
      divergente\ *) echo "${linha#divergente }" ;;
    esac
  done < "$arq" | awk '!vistos[$0]++'
}

# ── respostas: colhe uma vez, grava, re-execução não pergunta ────────────────
resposta() { # $1=chave → valor (vazio se não gravada)
  [ -f "$RESPOSTAS" ] && awk -F= -v k="$1" '$1==k{print substr($0,length(k)+2); exit}' "$RESPOSTAS"
}

grava_resposta() { # $1=chave $2=valor — idempotente, sobrescrita reporta alto
  mkdir -p "$(dirname "$RESPOSTAS")"
  touch "$RESPOSTAS"
  local atual; atual=$(resposta "$1")
  [ "$atual" = "$2" ] && return 0
  [ -n "$atual" ] && echo "  [respostas] sobrescrevendo $1: '$atual' → '$2'"
  { grep -v "^$1=" "$RESPOSTAS" 2>/dev/null; echo "$1=$2"; } > "$RESPOSTAS.tmp" && mv "$RESPOSTAS.tmp" "$RESPOSTAS"
}

colher_divergentes() { # pergunta só o que ainda não tem resposta
  local chave valor
  for chave in $(divergentes_do_perfil "$1"); do
    [ -n "$(resposta "$chave")" ] && continue
    read -rp "  $chave: " valor
    grava_resposta "$chave" "$valor"
  done
}

# ── menu: a interação acontece AQUI, uma vez, nunca ao longo do run ──────────
menu_perfil() {
  local escolhido; escolhido=$(resposta perfil)
  if [ -n "$escolhido" ]; then
    # `>&2` porque o VALOR desta função é capturado com $( ) pelo dispatch: em
    # stdout, a mensagem virava parte do nome do perfil e a SEGUNDA execução do
    # script morria com "'<mensagem>\npessoal' não existe". Toda a interação
    # abaixo já vai para stderr — só esta linha ficara de fora, e era a única no
    # caminho da re-execução, que é justamente o que o README promete ser seguro.
    echo "[perfil] respostas existentes: perfil '$escolhido' ($RESPOSTAS) — não pergunto de novo (U8)" >&2
    echo "$escolhido"; return 0
  fi
  echo "" >&2
  echo "  Perfis disponíveis:" >&2
  local i=1 nomes=()
  local p
  for p in "$PERFIS_DIR"/*.perfil; do
    nomes+=("$(basename "$p" .perfil)")
    echo "    $i) $(basename "$p" .perfil)" >&2
    i=$((i+1))
  done
  local n
  read -rp "  Escolha o perfil [1-${#nomes[@]}]: " n
  [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#nomes[@]} ] \
    || { echo "[perfil] escolha inválida: '$n'" >&2; return 1; }
  escolhido="${nomes[$((n-1))]}"
  grava_resposta perfil "$escolhido"
  echo "$escolhido"
}

# ── executor: roda as 4 fases restritas ao manifesto, com os gates de fase ───
passos_da_fase() { # $1=perfil $2=fase
  resolver_perfil "$1" | awk -v f="$2" '$1==f{print $2}'
}

executa_passo() { # nome lógico → função concreta
  case "$1" in
    base)          detect_distro; install_base ;;
    node_claude)   install_node_and_claude ;;
    java)          detect_distro; install_java ;;
    sshpilot)      detect_distro; install_sshpilot ;;
    discord)       install_discord ;;
    steam)         install_steam ;;
    brave_origin)  detect_distro; install_brave_origin ;;
    terminal)      setup_terminal ;;
    vscode)        setup_vscode ;;
    firefox)       setup_firefox ;;
    login_firefox) login_firefox ;;
    git_ssh)       setup_git_ssh ;;
    claude_login)  login_claude ;;
    login_discord) login_discord ;;
    login_steam)   login_steam ;;
    tailscale)     login_tailscale ;;
    claude_config) install_claude_config ;;
    clone_infra)   clone_infra ;;
    *) echo "[perfil] passo desconhecido no manifesto: $1" >&2; return 1 ;;
  esac
}

rodar_perfil() { # $1=nome — headless se as respostas já existem
  local perfil="$1" fase passo
  resolver_perfil "$perfil" >/dev/null || return 1
  colher_divergentes "$perfil"
  local gates=("" gate_provisionado gate_configurado gate_autenticado)
  local fases=(provisionar configurar autenticar fechar)
  local i=0
  for fase in "${fases[@]}"; do
    local passos; passos=$(passos_da_fase "$perfil" "$fase")
    [ -z "$passos" ] && { i=$((i+1)); continue; }
    [ -n "${gates[$i]:-}" ] && { ${gates[$i]} || return 1; }
    echo -e "\n══════ [$perfil] FASE $((i+1))/4 — ${fase^^} ══════"
    for passo in $passos; do executa_passo "$passo" || return 1; done
    i=$((i+1))
  done
  conferir_perfil "$perfil"
}

# ── conferência (#24): declarado × real, por passo, falha nomeada (U2) ───────
prova_passo() { # o comando que PROVA cada passo — instalado não é rodado, é constatável
  case "$1" in
    base)          command -v git &>/dev/null && command -v zsh &>/dev/null && command -v flatpak &>/dev/null ;;
    node_claude)   [ -d "$HOME/.nvm" ] && { command -v claude &>/dev/null || ls "$HOME"/.nvm/versions/node/*/bin/claude &>/dev/null; } ;;  # nvm não está no PATH de shell não-interativo (achado do dev-QA)
    java)          command -v java &>/dev/null ;;
    sshpilot)      command -v sshpilot &>/dev/null || flatpak list --app 2>/dev/null | grep -q sshpilot ;;
    discord)       flatpak list --app 2>/dev/null | grep -q com.discordapp.Discord ;;
    steam)         flatpak list --app 2>/dev/null | grep -q com.valvesoftware.Steam ;;
    brave_origin)  command -v brave-origin &>/dev/null || command -v brave-browser-origin &>/dev/null ;;
    # o shell de LOGIN entra na prova porque era exatamente o que faltava: o
    # chsh falhava por PAM, o passo imprimia [OK] e a conferência dizia "ok"
    # com o usuário ainda em bash (aceite #26, 2026-08-02).
    terminal)      [ -d "$HOME/.oh-my-zsh" ] && [ -f "$HOME/.zshrc" ] \
                   && [ "$(getent passwd "$USER" | cut -d: -f7)" = "$(command -v zsh)" ] ;;
    vscode)        [ -f "$HOME/.config/Code/User/settings.json" ] ;;
    firefox)       [ -n "$(_firefox_profile)" ] ;;
    login_firefox) return 0 ;;  # login é do operador — não constatável sem a conta
    # `</dev/null` NÃO é decoração: prova_passo roda dentro do `while read` de
    # conferir_perfil, e o ssh lê stdin — sem isto ele ENGOLE o resto da lista de
    # passos e o loop termina aqui. A conferência checava 6 de 14 passos do
    # `pessoal` e ainda assim imprimia "confere: tudo" (aceite #26, 2026-08-02).
    git_ssh)       ssh -T git@github.com -o StrictHostKeyChecking=no -o BatchMode=yes </dev/null 2>&1 | grep -q "successfully authenticated" ;;
    # DEIXOU de ser cego: `claude auth status` sai em JSON com `loggedIn`, então
    # o login do Claude é constatável como qualquer outro passo. Era `return 0`
    # incondicional sob a justificativa "login é do operador" — verdadeira para
    # Bitwarden, Discord e Steam, falsa para este (aceite #26, 2026-08-03).
    claude_login)  command -v claude &>/dev/null \
                   && claude auth status </dev/null 2>/dev/null | grep -q '"loggedIn": *true' ;;
    login_discord) return 0 ;;  # idem
    login_steam)   return 0 ;;  # idem
    tailscale)     tailscale status &>/dev/null ;;
    claude_config) [ -d "$HOME/Documentos/repos/O.N.A/.git" ] ;;
    clone_infra)   [ -d "$HOME/Documentos/repos/bootstrap-infra/.git" ] ;;
    *) return 1 ;;
  esac
}

conferir_perfil() { # $1=nome → conferência completa; sai 1 com divergência
  local perfil="$1" falhas=0 linha fase passo
  echo -e "\n══════ [$perfil] CONFERÊNCIA — declarado × real ══════"
  # A lista é materializada ANTES do loop, de propósito. Alimentar o `while read`
  # por stdin punha a lista e as provas disputando o mesmo descritor: bastava uma
  # prova que lê stdin (o ssh do git_ssh) para engolir os passos seguintes, e o
  # loop terminava cedo declarando sucesso — cego para 8 dos 14 passos do
  # `pessoal`. Com array, prova que lê stdin não tem como truncar a conferência.
  local declarados=(); local n=0
  while IFS= read -r linha; do declarados+=("$linha"); done < <(resolver_perfil "$perfil")
  for linha in "${declarados[@]}"; do
    read -r fase passo <<<"$linha"
    [ -z "$passo" ] && continue
    n=$((n+1))
    if prova_passo "$passo"; then
      echo "  [ok]        $passo"
    else
      echo "  [DIVERGE]   $passo — declarado no perfil, não constatado na máquina"
      falhas=$((falhas+1))
    fi
  done
  echo ""
  # conferido × declarado: um número menor aqui é conferência cega, e cega é
  # pior que vermelha — ela aprova o que não olhou.
  if [ "$n" -ne "${#declarados[@]}" ]; then
    echo "── [$perfil] CONFERÊNCIA INCOMPLETA: $n de ${#declarados[@]} passos conferidos ──"
    return 1
  fi
  echo "  ($n de ${#declarados[@]} passos declarados foram conferidos)"
  if [ "$falhas" -eq 0 ]; then
    echo "── [$perfil] confere: tudo que o manifesto declara está na máquina ──"
  else
    echo "── [$perfil] $falhas divergência(s) — conserte e re-execute: o feito dirá 'ok' ──"
    return 1
  fi
}
