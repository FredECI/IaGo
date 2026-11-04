# IaGo — Beta 0.1

**IaGo** (Inteligência Artificial de Gerenciamento e Organização de Estudos) reúne num só lugar as questões que o estudante encontra em várias plataformas. Ele organiza tudo por conteúdo e tipo e monta listas em PDF para estudar ou levar à aula de reforço.

Este beta implementa o pilar **Agrega**, com registro manual. **Direciona** (metas e prazos) e **Conecta** (comunidades) aparecem como "Em breve".

Projeto acadêmico de Caio Peixoto, Fred, João Ricardo, Luiz e Nicolas (UFRJ). Roteiro da apresentação em [DEMO.md](DEMO.md).

## Links

- **Código:** [github.com/FredECI/IaGo](https://github.com/FredECI/IaGo) (repositório privado).
- **APK para Android:** página [Releases](https://github.com/FredECI/IaGo/releases) do repositório, gerado pelo CI.

## O que tem nesta versão

- **Modo demonstração** em 1 toque: conta do Pedro com 40 questões originais e 2 listas, guardadas só no aparelho e funcionando sem internet.
- **Cadastro e login** com e-mail e senha, "Como você conheceu o IaGo?", aceite de termos (LGPD), recuperação de senha e exclusão da conta com todos os dados.
- **Salvar questão** de qualquer plataforma: colar o texto separa as alternativas A–E sozinho. Inclui área → matéria → assunto (com sugestões), origem, link, imagem compactada e observações.
- **Busca e filtros** (área, matéria, assunto, tipo, plataforma) com contadores, e uma visão do acervo por conteúdo.
- **Listas** montadas pelo filtro ou por seleção, com reordenação. O **PDF** é gerado na hora, no aparelho, sem gabarito e com linhas de resposta nas discursivas.
- **Painel** com o resumo da semana sempre comparado com a anterior.
- **Métricas do piloto** (H1–H4) para administradores; na demo, com dados simulados.

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

O Auth do emulador fica na porta 9099 e o Firestore na 8085.

### Com o Firebase de verdade

1. Crie o projeto no [console do Firebase](https://console.firebase.google.com) no plano **Spark** (gratuito, sem cartão). Ative **Authentication → E-mail/senha** e crie o **Firestore**.
2. Registre um app **Web** e um **Android** (`br.ufrj.iago`). Copie `env/firebase.example.json` para `env/firebase.json`, que fica fora do git, e preencha com os valores do console.
3. Rode com:
   ```bash
   flutter run -d chrome --dart-define-from-file=env/firebase.json
   ```
4. Publique as regras do Firestore:
   ```bash
   firebase deploy --only firestore:rules --project <id-do-projeto>
   ```
5. Para ver as métricas reais, crie no Firestore o documento `admins/{uid}`, com qualquer campo, para cada administrador.

O Cloud Storage não é usado, porque exige o plano pago. As imagens vão compactadas, com até ~300 KB, num documento do Firestore.

## Testar

```bash
flutter analyze                # deve terminar com "No issues found!"
flutter test                   # unitários e de widget (tela de 360 px)

# Regras do Firestore no emulador (na 1ª vez: cd firestore-tests && npm install)
firebase emulators:exec --only firestore --project demo-iago "node --test firestore-tests/rules.test.mjs"
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

## Publicar a versão web (Firebase Hosting)

```bash
firebase login
flutter build web --release --no-web-resources-cdn --dart-define-from-file=env/firebase.json
firebase deploy --only hosting,firestore:rules --project <id-do-projeto>
```

## CI (GitHub Actions)

O workflow `.github/workflows/ci.yml` roda a cada push na `main` e em pull requests:

- `flutter analyze` e `flutter test`;
- os testes das regras do Firestore no emulador;
- o build web e o APK, guardados como artefatos por 14 dias.

Dois secrets opcionais do repositório mudam os builds:

- `FIREBASE_ENV_JSON`, com o conteúdo do `env/firebase.json`. Sem ele, os builds só têm o modo demonstração.
- `ANDROID_DEBUG_KEYSTORE`, com o `debug.keystore` em base64. Com ele, todo APK sai com a mesma assinatura e a versão nova instala por cima da anterior. Sem ele, é preciso desinstalar a versão antiga antes.

Para gravá-los (PowerShell, na raiz do projeto, com o `gh` logado):

```powershell
Get-Content env\firebase.json -Raw | gh secret set FIREBASE_ENV_JSON -R FredECI/IaGo
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.android\debug.keystore")) | gh secret set ANDROID_DEBUG_KEYSTORE -R FredECI/IaGo
```

## Capturas e vídeo

O roteiro `tool/screenshots/drive.js` abre o build web no Chrome a 360 px e bloqueia qualquer pedido fora do localhost. Assim ele também prova que o app roda offline. As capturas e o vídeo do plano B ficam em [docs/demo](docs/demo).

```bash
cd tool/screenshots && npm install
RECORD_VIDEO=video node drive.js http://127.0.0.1:8765/ shots "shot:entrada" "click:Entrar como Pedro" "shot:painel"
```

## Estrutura

```
lib/
  app/        tema, rotas (go_router), inicialização, barra de navegação
  core/       utilitários (texto, datas, ids, imagem, config do Firebase)
  domain/     modelos e regras puras (questão, lista, filtros, painel, métricas)
  data/       repositórios: interfaces, local (demo) e Firebase
  features/   telas: entrada e cadastro, painel, questões, listas, PDF, conta, métricas
  shared/     marca e widgets comuns
test/         testes unitários e de widget
firestore-tests/  testes das regras do Firestore (Node, emulador)
tool/         geração de fontes e ícones, roteiro de capturas
docs/demo/    capturas, PDF e vídeo do roteiro de demonstração
```

## Fontes e licenças

- A fonte [Inter](https://github.com/rsms/inter) está sob a SIL Open Font License (`assets/fonts/OFL.txt`).
- O ícone usa o glifo `auto_stories` dos Material Icons (Apache 2.0).
- As questões de exemplo foram escritas para este protótipo e não vêm de plataformas comerciais.
