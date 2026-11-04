# IaGo Beta 0.1 — memória do projeto

Protótipo do **IaGo** (Inteligência Artificial de Gerenciamento e Organização de Estudos) para a apresentação em sala na **sexta, 06/11/2026**. Grupo: Caio Peixoto, Fred, João Ricardo, Luiz e Nicolas. O Fred roda e revisa o código.

**Prioridade absoluta:** o fluxo da demo funcionar de ponta a ponta, sem travar, online e offline. Um protótipo menor e estável vale mais que um grande e frágil. Se faltar prazo, corte do Desejável (nesta ordem: CI → métricas → deploy web), nunca do Obrigatório, e avise o Fred.

**Diretriz do Fred (03/11):** nada de estrutura robusta de servidor. O backend é o mais simples possível: Firebase Auth + Firestore com regras por usuário, sem Cloud Functions, sem Storage, sem scripts de admin.

**Congelamento de funcionalidades:** quinta, 05/11, às 20h. Depois, só correção de bugs.

## Produto em uma tela

- **Tese:** o problema do estudante não é falta de informação, é falta de autocontrole.
- **Pilares:** Agrega (este beta, registro manual) · Direciona e Conecta (só cards "Em breve").
- **Persona:** Pedro, 18 anos, vestibulando que dá aula de reforço. Pouco tempo, dinheiro e energia.
- **Regras de design:** nenhum número solto (sempre contra a semana anterior, a média ou a meta); gratuito; nada de recompensa em dinheiro; segurança dos dados é pré-requisito.
- **Não é/não faz:** chat, banco de questões, ensino, gabarito, correção, geração de questões, scraping.
- Fonte das referências: `docs/referencia/` (fora do git: canvas com "Confidencial" no rodapé, livro, roteiros).

## Fluxo da demo (menos de 2 min)

1. Abrir o app e tocar em "Entrar como Pedro (demonstração)".
2. Painel: resumo relativo da semana e cards "Em breve".
3. Salvar questão: colar uma objetiva (as alternativas A–E são separadas sozinhas), informar a plataforma e escolher Matemática → Funções.
4. Buscar "função" e filtrar por Matemática + Objetiva. A seed devolve 9; com a questão salva ao vivo, 10.
5. Montar a lista "Reforço — Funções" com as 10, exportar o PDF e abrir.
6. (Desejável) Métricas do piloto H1–H4 com "dados simulados".

## Decisões tomadas

- **Flutter 3.47.9 stable** (Dart 3.13.7). O Material saiu do framework: use sempre `import 'package:material_ui/material_ui.dart';` e nunca `package:flutter/material.dart`, para não ter duas cópias de `Theme`. As localizações vêm de `GlobalMaterialLocalizations.delegates` do próprio `material_ui`.
- **Riverpod 3.4 sem geração de código** (`Notifier`, `Provider`, `StreamProvider`). `Override` vem de `package:flutter_riverpod/misc.dart`. `AsyncValue.value` é anulável.
- **go_router 18** com `StatefulShellRoute.indexedStack` e 4 abas: Painel, Questões, Listas, Conta. O redirect depende de `sessionProvider`.
- **Camadas:** `lib/domain` (modelos e regras puras), `lib/data` (interfaces + `local/` em memória; `firebase/` virá na fatia 5), `lib/features` (telas), `lib/shared` (widgets), `lib/app` (tema, rotas, bootstrap), `lib/core` (utilitários).
- **Demo:** `DemoSession` nova a cada entrada recria a seed em memória (`DemoStore`), o que garante estado limpo em todo ensaio. A seed (`lib/data/local/demo_seed.dart`) tem 40 questões originais (30 objetivas e 10 discursivas) e 2 listas, com datas relativas a "agora": 8 questões nos últimos 7 dias e 5 nos 7 anteriores. Esses números são invariantes testados em `test/data/demo_seed_test.dart`; ao mexer na seed, mantenha-os.
- **Busca:** feita no cliente, ignorando acentos, com o plural "-ões" reduzido a "-ão" (`core/text_normalizer.dart`). Assunto e plataforma são tags livres comparadas por `tagKey`.
- **Filtros:** OU dentro da mesma dimensão e E entre dimensões. Os contadores são facetas: cada um respeita os filtros das outras dimensões.
- **Colagem:** `domain/paste_parser.dart` separa as alternativas A–E do texto colado. Exige 4 ou mais itens em sequência, para não confundir os itens a) e b) das discursivas.
  - O formulário detecta colagem quando o texto cresce 20 ou mais caracteres de uma vez.
  - O aviso "N alternativas separadas" com "Desfazer" fica dentro do formulário, porque um snackbar cobria as sugestões.
- **Salvar em menos de 30 s:** o formulário cronometra da abertura ao salvar e mostra "Questão salva em N s (meta: menos de 30 s)". Assunto e plataforma têm sugestões tocáveis (`domain/suggestions.dart`); os assuntos se limitam à matéria escolhida.
- **Filtros na tela:** os chips usam `Wrap`, com tudo visível a 360 px (nada escondido em rolagem horizontal). O cabeçalho rola junto com a lista. Resultado com filtro aparece como "9 de 40 questões".
- **Excluir questão** também a retira das listas, via `ListRepository.removeQuestion`.
- **Listas:** há três jeitos de começar uma.
  - Pelo filtro atual: "Montar lista com estas N questões", o caminho do roteiro.
  - Pela seleção: segurar um cartão, ou o atalho "Montar lista" do painel ou "Nova lista".
  - No editor: reordenar (`onReorderItem`, cujo índice já vem ajustado; `onReorder` está depreciado), remover, adicionar, renomear e excluir.
- **Tempo de montagem (H2):** `listAssemblyTimerProvider` começa na primeira busca, filtro ou seleção e grava `QuestionList.assemblyStartedAt` na criação. Zera ao criar a lista ou em "Limpar".
- **PDF** (`features/export/list_pdf.dart`):
  - A4, sem gabarito, com Nome/Data, numeração, (A)–(E) e 7 linhas nas discursivas.
  - Cada questão vai em `pw.Inseparable`, para não quebrar no meio da página. O enunciado usa `RichText(overflow: TextOverflow.span)`; sem isso, texto mais alto que uma página derruba o PDF.
  - Se algo não couber, `buildListPdf` refaz sem agrupar.
- **Entrega do PDF** (`pdf_exporter.dart`):
  - Web: "Abrir PDF" abre um blob numa nova aba, e precisa rodar no toque, sem `await` antes. "Baixar PDF" baixa o arquivo.
  - Android: `layoutPdf` para visualizar ou imprimir e `sharePdf` para compartilhar.
  - A exportação conta (`registerExport`), mas o arquivo não é guardado.
- **Painel:** janelas móveis de 7 dias (`domain/dashboard_summary.dart`), justas em qualquer dia, inclusive na segunda-feira. Para conta nova, um convite substitui os números zerados.
- **FABs com `heroTag: null`:** com `StatefulShellRoute.indexedStack`, todas as abas ficam na mesma rota, e a hero tag padrão repetida quebra a transição de saída.
- **Categorização:** área (4, padrão ENEM) → matéria (catálogo fixo) → assunto (1 tag livre, opcional). Matemática tem uma matéria só, que entra preenchida automaticamente.
- **Offline:**
  - Fonte Inter embutida (`assets/fonts`, gerada por `tool/build_fonts.py`), também usada no PDF.
  - Build web com `--no-web-resources-cdn`, que embute o CanvasKit.
  - Não usar `PdfPreview`, `Printing.raster` nem `Printing.info()` na web, porque baixam o pdf.js de CDN. `layoutPdf` e `sharePdf` funcionam sem rede.
  - Nada de emoji na interface (o glifo viria de CDN).
- **Cloud Storage exige o plano Blaze desde 03/02/2026**, então fica de fora. A imagem vai compactada (até ~300 KB) para um documento separado do Firestore; na demo, fica na memória.
- **Config do Firebase fora do git:** `--dart-define-from-file=env/firebase.json`. Sem esse arquivo, o app roda só em modo demo.
- **Firebase, o mais simples possível** (fatia 5): Auth com e-mail e senha e Firestore com regras por usuário.
  - Inicialização em segundo plano, com timeout de 12 s (`data/firebase/firebase_bootstrap.dart`). Na web, o SDK vem do CDN gstatic; sem internet, o status fica `unavailable` e a demo segue normal.
  - A sessão **escuta** o Auth (`ref.listen`) e nunca derruba uma `DemoSession` ativa; há teste de widget para isso.
  - Os repositórios dependem de `dataOwnerProvider` (o `uid`), então mudar o nome não os recria. O Auth é lido via `userChanges()`, para o nome gravado no cadastro aparecer na hora.
  - Escritas no Firestore esperam no máximo 4 s (`commitOrQueue`): sem rede, ficam na fila e a tela não trava.
  - Modelo de dados:
    - `users/{uid}`: perfil (nome, e-mail, `referralSource` da H4, `platformsBefore`, `termsVersion`, `termsAcceptedAt`);
    - `/questions`, `/questionImages` (Blob até 350 KB), `/lists` e `/events`;
    - `admins/{uid}`: criado no console.
  - Excluir a conta (LGPD) pede a senha, reautentica, apaga as subcoleções e o perfil, e por fim o usuário do Auth.
  - Mensagens de erro do Auth em português (`FirebaseAuthRepository.messageFor`).
- **Emuladores:** projeto `demo-iago`, que não precisa de conta nem login.
  - Auth na porta 9099 e Firestore na **8085**: a 8080 está ocupada nesta máquina por outro programa.
  - Na web, com emulador, o SDK tenta `accounts:lookup` em produção ao restaurar a sessão, porque isso acontece antes do `useAuthEmulator`. É inofensivo e só ocorre no emulador.
- **Métricas do piloto** (fatia 7, desejável):
  - Eventos em `users/{uid}/events`, via `MetricsLogger`, que nunca trava a tela:
    - `signed_up`: origem e plataformas antes;
    - `question_saved`: segundos e `questionType`;
    - `list_created`;
    - `list_exported`: `assemblySeconds` na 1ª exportação, `questionCount`, `exportIndex`;
    - `active`: id `active-AAAA-MM-DD`, no máximo um por dia;
    - `satisfaction` / `satisfaction_dismissed`.
  - `MetricEvent.toMap` grava `type`/`at` por último, porque um dado chamado `type` já sobrescreveu o tipo uma vez.
  - Pesquisa de satisfação (0–10 + plataformas agora) uma única vez, depois da 3ª exportação (`maybeAskSatisfaction`). Na demo, a seed tem 1 exportação, então a do roteiro (a 2ª) não abre a pesquisa.
  - Tela `/metricas`: H1–H4 calculadas na hora (`domain/pilot_metrics.dart`), cada valor ao lado da meta, com "Meta atingida", "Abaixo da meta" ou "Sem dados ainda".
    - Na demo: 20 usuários fictícios (`data/local/simulated_pilot.dart`, determinístico) e a faixa "DADOS SIMULADOS". Resultado de propósito misto: retenção 38% e listas/semana 0,8 ficam abaixo da meta.
    - Nas contas: só admin. Para virar admin, criar no console do Firestore o documento `admins/{uid}`, com qualquer campo.
  - **Linha de base da H2: 30 min é provisório** (`realPilotParameters` em `features/metrics/metrics_providers.dart`). O grupo deve trocar pelo número das entrevistas.
- **Identidade visual** (sem o deck oficial): índigo `#4F46E5` com a variante `fidelity` do M3, selo Beta âmbar, logo com degradê fixo. Os tokens estão em `lib/app/theme.dart`.
- **Git:** commits pequenos por fatia, com mensagem em português; `flutter analyze` sem avisos e `flutter test` verde antes de cada um. Autor local: Fred <frediro1910@gmail.com>.
- **Repositório e entrega (03/11):**
  - [github.com/FredECI/IaGo](https://github.com/FredECI/IaGo), **privado**. Para abrir ao público: `gh repo edit FredECI/IaGo --visibility public --accept-visibility-change-consequences`. Para dar acesso a um colega: `gh api -X PUT repos/FredECI/IaGo/collaborators/<usuario>`.
  - O APK sai do CI, porque o runner já tem as licenças do Android. Só ARM (`--target-platform android-arm,android-arm64`) e com `useLegacyPackaging = true`, o que levou o APK de 62 para 21 MB. Ele está na release `v0.1.0-beta` (prerelease), como `IaGo-Beta-0.1.apk`.
  - O `firebase.json` declara o banco (`southamerica-east1`; o deploy cria se não existir) e o login por e-mail e senha (`auth.providers`, aplicado por `deploy --only auth` no 1º app do projeto). Nada se faz no console.
  - O modo automático do Claude Code bloqueia três coisas: extrair credenciais (como a do Git Credential Manager), gravar secrets e publicar no Hosting. O deploy de `firestore,auth` passou. Logins, secrets e `deploy --only hosting` ficam com o Fred.
- **Projeto Firebase real (03/11):** `iago-beta` (nº 958140378539), no plano Spark, da conta frediro1910@gmail.com.
  - Firestore `(default)`, Standard, em `southamerica-east1`, com regras e índices publicados. Login por e-mail e senha ativo.
  - Apps: Web `1:958140378539:web:cc9bfd557bc11eed49f6ee` e Android `1:958140378539:android:71a8c5564031232949f6ee` (`br.ufrj.iago`).
  - O `env/firebase.json` foi gerado com `apps:sdkconfig` e fica fora do git. O `.firebaserc` tem `default` = `iago-beta` e o alias `demo` = `demo-iago`.
  - Verificado em 03/11 pelo `drive.js` em `localhost`, com `ALLOW_HOSTS=www.gstatic.com,googleapis.com`: cadastro → salvar → recarregar → sair/entrar → excluir conta → o login falha.
  - Para a CLI criar projetos, a conta precisa ter aceitado os termos do Firebase no console, senão o `addFirebase` dá 403. Na primeira tentativa, isso deixou dois projetos vazios do Google Cloud (`iago-beta-ufrj` e `iago-ufrj-2026`), para o Fred apagar.

## Ambiente desta máquina (instalado em 03/11)

- Flutter: `C:\Users\Fred\dev\flutter`. JDK 21: `C:\Users\Fred\dev\jdk-21`. Android SDK: `%LOCALAPPDATA%\Android\Sdk` (só as cmdline-tools).
- Firebase CLI 15.34.2 (npm global), logado como frediro1910@gmail.com. No PowerShell, chamar `firebase.cmd`: a política de execução bloqueia o `firebase.ps1`. FlutterFire CLI 1.4.1 (no Git Bash, chamar `flutterfire.bat`).
- GitHub CLI 2.103.3, portátil, em `C:\Users\Fred\dev\gh\bin`; logado como **FredECI** (escopos `repo` e `workflow`).
- O PATH do usuário já inclui Flutter e gh, mas o VS Code só enxerga depois de reiniciar. Em terminal antigo, rode antes: `$env:Path = "$env:USERPROFILE\dev\flutter\bin;$env:USERPROFILE\dev\gh\bin;$env:Path"`.
- Chave de debug do Android em `%USERPROFILE%\.android\debug.keystore` (senhas padrão `android`), criada em 03/11 para o secret `ANDROID_DEBUG_KEYSTORE`.
- As licenças do Android não foram aceitas nesta máquina. Não fazem falta, porque o APK sai do CI; só seriam necessárias para gerar o APK aqui.

## Pendências do Fred (e o que fazer em seguida)

1. **Publicar o site** (o Claude não consegue). O `build/web` já tem o build com Firebase e o APK em `build/web/IaGo-Beta-0.1.apk`:
   ```powershell
   cd C:\IaGo; firebase.cmd deploy --only hosting --project iago-beta
   ```
   Depois, Claude testa o site em https://iago-beta.web.app (demo e conta real).
2. **Apagar os dois projetos vazios** criados por engano. Em cada link, clicar em "Desligar" e digitar o ID:
   - https://console.cloud.google.com/iam-admin/settings?project=iago-beta-ufrj
   - https://console.cloud.google.com/iam-admin/settings?project=iago-ufrj-2026
3. **Secrets do CI** (opcional; o Claude não consegue gravar). Os dois comandos estão no README, seção CI. Com eles, o APK ganha o login real e uma assinatura fixa. Depois, Claude:
   - roda o CI de novo: `gh workflow run CI -R FredECI/IaGo`;
   - troca o APK da release: `gh release upload v0.1.0-beta IaGo-Beta-0.1.apk --clobber -R FredECI/IaGo`;
   - copia o APK para `build/web`, e o Fred publica de novo, como no item 1.
4. **Admin das métricas reais:** criar `admins/{uid}` no console do Firestore.
5. **Ensaio**: seguir o [DEMO.md](DEMO.md). O vídeo, as capturas e o PDF do plano B estão em `docs/demo/`. Para regenerar, rodar o `drive.js` com `RECORD_VIDEO`.

## Comandos úteis

```bash
flutter pub get
flutter analyze                      # precisa sair "No issues found!"
flutter test                         # unitários + widget
flutter run -d chrome                # desenvolvimento na web
flutter build web --release --no-web-resources-cdn
python -m http.server 8765 --bind 127.0.0.1 --directory build/web   # serve o build
# Firebase local (emuladores, sem conta):
firebase emulators:start --only auth,firestore --project demo-iago
flutter run -d chrome --dart-define-from-file=env/emulator.json
# Testes das regras do Firestore (cd firestore-tests && npm install na 1ª vez):
firebase emulators:exec --only firestore --project demo-iago "node --test firestore-tests/rules.test.mjs"
# Firebase de verdade (env/firebase.json fora do git, modelo em env/firebase.example.json):
flutter run -d chrome --dart-define-from-file=env/firebase.json
# Capturas a 360 px, bloqueando pedidos externos (prova de offline):
cd tool/screenshots && npm install && node drive.js http://127.0.0.1:8765/ shots "click:Entrar como Pedro" "shot:painel"
```

Passos do `drive.js`:

- `click:<texto>`: toca pelo rótulo de acessibilidade.
- `field:<rótulo>`: foca um campo de texto. O clique por coordenada **não** foca input no Flutter web.
- `type:<texto>`: digita.
- `paste:<texto com \n>`: cola de uma vez, como Ctrl+V.
- `scroll:<px>`, `wait:<ms>`, `shot:<nome>`, `dump`: lista a árvore de semântica.
- `focus`: mostra o elemento focado.
- `reload`: recarrega a página.
- Variável `ALLOW_HOSTS=www.gstatic.com` libera o SDK do Firebase, necessária para testar contas.
- `newtab:<texto>`: toca e confirma que abriu uma aba nova.
- `download:<texto>|<arquivo>`: toca e salva o download (por exemplo, o PDF).

## Status

| Fatia | Situação |
| --- | --- |
| 1. Esqueleto, tema, navegação, modo demo | **Pronta (03/11)**: 46 testes verdes, analyze limpo, build web sem nenhum pedido externo |
| 2. Salvar, listar, buscar, filtrar | **Pronta (03/11)**: 61 testes; fluxo de colar e salvar, busca "função" + filtros = 9 verificados no build web |
| 3. Categorização (autocompletar, hierarquia, contadores) | **Pronta (03/11)**: tela "Por conteúdo" (área → matéria → assunto com contagens; tocar aplica o filtro). 66 testes |
| 4. Listas e PDF | **Pronta (03/11)**: 82 testes; filtro → lista → PDF verificado no build web (aba nova + download), PDF conferido página a página |
| 5. Firebase Auth + Firestore | **Pronta (03/11)**: 87 testes Flutter e 6 de regras. Cadastro → salvar → recarregar → sair/entrar → excluir conta verificado nos emuladores e no projeto real `iago-beta` |
| 6. Painel (resumo relativo) | **Pronta (03/11)**: "8 questões nos últimos 7 dias, 3 a mais que nos 7 anteriores" (vira "9, 4 a mais" depois de salvar ao vivo), barras de comparação, listas e área com mais questões. 90 testes |
| 7. Métricas (desejável) | **Pronta (03/11)**: 97 testes; tela com dados simulados verificada no web; eventos e visão de admin com dados reais verificados nos emuladores |
| 8. Deploy (desejável) | **Em andamento (03/11)**: repositório privado `FredECI/IaGo`; CI verde (analyze, 97 testes, 6 de regras, build web e APK); APK de 21 MB na release `v0.1.0-beta`, só com o modo demo; Firebase `iago-beta` configurado e verificado. **Falta:** o Fred publicar o Hosting (pendência 1) |
