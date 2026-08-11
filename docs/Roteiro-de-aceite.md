# Roteiro de aceite — a passada do operador (issue #26)

O critério é o da antessala: o processo te conduz do zero ao fim **sem atrito**. Atrito = qualquer momento em que você teve que parar e pensar "e agora?", abrir outro terminal para investigar, ou consertar algo à mão. **Anote cada um** — atrito anotado é o dado do aceite; a nota vai na issue #26.

## 0. Preparação (fora da VM)

```bash
ssh root@proxmox 'qm rollback 303 recem-formatado && qm start 303'
```

Console: web do Proxmox → VM 303 → login `makina` / `bootstrap`.
**Confira de brinde o prometido da VM**: deixe-a parada uns minutos — ela **não pode** suspender nem apagar a tela sozinha.

## 1. O comando mínimo (o seed)

Num terminal da VM:

```bash
BOOTSTRAP_REF=develop bash <(curl -fsSL https://raw.githubusercontent.com/StayneDev/bootstrap-workstation/develop/machine/setup.sh)
```

- [ ] O menu de perfis aparece com os 4 (infra / minimo / pessoal / profissional)
- [ ] Escolha **`pessoal`** (é o que exercita tudo) — ele pergunta `git_name` e `git_email` **uma vez** e mais nada
- [ ] A partir daqui, até a fase 3, ele **não deve te perguntar nada** — se perguntar, é atrito

## 2. Fase 1 — provisionar (a mais longa; café)

- [ ] Banner `FASE 1/4 — PROVISIONAR` visível, rótulos `[provisionar]` nos passos
- [ ] Ao fim, spot-checks num segundo terminal:

```bash
git --version && zsh --version && flatpak --version        # base
flatpak list --app | grep -Ei 'discord|steam'              # camada pessoal
ls ~/.nvm/versions/node/*/bin/claude                       # claude code instalado
command -v brave-origin || command -v brave-browser-origin  # Brave Origin
```

## 3. Fase 2 — configurar

- [ ] `cat ~/.zshrc | head -3` mostra oh-my-zsh + tema bira
- [ ] Firefox abriu para criar o perfil; depois de fechá-lo o script **seguiu sozinho** (a espera ativa é de até 90s — se travou além disso, atrito)
- [ ] `find ~/snap/firefox/common/.mozilla/firefox ~/.mozilla/firefox -name user.js 2>/dev/null` — o user.js de privacidade está no perfil

## 4. Fase 3 — autenticar (interativa por natureza; **o Bitwarden é o pivô**)

Esta fase é a espinha do teste, porque tudo que vem depois autentica a partir dela:

- [ ] **Bitwarden prestando**: o Firefox abre, o ícone do Bitwarden está na toolbar (ou a página da AMO abre para 1 clique); login com a senha mestre funciona; **o cofre sincroniza** e a credencial do GitHub está lá dentro, utilizável
- [ ] **Chave SSH → GitHub**: a chave aparece na tela **e no clipboard**; o browser abre em github.com/settings/keys; você loga no GitHub **usando o Bitwarden** (é aqui que ele prova que presta); cola a chave; o script **testa a conexão sozinho** e diz `[OK] GitHub autenticado`
- [ ] **Tailscale**: o fluxo da auth key te conduz (gera no admin, cola no prompt) e fecha com `[OK] Tailscale conectado`
- [ ] **Claude login**: o fluxo de auth da Anthropic abre e conclui
- [ ] Discord e Steam abrem para login (pode pular o login em si — o que se testa é a condução)

**Teste do dente (opcional, vale ouro)**: se você rodar `bash setup.sh --fase fechar` ANTES de completar a auth, ele deve **recusar na entrada** dizendo `autenticar incompleto — rode antes: bash setup.sh --fase autenticar`. Recusa mal explicada = atrito.

## 5. Fase 4 — fechar (o orquestrador chega)

- [ ] Clona os dois repos privados sem pedir nada (a auth da fase 3 sustenta)
- [ ] O `install.sh` roda e **verifica**: todos os `[ok]`, incluindo "9 ganchos ligados", "verificador-de-maquinaria passa"
- [ ] A **conferência final** roda sozinha e fecha: `── [pessoal] confere: tudo que o manifesto declara está na máquina ──`

## 6. Claude funcionando COM o orquestrador (o fim da linha)

Abra um **terminal novo** (para o zsh e o PATH do nvm valerem):

```bash
claude --version                                            # o binário responde
grep -c 'O.N.A/scripts/' ~/.claude/settings.json   # espera: 7
ls -la ~/repos/orquestrador-normativo-agente/sistema  # symlink → maquinaria
bash ~/repos/orquestrador-normativo-agente/scripts/verificador-de-maquinaria.sh
bash ~/Documentos/repos/O.N.A/scripts/verificador-de-forma.sh
```

- [ ] Verificadores verdes
- [ ] Abra o `claude` em qualquer pasta: a **primeira mensagem da sessão** deve vir com o bloco do ORQUESTRADOR injetado (o carregador rodou no SessionStart)
- [ ] Prova da trava viva: peça ao Claude para editar um nó de domínio do vault afirmando um fato — a **trava de medição** deve interceptar pedindo o comando que prova

## 7. Idempotência (o retry que aprovamos)

```bash
cd ~ && BOOTSTRAP_REF=develop bash <(curl -fsSL https://raw.githubusercontent.com/StayneDev/bootstrap-workstation/develop/machine/setup.sh)
```

- [ ] **Não pergunta nada** (lê as respostas gravadas) e o que está feito diz "ok"/já instalado — rápido, sem refazer trabalho

## 8. Os outros perfis (amostragem)

Rollback e um segundo giro enxuto prova a composição:

```bash
ssh root@proxmox 'qm rollback 303 recem-formatado && qm start 303'
# na VM: o mesmo comando mínimo, escolhendo `minimo` ou `profissional`
```

- [ ] `profissional` NÃO instala Discord/Steam; `minimo` não instala Java/VSCode
- [ ] `bash setup.sh --conferir` fecha verde para o perfil escolhido

## Veredito

Tudo acima sem atrito → **entregue** (feche a #26 com a nota). Qualquer atrito → anota na #26 com o passo e o que você esperava — vira conserto antes do aceite.
