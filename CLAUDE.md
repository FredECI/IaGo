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
- **Categorização:** área (4, padrão ENEM) → matéria (catálogo fixo) → assunto (1 tag livre, opcional). Matemática tem uma matéria só, que entra preenchida automaticamente.
- **Offline:**
  - Fonte Inter embutida (`assets/fonts`, gerada por `tool/build_fonts.py`), também usada no PDF.
  - Build web com `--no-web-resources-cdn`, que embute o CanvasKit.
  - Não usar `PdfPreview`, `Printing.raster` nem `Printing.info()` na web, porque baixam o pdf.js de CDN. `layoutPdf` e `sharePdf` funcionam sem rede.
  - Nada de emoji na interface (o glifo viria de CDN).
- **Cloud Storage exige o plano Blaze desde 03/02/2026**, então fica de fora. A imagem vai compactada (até ~300 KB) para um documento separado do Firestore; na demo, fica na memória.
- **Config do Firebase fora do git:** `--dart-define-from-file=env/firebase.json`. Sem esse arquivo, o app roda só em modo demo.
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
# Capturas a 360 px, bloqueando pedidos externos (prova de offline):
cd tool/screenshots && npm install && node drive.js http://127.0.0.1:8765/ shots "click:Entrar como Pedro" "shot:painel"
```

## Status

| Fatia | Situação |
| --- | --- |
| 1. Esqueleto, tema, navegação, modo demo | **Pronta (03/11)**: 46 testes verdes, analyze limpo, build web sem nenhum pedido externo |
| 2. Salvar, listar, buscar, filtrar | Próxima |
| 3. Categorização (autocompletar, hierarquia, contadores) | — |
| 4. Listas e PDF | — |
| 5. Firebase Auth + Firestore | — |
| 6. Painel (resumo relativo) | — |
| 7. Métricas (desejável) | — |
| 8. Deploy (desejável) | — |
