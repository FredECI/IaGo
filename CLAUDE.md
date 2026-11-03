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
- **Identidade visual** (sem o deck oficial): índigo `#4F46E5` com a variante `fidelity` do M3, selo Beta âmbar, logo com degradê fixo. Os tokens estão em `lib/app/theme.dart`.
- **Git:** commits pequenos por fatia, com mensagem em português; `flutter analyze` sem avisos e `flutter test` verde antes de cada um. Autor local: Fred <frediro1910@gmail.com>.

## Ambiente desta máquina (instalado em 03/11)

- Flutter: `C:\Users\Fred\dev\flutter`. JDK 21: `C:\Users\Fred\dev\jdk-21`. Android SDK: `%LOCALAPPDATA%\Android\Sdk` (só as cmdline-tools por enquanto).
- Firebase CLI 15.34.2 (npm global). FlutterFire CLI 1.4.1 (no Git Bash, chamar `flutterfire.bat`).
- O PATH do usuário já foi atualizado, mas o VS Code só enxerga depois de reiniciar. Em terminal antigo, rode antes: `$env:Path = "$env:USERPROFILE\dev\flutter\bin;$env:Path"`.
- **Pendente (Fred):** aceitar as licenças do Android com `sdkmanager --licenses` (comando completo no histórico da sessão de 03/11). Depois, instalar `platform-tools` e a plataforma.

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
| 5. Firebase Auth + Firestore | **Pronta nos emuladores (03/11)**: 87 testes Flutter e 6 de regras. Cadastro → salvar → recarregar → sair/entrar → excluir conta verificado no navegador. **Falta o projeto real (Fred)** |
| 6. Painel (resumo relativo) | **Pronta (03/11)**: "8 questões nos últimos 7 dias, 3 a mais que nos 7 anteriores" (vira "9, 4 a mais" depois de salvar ao vivo), barras de comparação, listas e área com mais questões. 90 testes |
| 7. Métricas (desejável) | — |
| 8. Deploy (desejável) | — |
