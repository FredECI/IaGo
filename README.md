# IaGo

**IaGo** (Inteligência Artificial de Gerenciamento e Organização de Estudos) reúne num só lugar as questões que o estudante encontra em várias plataformas. Ele organiza tudo por conteúdo e tipo, monta listas em PDF para estudar ou levar à aula de reforço e, no MVP, ajuda a planejar a rotina e a trocar dúvidas com outros estudantes.

**Situação:**

- **Publicado:** Beta 0.1, só com o pilar **Agrega** (registro manual, busca, listas e PDF).
- **Em desenvolvimento:** MVP de 27/11/2026, com os três pilares em forma mínima (Agrega, **Direciona** e **Conecta**), na branch `feat/mvp`. O site e o APK continuam os do beta até a publicação do MVP.

Projeto acadêmico de Caio Peixoto, Fred, João Ricardo, Luiz e Nicolas (UFRJ). Roteiro da apresentação em [DEMO.md](DEMO.md).

## Links

- **Versão web (beta):** [iago-beta.web.app](https://iago-beta.web.app), com contas reais e modo demonstração.
- **APK para Android (beta):** [IaGo-Beta-0.1.apk](https://github.com/FredECI/IaGo/releases/download/v0.1.0-beta/IaGo-Beta-0.1.apk) (cerca de 20 MB), na release [v0.1.0-beta](https://github.com/FredECI/IaGo/releases/tag/v0.1.0-beta). É gerado pelo CI e tem o modo demonstração e as contas reais. O plano gratuito do Firebase não aceita `.apk` no Hosting. O APK do MVP sairá na release `v0.2.0`, depois do teste no celular.
- **Código:** [github.com/FredECI/IaGo](https://github.com/FredECI/IaGo). Para contribuir, veja [Como contribuir](#como-contribuir).

## O que tem nesta versão

### Beta 0.1 (publicado)

- **Modo demonstração** em 1 toque: conta do Pedro com 40 questões originais e 2 listas, guardadas só no aparelho e funcionando sem internet.
- **Cadastro e login** com e-mail e senha, "Como você conheceu o IaGo?", aceite de termos (LGPD), recuperação de senha e exclusão da conta com todos os dados.
- **Salvar questão** de qualquer plataforma: colar o texto separa as alternativas A–E sozinho. Inclui área → matéria → assunto (com sugestões), origem, link, imagem compactada e observações.
- **Busca e filtros** (área, matéria, assunto, tipo, plataforma) com contadores, e uma visão por conteúdo.
- **Listas** montadas pelo filtro ou por seleção, com reordenação. O **PDF** é gerado na hora, no aparelho, sem gabarito e com linhas de resposta nas discursivas.
- **Painel** com o resumo da semana, sempre comparado com a anterior.
- **Métricas do piloto** (H1–H4) para administradores; na demo, com dados simulados.

### MVP (em desenvolvimento, `feat/mvp`)

- **Acervo do ENEM** (1.687 questões, só leitura): busca, filtros, detalhe com origem e crédito, "Salvar em Minhas questões", "Montar lista" (até 30 questões) e a tela **Fontes e licenças**. Sem gabarito e sem imagens. Abre sem internet.
- **Avaliação de questões** pelos membros do piloto: dificuldade e qualidade. O resumo só aparece com 3 ou mais avaliações.
- **Importação por colagem** em lote, com revisão antes de salvar. Prints e PDF com IA estão em construção (dependem do P2a).
- **Direciona:** objetivo de estudo, etapas com prazo, concluir, adiar uma vez e link para a agenda. As etapas saem pelas regras; a proposta pela IA depende do P2a.
- **Conecta:** comunidades, posts e respostas de texto, "Ajudou", denúncia, moderação e exclusão em cascata. Fica desligado para contas reais até a definição dos moderadores; na demo, funciona com conteúdo simulado.
- **Termos novos com reaceite** e declaração de idade (18 anos ou mais) no cadastro.
- **Métricas H1 a H6** para administradores. H5 e H6 são provisórias.

## Requisitos

- Flutter 3.47.x stable (Dart 3.13) e Chrome.
- Android: o CI gera o APK (veja [CI](#ci-github-actions)). Para gerar na sua máquina, é preciso JDK 17 ou mais novo e o Android SDK com as licenças aceitas (`flutter doctor --android-licenses`).
- Firebase (opcional para rodar a demo): Node 20+ e `npm install -g firebase-tools`. Java 21 para os emuladores.

## Rodar

```bash
flutter pub get
flutter run -d chrome          # só o modo demonstração
```

Sem configuração do Firebase, a tela inicial oferece apenas **Entrar como Pedro (demonstração)**.

### Com Firebase local (emuladores, sem conta Google)

```bash
firebase emulators:start --only auth,firestore --project demo-iago
flutter run -d chrome --dart-define-from-file=env/emulator.json
```

O Auth do emulador fica na porta 9099 e o Firestore na 8085, como está em `firebase.json`.

### Com o Firebase de verdade

O projeto real é o **`iago-beta`**, no plano Spark (gratuito, sem cartão). O `env/firebase.json`, que fica fora do git, já aponta para ele na máquina do Fred:

```bash
flutter run -d chrome --dart-define-from-file=env/firebase.json
```

Para testar a IA em localhost, acrescente o segundo arquivo, que só tem o token de depuração do App Check:

```bash
flutter run -d chrome --dart-define-from-file=env/firebase.json --dart-define-from-file=env/appcheck-debug.json
```

- `env/firebase.json`: a configuração do Firebase. O build de publicação usa **só** este arquivo.
- `env/appcheck-debug.json`: só o token de depuração do App Check. Ele fica fora do git e **nunca** vai para `env/firebase.json`, para o secret `FIREBASE_ENV_JSON` (que vai embutido no site público) nem para o build de publicação.
- As chaves do App Check (`FIREBASE_APPCHECK_WEB_SITE_KEY` e `FIREBASE_APPCHECK_ANDROID_SITE_KEY`) estão no modelo `env/firebase.example.json`. O código ainda não as lê: isso entra com a tarefa F5b. Até lá, a flag do App Check não tem efeito.
- Sem `env/firebase.json`, o app roda só em modo demonstração.

Para montar um projeto do zero, use só a linha de comando. O `firebase.json` já declara o banco (Firestore em `southamerica-east1`), as regras e o login por e-mail e senha.

1. Na primeira vez, a conta Google precisa aceitar os termos do Firebase no [console](https://console.firebase.google.com). Sem isso, a criação pela CLI falha com erro 403.
2. Crie o projeto e registre os apps:
   ```bash
   firebase login
   firebase projects:create <id-do-projeto> --display-name IaGo
   firebase apps:create web "IaGo Web" --project <id-do-projeto>
   firebase apps:create android "IaGo Android" --package-name br.ufrj.iago --project <id-do-projeto>
   ```
3. Copie `env/firebase.example.json` para `env/firebase.json` e preencha com a saída de `firebase apps:sdkconfig web` e `firebase apps:sdkconfig android`. A chave do Android é o `current_key`.
4. Crie o banco, publique as regras e ative o login por e-mail e senha:
   ```bash
   firebase deploy --only firestore,auth --project <id-do-projeto>
   ```
5. Para ver as métricas reais, crie no Firestore o documento `admins/{uid}`, com qualquer campo, para cada administrador.

No PowerShell, chame `firebase.cmd` em vez de `firebase`. A política de execução padrão do Windows bloqueia o `firebase.ps1` que o npm instala.

O Cloud Storage não é usado, porque exige o plano pago. As imagens vão compactadas, com até ~300 KB, num documento do Firestore.

## Testar

```bash
flutter analyze                # deve terminar com "No issues found!"
flutter test                   # unitários e de widget (tela de 360 px)
```

Testes das regras do Firestore (na 1ª vez: `cd firestore-tests && npm install`). As portas são fixas, então rode uma vez por vez.

```bash
# Com o emulador de Auth: roda todos, inclusive exclusão de conta, e-mail verificado e termos
firebase emulators:exec --only auth,firestore --project demo-iago "node --test firestore-tests/*.test.mjs"

# Só o Firestore, como no CI: os testes que precisam do Auth são pulados
firebase emulators:exec --only firestore --project demo-iago "node --test firestore-tests/*.test.mjs"
```

## Gerar os builds

```bash
# Web, com o CanvasKit embutido (não depende de CDN)
flutter build web --release --no-web-resources-cdn [--dart-define-from-file=env/firebase.json]

# Servir o build localmente (ex.: no notebook da apresentação, sem internet)
python -m http.server 8765 --directory build/web

# APK de release para ARM de 32 e 64 bits (todos os celulares), assinado com a
# chave de debug, o que basta para instalar por arquivo
flutter build apk --release --target-platform android-arm,android-arm64 [--dart-define-from-file=env/firebase.json]
# → build/app/outputs/flutter-apk/app-release.apk
```

### Acervo do ENEM (só na máquina de desenvolvimento)

```bash
python -I tool/acervo/build_acervo.py
```

O script gera `assets/acervo/acervo-v1.json` a partir de `tool/acervo/sources.json`. Na primeira vez, leva cerca de 1,5 min (cache em `build/acervo-cache/`, fora do git). O app nunca acessa a API. Detalhes em [tool/acervo/README.md](tool/acervo/README.md).

## Publicar a versão web (Firebase Hosting)

```bash
flutter build web --release --no-web-resources-cdn --dart-define-from-file=env/firebase.json
firebase deploy --only hosting --project iago-beta
```

O site fica em [iago-beta.web.app](https://iago-beta.web.app). No plano Spark, o Hosting tem 360 MB de tráfego por dia e recusa arquivos `.apk`, `.exe`, `.dll`, `.bat` e `.ipa`. Por isso o APK fica na release do GitHub.

## CI (GitHub Actions)

O workflow `.github/workflows/ci.yml` roda em push para `main` e para as branches `feat/**`, em pull requests e de forma manual:

- `flutter analyze` e `flutter test`;
- os testes das regras do Firestore no emulador (só o Firestore, como acima);
- o build web, guardado como artefato por 14 dias;
- o APK, só na `main`. O APK das branches `feat/mvp*` sai pelo workflow manual `apk-manual.yml`.

Dois secrets opcionais do repositório mudam os builds:

- `FIREBASE_ENV_JSON`, com o conteúdo do `env/firebase.json`. Sem ele, os builds só têm o modo demonstração. Nunca grave nele o token de depuração do App Check.
- `ANDROID_DEBUG_KEYSTORE`, com o `debug.keystore` em base64. Com ele, todo APK sai com a mesma assinatura e a versão nova instala por cima da anterior. Sem ele, é preciso desinstalar a versão antiga antes.

No `FredECI/IaGo`, os dois estão configurados desde 04/11. Para gravá-los de novo, use o Git Bash, na raiz do projeto e com o `gh` logado:

```bash
gh secret set FIREBASE_ENV_JSON -R FredECI/IaGo < env/firebase.json
base64 -w0 ~/.android/debug.keystore | gh secret set ANDROID_DEBUG_KEYSTORE -R FredECI/IaGo
```

Evite o pipe do PowerShell: ele acrescenta um BOM e uma quebra de linha ao texto. O CI descarta os dois, mas o secret fica sujo.

## Capturas e vídeo

O roteiro `tool/screenshots/drive.js` abre o build web no Chrome a 360 px e bloqueia qualquer pedido fora do localhost. Assim ele também prova que o app roda offline. As capturas e o vídeo do plano B em [docs/demo](docs/demo) são do beta e serão regenerados depois da IA.

```bash
cd tool/screenshots && npm install
RECORD_VIDEO=video node drive.js http://127.0.0.1:8765/ shots "shot:entrada" "click:Entrar como Pedro" "shot:painel"
```

## Como contribuir

1. Instale o Flutter 3.47 (stable) e rode o app:
   ```bash
   git clone https://github.com/FredECI/IaGo.git
   cd IaGo
   flutter pub get
   flutter run -d chrome
   ```
   Sem o `env/firebase.json`, que não fica no repositório, o app abre só no modo demonstração, e isso basta para quase tudo. Para testar contas, use os emuladores (veja [Rodar](#rodar)).
2. Crie um branch e, antes de cada commit, rode:
   ```bash
   flutter analyze   # precisa terminar com "No issues found!"
   flutter test
   ```
3. Abra um pull request para a `main`. O CI roda os testes e gera o build web (e o APK, na `main`), e o Fred revisa. O trabalho do MVP fica na branch `feat/mvp`. Para enviar branches direto no repositório, sem fork, peça ao Fred para te adicionar como colaborador.

Convenções:
- Código e nomes em inglês. Textos da interface, comentários e documentação em português.
- Commits pequenos, com mensagem em português.
- Importe `package:material_ui/material_ui.dart`, nunca `package:flutter/material.dart`. No Flutter 3.47, o Material saiu do framework.

Congelamento de funcionalidades do MVP: **terça, 24/11, às 20h**. Depois disso, só correção de bugs.

## Estrutura

```
lib/
  app/        tema, rotas (go_router), inicialização, barra de navegação
  core/       utilitários (texto, datas, ids, imagem, config do Firebase)
  domain/     modelos e regras puras (questão, lista, filtros, painel, métricas,
              política de acesso, direção de estudo, comunidade, avaliação)
  data/       repositórios: interfaces, local (demo) e Firebase; ai/ (portas de IA)
  features/   telas: entrada e cadastro, painel, questões, acervo, importação,
              direciona, conecta, avaliação, listas, PDF, conta, métricas
  shared/     marca e widgets comuns
test/         testes unitários e de widget
firestore-tests/  testes das regras do Firestore (Node, emulador)
tool/         fontes e ícones, roteiro de capturas e o script local do acervo (acervo/)
assets/       fontes, ícones e o acervo do ENEM (acervo/acervo-v1.json)
docs/         spec do MVP, decisões (ADRs), guias, regras da comunidade e roteiro da demo
```

## Fontes e licenças

- **Questões do acervo (ENEM):** os textos são das provas do Exame Nacional do Ensino Médio (ENEM), do INEP, obtidos pela API de terceiros `api.enem.dev`, só na preparação do acervo. O app não acessa essa API. Cada questão traz o crédito, a origem e o link para a prova oficial, e a tela **Fontes e licenças** reúne tudo.
- **Licença:** não confirmamos que a licença do site do INEP se aplique às provas, e não afirmamos licença para elas. A decisão e o risco estão registrados na spec (decisão D4).
- **Pedidos de remoção:** se você é titular de algum texto e quer que ele saia do acervo, escreva para o e-mail do projeto, que ainda será definido (`AppInfo.projectContactEmail`). Se o pedido procede, a questão sai na versão seguinte do app.
- **Aviso sobre o conteúdo do ENEM:** o acervo reproduz textos das provas para uso educacional, com a formatação ajustada (as palavras não mudam). Não há gabarito nem imagens. Confira sempre o original.
- As questões de exemplo do Pedro foram escritas para este protótipo e não vêm de plataformas comerciais.
- A fonte [Inter](https://github.com/rsms/inter) está sob a SIL Open Font License (`assets/fonts/OFL.txt`).
- O ícone usa o glifo `auto_stories` dos Material Icons (Apache 2.0).
