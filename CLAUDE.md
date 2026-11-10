# IaGo — memória do projeto

Contexto compartilhado por todos os agentes. Mantenha curto (menos de 200 linhas) e atualizado.

## Sobre

**IaGo** (Inteligência Artificial de Gerenciamento e Organização de Estudos). Grupo: Caio Peixoto, Fred, João Ricardo, Luiz e Nicolas. O Fred roda e revisa o código. **Prioridade: o MVP de sexta, 27/11/2026**, conforme a spec [`docs/specs/mvp-27-11.md`](docs/specs/mvp-27-11.md), aprovada em 07/11: os três pilares em forma mínima, estáveis em web e Android, para um piloto fechado. Um protótipo menor e estável vale mais que um grande e frágil. Se faltar prazo, siga a ordem de corte da spec, nunca corte os itens "nunca cortar" e avise o Fred.

**Congelamento de funcionalidades:** terça, 24/11, às 20h. Depois, só correção de bugs. O site e o APK do beta só mudam na publicação do MVP (26/11). **Histórico:** o Beta 0.1 (só o Agrega) foi apresentado em 06/11, com congelamento em 05/11; o roteiro dele vale como teste de regressão até a tarefa O2 do MVP.

**Diretriz do Fred (03/11):** nada de estrutura robusta de servidor. O backend é o mais simples possível: Firebase Auth + Firestore com regras por usuário, sem Cloud Functions, sem Storage, sem scripts de admin. **Exceções aprovadas em 07/11:** acervo próprio só de leitura, como asset do app; script local de importação (`tool/acervo/`, só na máquina de desenvolvimento, sem tocar produção); e IA chamada do cliente (Firebase AI Logic com App Check), sem servidor e sem chat.

### Produto em uma tela

- **Tese:** o problema do estudante não é falta de informação, é falta de autocontrole.
- **Pilares:** Agrega · Direciona · Conecta. O beta tem só o Agrega; o MVP tem os três em forma mínima.
- **Persona:** Pedro, 18 anos, vestibulando que dá aula de reforço. Pouco tempo, dinheiro e energia.
- **Regras de design:** nenhum número solto (sempre contra a semana anterior, a média ou a meta); gratuito; nada de recompensa em dinheiro; segurança dos dados é pré-requisito.
- **Não é/não faz:** chat, ensino, gabarito, correção, geração de questões, scraping. Banco de questões, só o acervo de leitura aprovado no MVP (ENEM, sem gabarito). A IA só extrai questões de arquivos e propõe etapas de estudo.
- Referências em `docs/referencia/`: fora do git e não públicas (material do grupo, livro e roteiros). Não copie trechos, números nem nomes de lá para o repositório, que é público.

### Roteiro da demo

- **MVP:** [DEMO.md](DEMO.md), seções 1 a 7 (Painel, colagem, importação, acervo, Direciona, Conecta e métricas). Os números da busca estão nos testes: `test/data/demo_seed_test.dart` e `test/widget/questions_flow_test.dart`.
- **Regressão do beta:** seção própria do DEMO.md. Vale até a O2 ser fechada.

## Stack

- Frontend/mobile: Flutter 3.47.9 stable (Dart 3.13.7), Riverpod 3.4, go_router 18.
- Backend: sem servidor próprio; Firebase Auth e Hosting (plano Spark). No MVP, IA pelo Firebase AI Logic (Gemini), com App Check.
- Banco de dados: Cloud Firestore (`southamerica-east1`).
- CI/CD: GitHub Actions (`.github/workflows/ci.yml`), em push para `main` e `feat/**`.

## Comandos

```bash
flutter pub get                      # instalar dependências
flutter analyze                      # lint: precisa sair "No issues found!"
flutter test                         # unitários + widget
flutter run -d chrome                # desenvolvimento na web
flutter build web --release --no-web-resources-cdn
python -m http.server 8765 --bind 127.0.0.1 --directory build/web   # serve o build
# Firebase local (emuladores, sem conta):
firebase emulators:start --only auth,firestore --project demo-iago
flutter run -d chrome --dart-define-from-file=env/emulator.json
# Testes das regras do Firestore, todos, como no CI (cd firestore-tests && npm install na 1ª vez):
firebase emulators:exec --only firestore --project demo-iago "node --test firestore-tests/*.test.mjs"
# Firebase de verdade, com IA (env/*.json fora do git; modelo em env/firebase.example.json):
flutter run -d chrome --dart-define-from-file=env/firebase.json --dart-define-from-file=env/appcheck-debug.json
# Capturas a 360 px, bloqueando pedidos externos (prova de offline):
cd tool/screenshots && npm install && node drive.js http://127.0.0.1:8765/ shots "click:Entrar como Pedro" "shot:painel"
```

- **Token de depuração do App Check:** só em `env/appcheck-debug.json`. Nunca em `env/firebase.json`, no secret `FIREBASE_ENV_JSON` (que vai embutido no site público), no git ou no chat. O build de publicação usa só `--dart-define-from-file=env/firebase.json`.
- **Console** (Firebase, Google Cloud e AI Studio): o Fred segue o guia [`docs/guias/p2-console.md`](docs/guias/p2-console.md), em três partes (P2a, P2b e P2c).

Passos do `drive.js`:

- `click:<texto>`: toca pelo rótulo de acessibilidade. `newtab:<texto>`: toca e confirma que abriu uma aba nova. `download:<texto>|<arquivo>`: toca e salva o download (por exemplo, o PDF).
- `field:<rótulo>`: foca um campo de texto. O clique por coordenada **não** foca input no Flutter web. `type:<texto>`: digita. `paste:<texto com \n>`: cola de uma vez, como Ctrl+V.
- `scroll:<px>`, `wait:<ms>`, `shot:<nome>`, `reload` (recarrega a página), `dump` (lista a árvore de semântica) e `focus` (mostra o elemento focado). `RECORD_VIDEO` grava o roteiro em vídeo (plano B e checkpoints).
- `ALLOW_HOSTS` (por sufixo) libera hosts para testar contas: `www.gstatic.com,googleapis.com`; com IA e App Check, também `www.google.com`. Detalhes no topo do `drive.js`.

## Estrutura

- `lib/domain`: modelos e regras puras. `lib/data`: interfaces + `local/` (em memória) e `firebase/`. `lib/features`: telas. `lib/shared`: widgets. `lib/app`: tema, rotas, bootstrap. `lib/core`: utilitários.
- `test/`: testes Flutter. `firestore-tests/`: testes das regras. `tool/`: fontes, ícones e capturas (`screenshots/drive.js`).
- `android/`, `web/`, `assets/`: plataformas e recursos. `env/`: configuração do Firebase (`*.json` fora do git, exceto os modelos e o do emulador).
- `docs/demo/`: vídeo, capturas e PDF do plano B. `docs/referencia/`: referências (fora do git). `DEMO.md`: roteiro do ensaio.
- `docs/specs/`, `docs/decisoes/` e `docs/guias/`: artefatos dos agentes (spec do MVP, ADRs e guia do console), criados quando forem necessários.

## Convenções

- Nomes no código em inglês; interface, commits e documentação em português.
- Commits no padrão Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`), pequenos e por fatia. Os commits antigos usam outro prefixo (`Docs:`, `CI:`).
- Branches: `feat/<slug>` e `fix/<slug>`. No MVP: `feat/mvp` (base) e `feat/mvp-<trilha>`.
- `flutter analyze` sem avisos e `flutter test` verde antes de cada commit. Autor local: Fred <frediro1910@gmail.com>.

## Time de agentes

O agente principal da sessão é o `orquestrador` (configurado em `.claude/settings.json`). Ele conversa com o usuário e delega aos especialistas em `.claude/agents/`: arquiteto, backend, frontend, qa, revisor, devops e documentador.

Se você é um especialista: trabalhe só no briefing (você não vê a conversa com o usuário); dúvidas que só o usuário responde vão para "Pendências e riscos"; use `docs/specs/` e `docs/decisoes/` como artefatos compartilhados; se briefing e spec se contradizem, aponte no relatório e, se a escolha for arriscada, pare antes de implementar.

## Relatório padrão

Todo especialista termina com:

- **Resumo:** o que foi feito, em 2 a 5 linhas
- **Arquivos alterados:** caminho e o que mudou em cada um
- **Verificação:** comandos executados e resultado (testes, lint, build)
- **Suposições:** o que foi decidido sem informação explícita
- **Pendências e riscos:** o que ficou faltando, dúvidas para o usuário, cuidados no deploy
- **Próximo passo sugerido**

## Regras gerais

- Nunca commitar segredos; `.env` fica fora do git (mantenha um `.env.example` atualizado).
- Nada de commit, push, merge, deploy ou exclusão de arquivos e branches sem pedido explícito do usuário. Única exceção: o orquestrador, no MVP, dentro da autorização de 07/11 (veja "MVP (07/11)" abaixo).
- Mudanças focadas no escopo; sugestões fora do escopo vão no relatório.
- Não invente resultados: se algo não foi verificado, diga.

## Decisões tomadas

- **MVP (07/11)**, pela spec [`docs/specs/mvp-27-11.md`](docs/specs/mvp-27-11.md) e pelos ADRs 0001 a 0005 em `docs/decisoes/`:
  - **D1 a D5 aprovadas:** contas reais e piloto para maiores de 18, com IA e Conecta só para membros com convite (D1); camada gratuita do Gemini, com aviso e minimização (D2); gabarito descartado (D3); texto do ENEM no app e no repositório, com crédito e canal de remoção, e o script local (D4); `gemini-3.5-flash-lite` como modelo padrão (D5). D5 vale se as cotas se confirmarem. D6, D7, D9 e D10 estão abertas: vale a recomendação da spec, sem bloquear a implementação.
  - **Toda limitação é reversível:** mora num ponto único (política de acesso em `lib/domain/access_policy.dart`, alimentada por `appConfig/runtime`; flag; regra nomeada; adaptador; script), nunca espalhada por telas e repositórios. IA por portas no domínio (`QuestionExtractor` e `StepProposer`), com `firebase_ai` só em `lib/data/ai/gemini/`; acervo só pela interface paginável `BankCatalog`, com ids estáveis prefixados pela fonte. Tabela e critérios CA-R1 a CA-R7 em [Como desfazer as limitações](docs/specs/mvp-27-11.md#como-desfazer-as-limitações).
  - **Conecta:** construído completo, mas desligado em conta real (`conectaEnabled=false`) até a D6 (moderadores, CA-C11). Na demo, funciona com conteúdo simulado.
  - **Processo autônomo (D8):** cada parte só fica pronta com `flutter analyze` limpo, `flutter test` e testes de regra verdes, aprovação do `qa`, `revisor` sem nada CRÍTICO ou ALTO e CI verde no push. No máximo 2 ciclos de correção; depois, o impasse vai ao Fred. O Fred só entra no P2, nos checkpoints CP0 a CP3 (até 15 min cada), no teste no celular (Q2), na publicação do Hosting e nas decisões. Sem resposta dele até o horário do checkpoint (de Brasília): se o `qa` aprovou, segue; se não, vale a ordem de corte. O corte 9 (IA no Direciona) nunca é automático.
  - **Commits:** o Fred autorizou commit e push só nas branches `feat/mvp*`, depois que `qa` e `revisor` aprovarem cada parte, e merge só entre essas branches, com `C:\IaGo` livre de agentes. Quem faz é o **orquestrador**; os especialistas não fazem commit. Merge em `main`, deploy e release continuam dependendo do OK do Fred.
  - **Branches:** base `feat/mvp`. Fase 1 nela, com um agente por vez em `C:\IaGo`. Trilhas da Fase 2 em `feat/mvp-<trilha>`, cada uma numa worktree ignorada pelo git (`C:\IaGo\.worktrees\<trilha>`), mescladas pelo orquestrador. Testes de regra, uma worktree de cada vez (portas fixas do emulador).
- **MVP, em `feat/mvp` (09/11):**
  - **Avaliação só para membros (AV2):** resumo e avaliação do acervo são para membros; fora do piloto, a tela mostra "Entrar no piloto" (`rating_panel.dart`). Na demo, são dados simulados. Ver [seção 6](docs/specs/mvp-27-11.md#6-avaliação-pelos-usuários).
  - **Exclusão em cascata (C5):** apaga também o Conecta (posts, respostas, "Ajudou", denúncias, limites) e as avaliações (`questionRatings`). Ver [CA-T7](docs/specs/mvp-27-11.md#critérios-de-aceite).
  - **`Source.server` na exclusão:** inventário e subcoleções são lidos do servidor, para não apagar só o que está no cache; sem fila offline e com timeout de 30 s (`firebase_auth_repository.dart`).
  - **Membro sem Conecta (10/11):** virar membro do piloto (convite + e-mail verificado) não depende de `conectaEnabled`: pela aba Conta e pelos avisos "Entrar no piloto" (`canOfferJoinProvider`, rota `/conecta/membro`). O fórum segue exigindo `conectaEnabled`. IA real: F5b, I3 e DI3 em `feat/mvp`; App Check ativado só quando conta real usa a IA, para a demo seguir offline.
- **Moderador só na demo:** "Ver como moderador (demonstração)" liga o papel em memória (`demoModeratorModeProvider`) e volta a desligado a cada sessão. Em conta real, o papel é `moderators/{uid}`. Ver [Conecta](docs/specs/mvp-27-11.md#2-conecta).
  - **Contato do projeto:** `AppInfo.projectContactEmail` ainda é `<e-mail do projeto>`, e `test/publish_ready_test.dart` está com `skip: true`. Antes de 26/11, trocar pelo e-mail da P4 e ligar o teste. Ver [CA-C11](docs/specs/mvp-27-11.md#critérios-de-aceite).
  - **`hadAcceptedListStep` em `list_exported`:** `true` se a lista saiu com uma etapa "Montar lista" aceita (H3). A H2 usa só listas sem questões do acervo (`bankQuestionCount`). Ver [métricas](docs/specs/mvp-27-11.md#métricas).
  - **Limites da importação:** 5 arquivos por vez, 10 MB cada e 30 questões por lote (`maxImportFiles`, `maxImportFileBytes`, `maxExtractedQuestions`). PDF até 10 páginas (`maxImportPdfPages`, contagem em `core/pdf_page_count.dart`, com teto contra bomba de compressão; sem contagem possível, recusa). Limite diário de IA `aiDailyPerUser` contado no aparelho (`data/ai/ai_daily_limit.dart`). Ver [seção 3](docs/specs/mvp-27-11.md#3-importação-em-lote).
- **Flutter:** o Material saiu do framework: use sempre `import 'package:material_ui/material_ui.dart';` e nunca `package:flutter/material.dart`, para não ter duas cópias de `Theme`. As localizações vêm de `GlobalMaterialLocalizations.delegates` do próprio `material_ui`.
- **Riverpod sem geração de código** (`Notifier`, `Provider`, `StreamProvider`). `Override` vem de `package:flutter_riverpod/misc.dart`. `AsyncValue.value` é anulável.
- **go_router** com `StatefulShellRoute.indexedStack` e 4 abas: Painel, Questões, Listas, Conta. O redirect depende de `sessionProvider`.
- **Demo:** `DemoSession` nova a cada entrada recria a seed em memória (`DemoStore`), o que garante estado limpo em todo ensaio. A seed (`lib/data/local/demo_seed.dart`) tem 40 questões originais (30 objetivas e 10 discursivas) e 2 listas, com datas relativas a "agora": 8 questões nos últimos 7 dias e 5 nos 7 anteriores. Esses números são invariantes testados em `test/data/demo_seed_test.dart`; ao mexer na seed, mantenha-os.
- **Busca:** feita no cliente, ignorando acentos, com o plural "-ões" reduzido a "-ão" (`core/text_normalizer.dart`). Assunto e plataforma são tags livres comparadas por `tagKey`.
- **Filtros:** OU dentro da mesma dimensão e E entre dimensões. Os contadores são facetas: cada um respeita os filtros das outras dimensões.
- **Colagem:** `domain/paste_parser.dart` separa as alternativas A–E do texto colado. Exige 4 ou mais itens em sequência, para não confundir os itens a) e b) das discursivas. O formulário detecta colagem quando o texto cresce 20 ou mais caracteres de uma vez. O aviso "N alternativas separadas" com "Desfazer" fica dentro do formulário, porque um snackbar cobria as sugestões.
- **Salvar em menos de 30 s:** o formulário cronometra da abertura ao salvar e mostra "Questão salva em N s (meta: menos de 30 s)". Assunto e plataforma têm sugestões tocáveis (`domain/suggestions.dart`); os assuntos se limitam à matéria escolhida.
- **Filtros na tela:** os chips usam `Wrap`, com tudo visível a 360 px (nada escondido em rolagem horizontal). O cabeçalho rola junto com a lista. Resultado com filtro aparece como "9 de 40 questões".
- **Excluir questão** também a retira das listas, via `ListRepository.removeQuestion`.
- **Listas:** há três jeitos de começar uma. Pelo filtro atual: "Montar lista com estas N questões", o caminho do roteiro. Pela seleção: segurar um cartão, ou o atalho "Montar lista" do painel ou "Nova lista". No editor: reordenar (`onReorderItem`, cujo índice já vem ajustado; `onReorder` está depreciado), remover, adicionar, renomear e excluir.
- **Tempo de montagem (H2):** `listAssemblyTimerProvider` começa na primeira busca, filtro ou seleção e grava `QuestionList.assemblyStartedAt` na criação. Zera ao criar a lista ou em "Limpar".
- **PDF** (`features/export/list_pdf.dart`):
  - A4, sem gabarito, com Nome/Data, numeração, (A)–(E) e 7 linhas nas discursivas.
  - Cada questão vai em `pw.Inseparable`, para não quebrar no meio da página. O enunciado usa `RichText(overflow: TextOverflow.span)`; sem isso, texto mais alto que uma página derruba o PDF. Se algo não couber, `buildListPdf` refaz sem agrupar.
- **Entrega do PDF** (`pdf_exporter.dart`):
  - Web: "Abrir PDF" abre um blob numa nova aba, e precisa rodar no toque, sem `await` antes. "Baixar PDF" baixa o arquivo.
  - Android: `layoutPdf` para visualizar ou imprimir e `sharePdf` para compartilhar. A exportação conta (`registerExport`), mas o arquivo não é guardado.
- **Painel:** janelas móveis de 7 dias (`domain/dashboard_summary.dart`), justas em qualquer dia, inclusive na segunda-feira. Para conta nova, um convite substitui os números zerados.
- **FABs com `heroTag: null`:** com `StatefulShellRoute.indexedStack`, todas as abas ficam na mesma rota, e a hero tag padrão repetida quebra a transição de saída.
- **Categorização:** área (4, padrão ENEM) → matéria (catálogo fixo) → assunto (1 tag livre, opcional). Matemática tem uma matéria só, que entra preenchida automaticamente.
- **Offline:** fonte Inter embutida (`assets/fonts`, gerada por `tool/build_fonts.py`), também usada no PDF. Build web com `--no-web-resources-cdn`, que embute o CanvasKit. Não usar `PdfPreview`, `Printing.raster` nem `Printing.info()` na web, porque baixam o pdf.js de CDN; `layoutPdf` e `sharePdf` funcionam sem rede. Nada de emoji na interface (o glifo viria de CDN).
- **Cloud Storage exige o plano Blaze desde 03/02/2026**, então fica de fora. A imagem vai compactada (até ~300 KB) para um documento separado do Firestore; na demo, fica na memória.
- **Config do Firebase fora do git:** `--dart-define-from-file=env/firebase.json` (e, para testar a IA em localhost, também `env/appcheck-debug.json`). Sem esse arquivo, o app roda só em modo demo.
- **Firebase, o mais simples possível** (fatia 5): Auth com e-mail e senha e Firestore com regras por usuário.
  - Inicialização em segundo plano, com timeout de 12 s (`data/firebase/firebase_bootstrap.dart`). Na web, o SDK vem do CDN gstatic; sem internet, o status fica `unavailable` e a demo segue normal.
  - A sessão **escuta** o Auth (`ref.listen`) e nunca derruba uma `DemoSession` ativa; há teste de widget para isso.
  - Os repositórios dependem de `dataOwnerProvider` (o `uid`), então mudar o nome não os recria. O Auth é lido via `userChanges()`, para o nome gravado no cadastro aparecer na hora.
  - Escritas no Firestore esperam no máximo 4 s (`commitOrQueue`): sem rede, ficam na fila e a tela não trava.
  - Modelo de dados: `users/{uid}`: perfil (nome, e-mail, `referralSource` da H4, `platformsBefore`, `termsVersion`, `termsAcceptedAt`); `/questions`, `/questionImages` (Blob até 350 KB), `/lists` e `/events`; `admins/{uid}`: criado no console. O MVP acrescenta coleções públicas e `appConfig/runtime` (veja a spec).
  - Excluir a conta (LGPD) pede a senha, reautentica, apaga as subcoleções e o perfil, e por fim o usuário do Auth. Mensagens de erro do Auth em português (`FirebaseAuthRepository.messageFor`).
- **Emuladores:** projeto `demo-iago`, que não precisa de conta nem login. Auth na porta 9099 e Firestore na **8085**: a 8080 está ocupada nesta máquina por outro programa. Na web, com emulador, o SDK tenta `accounts:lookup` em produção ao restaurar a sessão, porque isso acontece antes do `useAuthEmulator`. É inofensivo e só ocorre no emulador.
- **Métricas do piloto** (fatia 7, desejável):
  - Eventos em `users/{uid}/events` via `MetricsLogger`, que nunca trava a tela: `signed_up`, `question_saved` (segundos e `questionType`), `list_created`, `list_exported` (`assemblySeconds` na 1ª, `questionCount`, `exportIndex`, `bankQuestionCount`, `hadAcceptedListStep`), `active` (id `active-AAAA-MM-DD`, no máximo um por dia), `satisfaction` / `satisfaction_dismissed`. `MetricEvent.toMap` grava `type`/`at` por último, porque um dado chamado `type` já sobrescreveu o tipo uma vez.
  - Pesquisa de satisfação (0–10 + plataformas) uma vez, depois da 3ª exportação (`maybeAskSatisfaction`). Na demo, a seed tem 1 exportação, então a do roteiro não abre a pesquisa.
  - Tela `/metricas`: H1–H6 calculadas na hora (`domain/pilot_metrics.dart`), cada valor com a meta; H5 e H6 têm "meta provisória". Na demo: 20 usuários fictícios (`data/local/simulated_pilot.dart`) e a faixa "DADOS SIMULADOS"; retenção 38% e listas/semana 0,8 ficam abaixo da meta, de propósito. Nas contas: só admin (`admins/{uid}`, criado no console).
  - **Linha de base da H2: 30 min é provisório** (`realPilotParameters` em `features/metrics/metrics_providers.dart`). O grupo deve trocar pelo número das entrevistas.
- **Identidade visual** (sem o deck oficial): índigo `#4F46E5` com a variante `fidelity` do M3, selo Beta âmbar, logo com degradê fixo. Os tokens estão em `lib/app/theme.dart`.
- **Repositório e entrega:**
  - Público em [github.com/FredECI/IaGo](https://github.com/FredECI/IaGo), desde 03/11, para os colegas contribuírem; colaborador: `gh api -X PUT repos/FredECI/IaGo/collaborators/<usuario>`. O histórico foi varrido e não tem segredos.
  - O APK sai do CI (só ARM, `useLegacyPackaging`, 21 MB), com `FIREBASE_ENV_JSON` e assinatura fixa (`ANDROID_DEBUG_KEYSTORE`; SHA-256 `af704be4…e09d80`). Release `v0.1.0-beta`: `gh workflow run CI`, baixar `iago-apk` e `gh release upload v0.1.0-beta IaGo-Beta-0.1.apk --clobber`. O link direto não muda. O APK de `feat/mvp*` sai só pelo workflow manual `apk-manual.yml`.
  - O Spark recusa `.apk` no Hosting (projetos criados depois de 28/09/2023): não mude a extensão.
  - Secrets pelo Git Bash (`gh secret set X < arquivo`): o PowerShell grava BOM e `\r\n`. O modo automático bloqueia credenciais e deploy de Hosting; logins e `deploy --only hosting` ficam com o Fred.
- **Projeto Firebase real:** `iago-beta` (nº 958140378539), plano Spark, conta frediro1910@gmail.com. Firestore `(default)` em `southamerica-east1`, login por e-mail e senha, apps Web `1:958140378539:web:cc9bfd557bc11eed49f6ee` e Android `1:958140378539:android:71a8c5564031232949f6ee` (`br.ufrj.iago`). `env/firebase.json` (gerado com `apps:sdkconfig`) fica fora do git; `.firebaserc`: `default` = `iago-beta`, `demo` = `demo-iago`.
  - Verificado em 03/11 pelo `drive.js` em `localhost` (com `ALLOW_HOSTS=www.gstatic.com,googleapis.com`): cadastro, salvar, recarregar, sair e entrar, excluir conta, e o login falha depois. Para a CLI criar projetos, a conta precisa aceitar os termos do Firebase no console (senão, 403).

## Ambiente desta máquina (03/11)

- Flutter em `C:\Users\Fred\dev\flutter`, JDK 21 em `C:\Users\Fred\dev\jdk-21`, Android SDK em `%LOCALAPPDATA%\Android\Sdk` (só cmdline-tools; licenças não aceitas, e o APK sai do CI). Sem aparelho nem emulador Android: o teste no celular é do Fred.
- Firebase CLI 15.34.2 e GitHub CLI 2.103.3 (`C:\Users\Fred\dev\gh\bin`, logado como FredECI). No PowerShell, `firebase.cmd` (a política bloqueia o `.ps1`); FlutterFire CLI no Git Bash é `flutterfire.bat`. Em terminal antigo: `$env:Path = "$env:USERPROFILE\dev\flutter\bin;$env:USERPROFILE\dev\gh\bin;$env:Path"`.
- Chave de debug em `%USERPROFILE%\.android\debug.keystore` (senhas `android`), a mesma do secret `ANDROID_DEBUG_KEYSTORE`.

## Pendências do Fred (e o que fazer em seguida)

A lista completa, em ordem, está na spec: [Ações do Fred, em ordem](docs/specs/mvp-27-11.md#ações-do-fred-em-ordem). As próximas:

1. **P2a** pelo guia (cerca de 50 min), com prazo hoje, 09/11. Destrava a F1 e o CP0 de terça, 10/11, às 20h. Inclui o secret `FIREBASE_ENV_JSON` (F4). Depois: P2b (só para o APK) e P2c (antes de 26/11).
2. **Publicação (26/11):** `deploy --only firestore` (O1), com OK do Fred. Claude gera o build com `--dart-define-from-file=env/firebase.json`; o Fred roda `firebase.cmd deploy --only hosting --project iago-beta`. Para ver as métricas reais, criar `admins/{uid}` no console.
3. **Q2:** teste no celular (cerca de 30 min) com o APK candidato. **Ensaio:** seguir o [DEMO.md](DEMO.md); capturas e vídeo em `docs/demo/` são do beta e serão regenerados na O2, depois da IA.

## Status

| Fase | Situação |
| --- | --- |
| Beta 0.1 (fatias 1 a 8) | **Pronto (03/11)**: 97 testes Flutter e 6 de regras; demo offline e conta real verificadas a 360 px no site https://iago-beta.web.app; repositório público com CI verde; APK de 21 MB na release `v0.1.0-beta`, testado num celular em 04/11. O APK trocado em 05/11 (só o texto do card Conecta) ainda não foi testado no celular. Roteiro e plano B: [DEMO.md](DEMO.md) e `docs/demo/` |
| MVP de 27/11 | **Spec aprovada em 07/11.** Em 09/11, 26 commits em `feat/mvp`: F2, F3, F5a, F6, F7; acervo (A1, A3, A4, A5; 1.687 questões); avaliação (AV1, AV2); colagem (I1, I2, I4); Direciona (DI1, DI2, DI4); Conecta (C1 a C6); métricas H1 a H6 (M1). Pendentes: P2a (Fred, hoje), F1, F5b, I3, I5, DI3, DI5, A2, A6, Q1 a Q4, O1 e O2 (falta o vídeo). Próximo: P2a e CP0, terça, 10/11, às 20h |
