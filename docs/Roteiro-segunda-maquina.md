# Roteiro — segunda máquina (o orquestrador já existe)

> ## Migração obrigatória, para toda máquina instalada antes de 2026-08-05
>
> A divisão em dois repositórios foi revogada (`ADR-20260805-revogacao-do-par`). Máquina que já
> sincronizava **não quebra**, e é importante saber por quê antes de correr: ela puxa o monorepo
> normalmente (o GitHub redireciona o nome antigo), os ganchos continuam apontando para o clone
> antigo de `…-maquinaria`, que continua existindo no disco, e **os portões seguem funcionando**.
> O commit trivial passa — medido, não suposto.
>
> O que ela fica é **velha, com duas cópias da maquinaria, e a que roda não é a versionada.**
> Consequências reais, todas medidas em sandbox:
>
> - O `verificador-de-forma` acusa **2 nós bloqueados** que não são defeito: `template/README.md` e
>   `template/acervo/dominios/Exemplo/Exemplo.md`. A isenção de `template/` nasceu com a revogação e
>   o motor antigo não a tem. (O portão de **commit** só bloqueia se você colocar `template/` em
>   stage, o que não acontece em trabalho normal.)
> - Toda correção futura em `scripts/` chega pelo `git pull` e **não entra em vigor** — os ganchos
>   executam o clone antigo.
> - O `verificador-de-fato` vai **denunciar a máquina**, e isso é o sistema funcionando: dois `afere`
>   de `Desenvolvimento.md` esperam os 9 ganchos apontando para dentro e `core.hooksPath` relativo.
>   Numa máquina não migrada os dois divergem. **Divergência ali significa "esta máquina não
>   migrou"**, não "o nó mente".
> - O `sincronizador` antigo ainda empurra o clone de `…-maquinaria`. Se houver commit local lá, ele
>   vai para o repositório público congelado.
>
> ### A migração — três comandos, provados em sandbox com `HOME` isolado
>
> ```bash
> cd ~/Documentos/repos
> mv orquestrador-normativo-agente-acervo O.N.A
> rm -rf orquestrador-normativo-agente-maquinaria      # o clone antigo do motor; nada seu mora nele
> bash O.N.A/install.sh
> ```
>
> **Antes do `rm -rf`, conferir que nada seu mora no clone antigo:**
> `git -C orquestrador-normativo-agente-maquinaria status -sb` deve estar limpo e sem commit à
> frente do remoto. Se houver, decida o que fazer com ele primeiro — desambiguar antes de destruir.
>
> **O que provar depois:** o `install.sh` fecha com todos os `[ok]`, incluindo *"9 ganchos ligados"*
> e *"verificador-de-maquinaria passa"*; rodar de novo diz *"nada a fazer"* (U8); e
> `git config core.hooksPath` devolve `scripts/git-hooks` — relativo, não absoluto.

Este roteiro **não é a instalação**. A instalação já está construída e não se reescreve aqui (U1):
`machine/setup.sh` clona o orquestrador e chama o `install.sh` dele (`install_claude_config`),
e o [`Roteiro-de-aceite.md`](Roteiro-de-aceite.md) é a passada de aceite em VM virgem.

O que este documento cobre é o caso que nenhum dos dois cobre: **uma segunda máquina real do mesmo
operador, dividindo o mesmo acervo com a primeira.** Instalar é o problema resolvido; conviver não é.

---

## 1. O comando

Na máquina nova, um terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/StayneDev/bootstrap-workstation/main/machine/setup.sh)
```

No menu, escolher **`profissional`** — é `minimo` mais Java, VSCode, sshpilot, Brave e Tailscale,
sem Discord nem Steam. O par do orquestrador vem no `minimo`, então aparece em qualquer perfil.

Ele pergunta perfil e identidade git uma vez, grava em `~/.config/bootstrap-workstation/respostas`,
e roda as quatro fases. A fase 3 (autenticar) é interativa por natureza e o Bitwarden é o pivô: é
a partir dela que a chave SSH entra no GitHub, e é o SSH que sustenta o clone dos dois repos
privados na fase 4.

## 2. O que conferir ao fim

A fase 4 já roda o `install.sh`, que verifica sozinho. O que se confere à mão é só o que prova que
o orquestrador está **vivo**, não apenas instalado:

```bash
grep -c 'orquestrador-normativo-agente/scripts/' ~/.claude/settings.json   # espera 9
bash ~/Documentos/repos/orquestrador-normativo-agente/scripts/verificador-de-maquinaria.sh
bash ~/Documentos/repos/orquestrador-normativo-agente/scripts/verificador-de-forma.sh
```

Depois, num terminal novo, abrir o `claude`: a primeira mensagem tem de vir com o bloco do
ORQUESTRADOR injetado. Se não vier, o `SessionStart` não rodou e o resto é decoração.

> **Correção pendente:** o `Roteiro-de-aceite.md` §6 usa `~/repos/` nesses três comandos, mas o
> `setup.sh` clona em `$HOME/Documentos/repos`. Os comandos de lá falham como estão escritos.

## 3. A disciplina de duas máquinas

Esta é a parte que não existe em lugar nenhum, e é a que morde.

**O acervo é de escritor único.** O `sincronizador.sh` roda no `SessionStart` e faz
`git pull --ff-only` nos **dois** repos. Fast-forward apenas: se as duas máquinas editaram o vault
desde o último encontro, o pull falha, o hook **avisa alto e libera** — porque falha de mecanismo
nunca bloqueia — e você segue trabalhando sobre um acervo atrasado sem que nada o impeça.

**As travas são por clone.** Quando você edita `Charter.md` ou o `Esquema`, a trava de forma abre
uma obrigação de cascata em `registros/Dividas.md`. Essa obrigação é um arquivo. Se ela ficar sem
push, a outra máquina não sabe que existe e vai deixar você emendar outro nó-fonte — que é
exatamente o que o invariante 8 existe para impedir. O mesmo vale para o veredito e para o
semáforo de `main`: eles leem o disco local.

Daí as três regras, e nenhuma delas é mecanismo — são hábito, e estão escritas aqui por isso:

1. **Push antes de trocar de máquina.** Sempre, mesmo com trabalho pela metade. Branch local sem
   upstream é estado válido de trabalho e o sincronizador a ignora dizendo isso — o que significa
   que trabalho em branch local **não viaja**, e não avisa que não viajou.
2. **Abrir a sessão e ler o que o carregador diz.** Ele mostra obrigações abertas, vereditos
   pendentes e propostas dormindo. Se o pull falhou, o aviso está ali.
3. **Não fechar cascata em duas máquinas.** Abrir a obrigação numa e resolvê-la noutra produz duas
   metades que só se encontram no merge, e o merge não as reconcilia — ele só as junta.

**Estado no momento em que este roteiro foi escrito (2026-08-03):** o `develop` da maquinaria não
tem upstream configurado localmente, e há trabalho sem commit nos dois repos. Um clone feito agora
não traz nada disso. Conferir antes de instalar na outra máquina:

```bash
git -C ~/Documentos/repos/orquestrador-normativo-agente status -sb
git -C ~/Documentos/repos/orquestrador-normativo-agente status -sb
git -C ~/Documentos/repos/orquestrador-normativo-agente branch -vv
```

## 4. A decisão do `ORQ_RAIZ` — mesmo acervo ou acervo próprio

O endereço é variável, não constante: `ORQ_RAIZ` aponta onde o orquestrador mora, com default em
`$HOME/Documentos/repos`. Os 26 scripts do motor o respeitam e nenhum carrega caminho fixo. Isso
abre duas configurações, e a escolha é do operador.

**(a) Mesmo acervo, duas máquinas.** É o default. Você tem um vault só, e paga a disciplina da §3.
Serve quando as duas máquinas fazem o mesmo tipo de trabalho.

**(b) Acervo próprio na máquina nova, mesmo motor.** O motor traz `template/acervo/` — um acervo
semente com Charter, Home, Glossário, os registros e um domínio de exemplo, já verificável. A
máquina nova roda o mesmo motor sobre um acervo separado, com `ORQ_RAIZ` apontando para outro
lugar. Não há sincronização a manter, porque não há nada dividido.

A opção (b) é a que resolve o caso do trabalho de cliente: você leva a norma e as travas sem levar
o vault pessoal para dentro do workspace do cliente.

> **Atenção: (b) ficou mais cara em 2026-08-05, e o roteiro acima descreve o mundo anterior.** A
> divisão em dois repos foi revogada (`ADR-20260805-revogacao-do-par`), então "levar o motor sem o
> acervo" deixou de ser um clone e passou a exigir extração. A semente `template/acervo/` está
> **congelada** e as instruções dela mandam clonar um par que não existe — ver o banner em
> `template/README.md` do orquestrador. O caso do cliente continua real e continua sem resposta
> pronta; o que mudou é que ele voltou a custar trabalho de extração, e essa é a conta que a
> revogação aceitou pagar. O veredito do `ADR-20260730-estratos-e-extracao` fechou em **entregou em
> parte**: a semente chegou a rodar num sandbox em 02/08, com seis verificadores passando, mas o
> segundo acervo com conteúdo próprio nunca existiu.

## 5. O que medir para fechar o veredito

O `install.sh` **nunca rodou em máquina limpa na forma atual**, e já são três formas: a pré-corte
passou 5/5 na VM 303 em 2026-07-30; a do par (01/08 a 05/08) nunca foi testada e o próprio script
declarava isso nas linhas finais; a de repositório único nasceu em 2026-08-05 com a revogação do par
e é esta. Esta instalação é a primeira oportunidade de fechar isso, e o dado só existe se for
anotado no momento.

Anotar, durante a passada:

- [ ] O `setup.sh` conduziu do zero ao fim sem que você precisasse parar e pensar "e agora?"
- [ ] A fase 4 clonou o orquestrador sem pedir nada (a auth da fase 3 sustentou)
- [ ] O `install.sh` fechou com todos os `[ok]`, incluindo os 9 ganchos apontando para arquivo existente
- [ ] `verificador-de-maquinaria` e `verificador-de-forma` verdes **no clone novo**
- [ ] O carregador injetou o bloco do ORQUESTRADOR na primeira mensagem
- [ ] A trava de medição interceptou uma afirmação de fato sem comando que a prove
- [ ] Re-rodar o `install.sh` disse "nada a fazer, já estava instalado" (U8)

Cada atrito anotado vira conserto. Passada limpa fecha o `destrava:` do ADR de estratos e a issue
do aceite; passada com atrito é informação melhor ainda, porque é a primeira medição real.

## 6. O que este roteiro não faz

- Não instala nada por conta própria — o `setup.sh` é quem instala.
- Não cobre login do Claude Code, GitHub, Tailscale ou SSH: são fases do `setup.sh`.
- Não resolve divergência de git entre as duas máquinas. Quando o `ff-only` falhar, é trabalho
  manual, e deliberadamente: merge automático de vault é como duas verdades viram uma mentira.
